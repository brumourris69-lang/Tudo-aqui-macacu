import { createCatalogReconciliationPlan } from "./catalog_reconciliation.mjs";

const MAX_PAGE_SIZE = 200;
const MAX_PAGES_PER_RUN = 1000;

export class CatalogReconciliationScanError extends Error {
  constructor(code) {
    const safeCode = new Set([
        "invalid_scan_configuration",
        "invalid_checkpoint",
        "invalid_snapshot_page",
        "snapshot_expired",
        "snapshot_read_failed",
        "checkpoint_read_failed",
        "checkpoint_conflict",
        "checkpoint_commit_failed",
      ]).has(code)
      ? code
      : "snapshot_read_failed";
    super(safeCode);
    this.name = "CatalogReconciliationScanError";
    this.code = safeCode;
  }
}

/**
 * Resumable, read-only pagination around the single-page reconciliation planner.
 * The reader must keep snapshotId stable across every source and destination page.
 * The checkpoint store must atomically persist findings and checkpoint together.
 */
export async function runCatalogReconciliationScan({
  snapshotId,
  reader,
  checkpointStore,
  pageSize = 100,
  maxPages = 100,
}) {
  if (
    typeof snapshotId !== "string" || snapshotId.length === 0 ||
    snapshotId.length > 256 ||
    typeof reader?.readPage !== "function" ||
    typeof checkpointStore?.load !== "function" ||
    typeof checkpointStore?.commitPage !== "function" ||
    !Number.isSafeInteger(pageSize) || pageSize < 1 ||
    pageSize > MAX_PAGE_SIZE ||
    !Number.isSafeInteger(maxPages) || maxPages < 1 ||
    maxPages > MAX_PAGES_PER_RUN
  ) {
    throw new CatalogReconciliationScanError("invalid_scan_configuration");
  }

  let checkpoint;
  try {
    checkpoint = await checkpointStore.load(snapshotId);
  } catch {
    throw new CatalogReconciliationScanError("checkpoint_read_failed");
  }
  if (checkpoint === null) checkpoint = initialCheckpoint(snapshotId, pageSize);
  else if (!isValidCheckpoint(checkpoint, snapshotId, pageSize)) {
    throw new CatalogReconciliationScanError("invalid_checkpoint");
  }
  if (checkpoint.done) return result("complete", checkpoint);

  for (let pageNumber = 0; pageNumber < maxPages; pageNumber += 1) {
    let page;
    try {
      page = await reader.readPage({
        snapshotId,
        afterId: checkpoint.cursor,
        limit: pageSize,
      });
    } catch (error) {
      throw new CatalogReconciliationScanError(
        error?.code === "snapshot-expired"
          ? "snapshot_expired"
          : "snapshot_read_failed",
      );
    }

    const ids = validatePage(page, {
      snapshotId,
      cursor: checkpoint.cursor,
      pageSize,
    });
    let plan;
    try {
      plan = createCatalogReconciliationPlan({
        canonicalDocuments: page.canonicalDocuments,
        catalogRows: page.catalogRows,
        tombstones: page.tombstones,
      });
    } catch {
      throw new CatalogReconciliationScanError("invalid_snapshot_page");
    }

    const nextCheckpoint = {
      schemaVersion: 1,
      snapshotId,
      pageSize,
      cursor: page.nextCursor,
      sequence: checkpoint.sequence + 1,
      scannedCount: checkpoint.scannedCount + ids.length,
      summary: mergeSummary(checkpoint.summary, plan.summary),
      done: page.done,
    };
    try {
      await checkpointStore.commitPage({
        expectedSequence: checkpoint.sequence,
        checkpoint: nextCheckpoint,
        findings: plan.items,
      });
    } catch (error) {
      throw new CatalogReconciliationScanError(
        error?.code === "checkpoint_conflict"
          ? "checkpoint_conflict"
          : "checkpoint_commit_failed",
      );
    }
    checkpoint = nextCheckpoint;
    if (checkpoint.done) return result("complete", checkpoint);
  }

  return result("paused", checkpoint);
}

function initialCheckpoint(snapshotId, pageSize) {
  return {
    schemaVersion: 1,
    snapshotId,
    pageSize,
    cursor: null,
    sequence: 0,
    scannedCount: 0,
    summary: {},
    done: false,
  };
}

function isValidCheckpoint(value, snapshotId, pageSize) {
  return plainObject(value) && value.schemaVersion === 1 &&
    value.snapshotId === snapshotId &&
    value.pageSize === pageSize &&
    (value.cursor === null || isDocumentId(value.cursor)) &&
    Number.isSafeInteger(value.sequence) && value.sequence >= 0 &&
    Number.isSafeInteger(value.scannedCount) && value.scannedCount >= 0 &&
    plainObject(value.summary) &&
    Object.values(value.summary).every((count) =>
      Number.isSafeInteger(count) && count >= 0
    ) && typeof value.done === "boolean" &&
    (value.sequence > 0 ||
      (value.cursor === null && value.scannedCount === 0 && !value.done));
}

function validatePage(page, { snapshotId, cursor, pageSize }) {
  if (
    !plainObject(page) || page.snapshotId !== snapshotId ||
    !Array.isArray(page.canonicalDocuments) ||
    !Array.isArray(page.catalogRows) ||
    !Array.isArray(page.tombstones) || typeof page.done !== "boolean"
  ) {
    throw new CatalogReconciliationScanError("invalid_snapshot_page");
  }

  const ids = new Set();
  for (
    const collection of [
      page.canonicalDocuments,
      page.catalogRows,
      page.tombstones,
    ]
  ) {
    for (const value of collection) {
      if (!plainObject(value) || !isDocumentId(value.id)) {
        throw new CatalogReconciliationScanError("invalid_snapshot_page");
      }
      ids.add(value.id);
    }
  }
  const ordered = [...ids].sort(compareIds);
  if (
    ordered.length > pageSize ||
    ordered.some((id) => cursor !== null && compareIds(id, cursor) <= 0)
  ) {
    throw new CatalogReconciliationScanError("invalid_snapshot_page");
  }

  const expectedCursor = ordered.at(-1) ?? cursor;
  if (
    page.nextCursor !== expectedCursor || (!page.done && ordered.length === 0)
  ) {
    throw new CatalogReconciliationScanError("invalid_snapshot_page");
  }
  return ordered;
}

function mergeSummary(previous, current) {
  const merged = { ...previous };
  for (const [status, count] of Object.entries(current)) {
    merged[status] = (merged[status] ?? 0) + count;
  }
  return Object.fromEntries(
    Object.entries(merged).sort(([left], [right]) => left.localeCompare(right)),
  );
}

function result(state, checkpoint) {
  return Object.freeze({
    state,
    checkpoint: structuredClone(checkpoint),
    summary: { ...checkpoint.summary },
  });
}

function isDocumentId(value) {
  return typeof value === "string" && value.length > 0 && value !== "." &&
    value !== ".." &&
    !value.includes("/") &&
    new TextEncoder().encode(value).byteLength <= 1500 &&
    (!value.startsWith("__") || !value.endsWith("__") ||
      /^__id\d+__$/u.test(value));
}

function compareIds(left, right) {
  const leftPoints = Array.from(left, (character) => character.codePointAt(0));
  const rightPoints = Array.from(
    right,
    (character) => character.codePointAt(0),
  );
  for (
    let index = 0;
    index < Math.min(leftPoints.length, rightPoints.length);
    index += 1
  ) {
    if (leftPoints[index] !== rightPoints[index]) {
      return leftPoints[index] - rightPoints[index];
    }
  }
  return leftPoints.length - rightPoints.length;
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null);
}
