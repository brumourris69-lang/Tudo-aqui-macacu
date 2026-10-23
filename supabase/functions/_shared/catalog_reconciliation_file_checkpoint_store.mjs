import { createHash, randomUUID } from "node:crypto";
import {
  lstat,
  mkdir,
  open,
  readFile,
  realpath,
  rename,
  rm,
} from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";

const MAX_REPORT_BYTES = 67_108_864;
const MAX_FINDINGS_PER_PAGE = 200;
const MAX_LOCK_WAIT_MS = 10_000;
const STATUSES = new Set([
  "canonical_missing",
  "invalid_canonical",
  "blocked_by_tombstone",
  "destination_newer",
  "version_conflict",
  "tombstone_projection_conflict",
  "in_sync_tombstone",
  "tombstone_outdated",
  "tombstone_missing",
  "projection_missing",
  "in_sync",
  "projection_outdated",
]);
const ACTION_FOR_STATUS = Object.freeze({
  canonical_missing: "manual_review",
  invalid_canonical: "manual_review",
  blocked_by_tombstone: "manual_review",
  destination_newer: "manual_review",
  version_conflict: "manual_review",
  tombstone_projection_conflict: "manual_review",
  in_sync_tombstone: "none",
  tombstone_outdated: "apply_tombstone",
  tombstone_missing: "apply_tombstone",
  projection_missing: "apply_projection",
  in_sync: "none",
  projection_outdated: "apply_projection",
});
const PROJECTION_FIELDS = Object.freeze([
  "id",
  "content_kind",
  "category_group",
  "name",
  "summary",
  "category",
  "subcategory",
  "location",
  "artwork",
  "image_url",
  "logo_url",
  "gallery_urls",
  "featured",
  "is_open",
  "maps_url",
  "hours",
  "services",
  "products",
  "additional_info",
  "promotion_title",
  "promotion_description",
  "public_contact_approved",
  "phone",
  "whatsapp",
  "instagram",
  "published",
  "active",
  "expires_at",
  "deleted_at",
  "catalog_version",
  "outbox_operation_id",
]);
const TOMBSTONE_FIELDS = Object.freeze([
  "id",
  "catalog_version",
  "outbox_operation_id",
  "deleted_at",
]);
const SUMMARY_STATUSES = new Set(STATUSES);

export class CatalogReconciliationFileCheckpointError extends Error {
  constructor(code = "checkpoint_storage_failed") {
    const safeCode =
      ["invalid_checkpoint", "checkpoint_conflict", "checkpoint_storage_failed"]
          .includes(code)
        ? code
        : "checkpoint_storage_failed";
    super(safeCode);
    this.name = "CatalogReconciliationFileCheckpointError";
    this.code = safeCode;
  }
}

/**
 * Local, single-host durable checkpoint storage. Reports contain only planner
 * recommendations with explicitly public payload fields. The caller must
 * choose a private directory and protect its Windows ACLs.
 */
export function createCatalogReconciliationFileCheckpointStore({
  directory,
  lockWaitMs = 2_500,
  now = Date.now,
}) {
  if (
    typeof directory !== "string" || !isAbsolute(directory) ||
    typeof now !== "function" ||
    !Number.isSafeInteger(lockWaitMs) || lockWaitMs < 100 ||
    lockWaitMs > MAX_LOCK_WAIT_MS
  ) {
    throw new CatalogReconciliationFileCheckpointError("invalid_checkpoint");
  }
  const root = resolve(directory);

  async function load(snapshotId) {
    validateSnapshotId(snapshotId);
    const report = await readReportFile(snapshotId);
    return report?.checkpoint ?? null;
  }

  async function loadReport(snapshotId) {
    validateSnapshotId(snapshotId);
    const report = await readReportFile(snapshotId);
    if (!report) return null;
    return structuredClone({
      checkpoint: report.checkpoint,
      findings: report.findings,
    });
  }

  async function commitPage({ expectedSequence, checkpoint, findings } = {}) {
    if (
      !Number.isSafeInteger(expectedSequence) || expectedSequence < 0 ||
      !validCheckpoint(checkpoint, checkpoint?.snapshotId) ||
      checkpoint.sequence !== expectedSequence + 1 ||
      !Array.isArray(findings) || findings.length > MAX_FINDINGS_PER_PAGE ||
      !findings.every(validFinding) ||
      new Set(findings.map(({ id }) => id)).size !== findings.length
    ) {
      throw new CatalogReconciliationFileCheckpointError("invalid_checkpoint");
    }
    const snapshotId = checkpoint.snapshotId;
    const serializedFindings = JSON.stringify(findings);
    if (Buffer.byteLength(serializedFindings, "utf8") > MAX_REPORT_BYTES) {
      throw new CatalogReconciliationFileCheckpointError("invalid_checkpoint");
    }

    const paths = await resolvePaths(snapshotId, true);
    const releaseLock = await acquireLock(paths.lockPath);
    let tempPath;
    try {
      const current = await readReportAtPath(paths.reportPath, snapshotId);
      const currentSequence = current?.checkpoint.sequence ?? 0;
      if (
        currentSequence !== expectedSequence ||
        (current && current.checkpoint.pageSize !== checkpoint.pageSize)
      ) {
        throw new CatalogReconciliationFileCheckpointError(
          "checkpoint_conflict",
        );
      }
      const nextReport = {
        storageSchemaVersion: 1,
        checkpoint: structuredClone(checkpoint),
        findings: [...(current?.findings ?? []), ...structuredClone(findings)],
      };
      if (!validReport(nextReport, snapshotId)) {
        throw new CatalogReconciliationFileCheckpointError(
          "invalid_checkpoint",
        );
      }
      const bytes = Buffer.from(JSON.stringify(nextReport), "utf8");
      if (bytes.byteLength > MAX_REPORT_BYTES) {
        throw new CatalogReconciliationFileCheckpointError(
          "invalid_checkpoint",
        );
      }
      tempPath = `${paths.reportPath}.${process.pid}.${randomUUID()}.tmp`;
      const handle = await open(tempPath, "wx", 0o600);
      try {
        await handle.writeFile(bytes);
        await handle.sync();
      } finally {
        await handle.close();
      }
      await rename(tempPath, paths.reportPath);
      tempPath = undefined;
    } catch (error) {
      if (error instanceof CatalogReconciliationFileCheckpointError) {
        throw error;
      }
      throw new CatalogReconciliationFileCheckpointError();
    } finally {
      if (tempPath) {
        try {
          await rm(tempPath, { force: true });
        } catch { /* only this store's unique temp file */ }
      }
      await releaseLock();
    }
  }

  async function readReportFile(snapshotId) {
    const paths = await resolvePaths(snapshotId, false);
    if (!paths) return null;
    return readReportAtPath(paths.reportPath, snapshotId);
  }

  async function resolvePaths(snapshotId, createDirectory) {
    const reportName = `${
      createHash("sha256").update(snapshotId, "utf8").digest("hex")
    }.json`;
    if (createDirectory) {
      try {
        await mkdir(root, { recursive: true, mode: 0o700 });
        await verifyRoot();
      } catch {
        throw new CatalogReconciliationFileCheckpointError();
      }
    } else {
      try {
        await verifyRoot();
      } catch (error) {
        if (error?.code === "ENOENT") return null;
        throw new CatalogReconciliationFileCheckpointError();
      }
    }
    return {
      reportPath: join(root, reportName),
      lockPath: join(root, `${reportName}.lock`),
    };
  }

  async function readReportAtPath(path, snapshotId) {
    try {
      const metadata = await lstat(path);
      if (
        !metadata.isFile() || metadata.isSymbolicLink() ||
        metadata.size > MAX_REPORT_BYTES
      ) {
        throw new CatalogReconciliationFileCheckpointError(
          "invalid_checkpoint",
        );
      }
      const report = JSON.parse(await readFile(path, "utf8"));
      if (!validReport(report, snapshotId)) {
        throw new CatalogReconciliationFileCheckpointError(
          "invalid_checkpoint",
        );
      }
      return report;
    } catch (error) {
      if (error?.code === "ENOENT") return null;
      if (error instanceof CatalogReconciliationFileCheckpointError) {
        throw error;
      }
      throw new CatalogReconciliationFileCheckpointError("invalid_checkpoint");
    }
  }

  async function verifyRoot() {
    const metadata = await lstat(root);
    if (!metadata.isDirectory() || metadata.isSymbolicLink()) {
      throw new Error("checkpoint directory is not a real directory");
    }
    const actualRoot = await realpath(root);
    const expected = resolve(root).toLocaleLowerCase("en-US");
    const actual = resolve(actualRoot).toLocaleLowerCase("en-US");
    if (actual !== expected) {
      throw new Error("checkpoint directory changed");
    }
  }

  async function acquireLock(lockPath) {
    const deadline = Date.now() + lockWaitMs;
    while (Date.now() <= deadline) {
      let handle;
      let ownsLockFile = false;
      try {
        handle = await open(lockPath, "wx", 0o600);
        ownsLockFile = true;
        await handle.writeFile(
          JSON.stringify({ pid: process.pid, createdAt: now() }),
        );
        await handle.sync();
        await handle.close();
        handle = undefined;
        return async () => {
          try {
            await rm(lockPath);
          } catch {
            throw new CatalogReconciliationFileCheckpointError();
          }
        };
      } catch (error) {
        if (handle) {
          try {
            await handle.close();
          } catch { /* close only the handle created by this attempt */ }
        }
        if (ownsLockFile) {
          try {
            await rm(lockPath, { force: true });
          } catch { /* remove only the lock acquired by this attempt */ }
        }
        if (error?.code !== "EEXIST") {
          throw new CatalogReconciliationFileCheckpointError();
        }
        await delay(20);
      }
    }
    throw new CatalogReconciliationFileCheckpointError("checkpoint_conflict");
  }

  return Object.freeze({ load, loadReport, commitPage });
}

function validReport(value, snapshotId) {
  return plainObject(value) &&
    sameKeys(value, ["storageSchemaVersion", "checkpoint", "findings"]) &&
    value.storageSchemaVersion === 1 &&
    validCheckpoint(value.checkpoint, snapshotId) &&
    Array.isArray(value.findings) && value.findings.every(validFinding);
}

function validCheckpoint(value, snapshotId) {
  return plainObject(value) && sameKeys(value, [
    "schemaVersion",
    "snapshotId",
    "pageSize",
    "cursor",
    "sequence",
    "scannedCount",
    "summary",
    "done",
  ]) && value.schemaVersion === 1 && typeof snapshotId === "string" &&
    value.snapshotId === snapshotId && value.snapshotId.length > 0 &&
    value.snapshotId.length <= 256 &&
    Number.isSafeInteger(value.pageSize) && value.pageSize >= 1 &&
    value.pageSize <= MAX_FINDINGS_PER_PAGE &&
    (value.cursor === null || validDocumentId(value.cursor)) &&
    Number.isSafeInteger(value.sequence) &&
    value.sequence >= 1 && Number.isSafeInteger(value.scannedCount) &&
    value.scannedCount >= 0 &&
    plainObject(value.summary) &&
    Object.keys(value.summary).every((key) => SUMMARY_STATUSES.has(key)) &&
    Object.values(value.summary).every((count) =>
      Number.isSafeInteger(count) && count >= 0
    ) &&
    typeof value.done === "boolean";
}

function validFinding(value) {
  if (
    !plainObject(value) ||
    !Object.keys(value).every((key) =>
      ["id", "status", "action", "payload"].includes(key)
    ) ||
    !sameKeys(
      value,
      Object.hasOwn(value, "payload")
        ? ["id", "status", "action", "payload"]
        : ["id", "status", "action"],
    ) ||
    !validDocumentId(value.id) || !STATUSES.has(value.status) ||
    value.action !== ACTION_FOR_STATUS[value.status]
  ) return false;
  if (!Object.hasOwn(value, "payload")) {
    return !["apply_projection", "apply_tombstone"].includes(value.action);
  }
  if (value.action === "apply_projection") {
    return validProjection(value.payload) && value.payload.id === value.id;
  }
  if (value.action === "apply_tombstone") {
    return validTombstone(value.payload) && value.payload.id === value.id;
  }
  return false;
}

function validProjection(value) {
  return plainObject(value) && sameKeys(value, PROJECTION_FIELDS) &&
    validDocumentId(value.id) &&
    value.content_kind === "establishment" &&
    ["commerce", "services"].includes(value.category_group) &&
    [
      "name",
      "summary",
      "category",
      "subcategory",
      "image_url",
      "logo_url",
      "maps_url",
      "hours",
      "additional_info",
      "promotion_title",
      "promotion_description",
    ].every((key) => typeof value[key] === "string") &&
    (value.location === null || typeof value.location === "string") &&
    Number.isSafeInteger(value.artwork) &&
    value.artwork >= 0 && value.artwork <= 18 &&
    ["gallery_urls", "services", "products"].every((key) =>
      Array.isArray(value[key]) &&
      value[key].every((entry) => typeof entry === "string")
    ) &&
    ["featured", "is_open", "public_contact_approved", "published", "active"]
      .every((key) => typeof value[key] === "boolean") &&
    ["phone", "whatsapp", "instagram"].every((key) =>
      value[key] === null || typeof value[key] === "string"
    ) &&
    (value.public_contact_approved ||
      [value.phone, value.whatsapp, value.instagram].every((entry) =>
        entry === null
      )) &&
    ["expires_at", "deleted_at"].every((key) =>
      value[key] === null || validTimestamp(value[key])
    ) &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu
      .test(value.outbox_operation_id);
}

function validTombstone(value) {
  return plainObject(value) && sameKeys(value, TOMBSTONE_FIELDS) &&
    validDocumentId(value.id) &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu
      .test(value.outbox_operation_id) &&
    validTimestamp(value.deleted_at);
}

function validateSnapshotId(value) {
  if (typeof value !== "string" || value.length === 0 || value.length > 256) {
    throw new CatalogReconciliationFileCheckpointError("invalid_checkpoint");
  }
}

function validDocumentId(value) {
  return typeof value === "string" &&
    new TextEncoder().encode(value).byteLength > 0 &&
    new TextEncoder().encode(value).byteLength <= 1500 && value !== "." &&
    value !== ".." && !value.includes("/") &&
    (!value.startsWith("__") || !value.endsWith("__") ||
      /^__id\d+__$/u.test(value));
}

function validTimestamp(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function sameKeys(value, expected) {
  const keys = Object.keys(value);
  return keys.length === expected.length &&
    expected.every((key) => Object.hasOwn(value, key));
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null);
}

function delay(ms) {
  return new Promise((resolveDelay) => setTimeout(resolveDelay, ms));
}
