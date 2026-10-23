const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const FIRESTORE_TIMESTAMP_PATTERN =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/u;
const MAX_PAGE_SIZE = 200;
const MAX_SNAPSHOT_AGE_MS = 50 * 60 * 1000;
const TOKEN_PREFIX = "reconciliation-v1.";
const CANONICAL_FIELDS = new Set([
  "name",
  "title",
  "shortDescription",
  "description",
  "category",
  "subcategory",
  "location",
  "artwork",
  "imageUrl",
  "logoUrl",
  "galleryUrls",
  "featured",
  "open",
  "mapsUrl",
  "maps",
  "hours",
  "services",
  "products",
  "additionalInfo",
  "promotionTitle",
  "promotionDescription",
  "publicContactApproved",
  "phone",
  "whatsapp",
  "instagram",
  "published",
  "active",
  "expiresAt",
  "deletedAt",
  "catalogVersion",
  "outboxOperationId",
]);

export class CatalogReconciliationSnapshotReaderError extends Error {
  constructor(code = "snapshot_read_failed") {
    const safeCode =
      ["invalid_snapshot", "snapshot-expired", "snapshot_read_failed"].includes(
          code,
        )
        ? code
        : "snapshot_read_failed";
    super(safeCode);
    this.name = "CatalogReconciliationSnapshotReaderError";
    this.code = safeCode;
  }
}

/**
 * Pairs a fixed Firestore readTime with a private, materialized PostgreSQL
 * snapshot. It only reads both sources and never applies reconciliation plans.
 * The composite cursor is intentionally small enough for the scan checkpoint.
 */
export function createCatalogReconciliationSnapshotReader({
  firestore,
  catalog,
  now = Date.now,
  createSnapshotId = () => crypto.randomUUID(),
}) {
  if (
    typeof firestore?.queryEstablishmentsSnapshotPage !== "function" ||
    typeof catalog?.beginSnapshot !== "function" ||
    typeof catalog?.readPage !== "function" ||
    typeof catalog?.disposeSnapshot !== "function" ||
    typeof now !== "function" ||
    typeof createSnapshotId !== "function"
  ) {
    throw new CatalogReconciliationSnapshotReaderError("invalid_snapshot");
  }

  async function beginSnapshot() {
    let catalogSnapshotId;
    let catalogStarted = false;
    try {
      catalogSnapshotId = createSnapshotId();
      if (
        typeof catalogSnapshotId !== "string" ||
        !UUID_PATTERN.test(catalogSnapshotId)
      ) {
        throw new CatalogReconciliationSnapshotReaderError("invalid_snapshot");
      }
      const catalogHeader = await catalog.beginSnapshot(catalogSnapshotId);
      catalogStarted = true;
      if (!validCatalogHeader(catalogHeader, catalogSnapshotId)) {
        throw new CatalogReconciliationSnapshotReaderError();
      }
      const probe = await firestore.queryEstablishmentsSnapshotPage({
        limit: 1,
      });
      if (
        !validFirestorePage(probe, null, 1) || !validTimestamp(probe.readTime)
      ) {
        throw new CatalogReconciliationSnapshotReaderError();
      }
      const firestoreExpiry = Date.parse(probe.readTime) + MAX_SNAPSHOT_AGE_MS;
      const expiresAt = Math.min(
        Date.parse(catalogHeader.expires_at),
        firestoreExpiry,
      );
      if (!Number.isFinite(expiresAt) || expiresAt <= safeNow(now)) {
        throw new CatalogReconciliationSnapshotReaderError("snapshot-expired");
      }
      return encodeSnapshot({
        schemaVersion: 1,
        catalogSnapshotId,
        firestoreReadTime: probe.readTime,
        expiresAt: new Date(expiresAt).toISOString(),
      });
    } catch (error) {
      if (catalogStarted) {
        try {
          await catalog.disposeSnapshot(catalogSnapshotId);
        } catch { /* best-effort cleanup */ }
      }
      throw normalizeError(error);
    }
  }

  async function readPage({ snapshotId, afterId = null, limit = 100 } = {}) {
    const snapshot = decodeSnapshot(snapshotId);
    if (
      !snapshot || (afterId !== null && !validDocumentId(afterId)) ||
      !Number.isSafeInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE
    ) {
      throw new CatalogReconciliationSnapshotReaderError("invalid_snapshot");
    }
    if (Date.parse(snapshot.expiresAt) <= safeNow(now)) {
      throw new CatalogReconciliationSnapshotReaderError("snapshot-expired");
    }

    let sourcePage;
    let destinationPage;
    try {
      [sourcePage, destinationPage] = await Promise.all([
        firestore.queryEstablishmentsSnapshotPage({
          limit,
          readTime: snapshot.firestoreReadTime,
          startAfterDocumentId: afterId,
        }),
        catalog.readPage({
          snapshotId: snapshot.catalogSnapshotId,
          afterId,
          limit,
        }),
      ]);
    } catch (error) {
      throw normalizeError(error);
    }
    if (
      !validFirestorePage(sourcePage, afterId, limit) ||
      sourcePage.readTime !== snapshot.firestoreReadTime ||
      !validDestinationPage(
        destinationPage,
        snapshot.catalogSnapshotId,
        afterId,
        limit,
      )
    ) {
      throw new CatalogReconciliationSnapshotReaderError();
    }

    const canonicalById = new Map(sourcePage.documents.map((document) => [
      document.id,
      { id: document.id, data: sanitizeCanonicalData(document.data) },
    ]));
    const catalogById = new Map(
      destinationPage.catalog_rows.map((row) => [row.id, row]),
    );
    const tombstonesById = new Map(
      destinationPage.tombstones.map((row) => [row.id, row]),
    );
    const allIds = [
      ...new Set([
        ...canonicalById.keys(),
        ...catalogById.keys(),
        ...tombstonesById.keys(),
      ]),
    ].sort(compareDocumentIds);
    const pageIds = allIds.slice(0, limit);
    const selected = new Set(pageIds);
    if (
      pageIds.length === 0 && (!sourcePage.hasMore || !destinationPage.done)
    ) {
      throw new CatalogReconciliationSnapshotReaderError();
    }
    const nextCursor = pageIds.at(-1) ?? afterId;
    return Object.freeze({
      snapshotId,
      canonicalDocuments: Object.freeze(
        pageIds.flatMap((id) =>
          canonicalById.has(id) ? [canonicalById.get(id)] : []
        ),
      ),
      catalogRows: Object.freeze(
        pageIds.flatMap((id) =>
          catalogById.has(id) ? [catalogById.get(id)] : []
        ),
      ),
      tombstones: Object.freeze(
        pageIds.flatMap((id) =>
          tombstonesById.has(id) ? [tombstonesById.get(id)] : []
        ),
      ),
      nextCursor,
      done: pageIds.length === allIds.length && !sourcePage.hasMore &&
        destinationPage.done,
    });
  }

  async function disposeSnapshot(snapshotId) {
    const snapshot = decodeSnapshot(snapshotId);
    if (!snapshot) {
      throw new CatalogReconciliationSnapshotReaderError("invalid_snapshot");
    }
    try {
      return await catalog.disposeSnapshot(snapshot.catalogSnapshotId);
    } catch (error) {
      throw normalizeError(error);
    }
  }

  return Object.freeze({ beginSnapshot, readPage, disposeSnapshot });
}

function validFirestorePage(page, cursor, limit) {
  return plainObject(page) && Array.isArray(page.documents) &&
    page.documents.length <= limit &&
    typeof page.hasMore === "boolean" && validTimestamp(page.readTime) &&
    page.documents.every((document, index) =>
      plainObject(document) && validDocumentId(document.id) &&
      plainObject(document.data) && validTimestamp(document.updateTime) &&
      (index === 0
        ? cursor === null || compareDocumentIds(document.id, cursor) > 0
        : compareDocumentIds(page.documents[index - 1].id, document.id) < 0)
    );
}

function validCatalogHeader(value, snapshotId) {
  return plainObject(value) && Object.keys(value).length === 6 &&
    Object.hasOwn(value, "snapshot_id") &&
    Object.hasOwn(value, "captured_at") &&
    Object.hasOwn(value, "expires_at") &&
    Object.hasOwn(value, "entity_count") &&
    Object.hasOwn(value, "payload_bytes") && Object.hasOwn(value, "replayed") &&
    value.snapshot_id === snapshotId && validTimestamp(value.captured_at) &&
    validTimestamp(value.expires_at) &&
    Date.parse(value.expires_at) > Date.parse(value.captured_at) &&
    Number.isSafeInteger(value.entity_count) && value.entity_count >= 0 &&
    value.entity_count <= 10_000 &&
    Number.isSafeInteger(value.payload_bytes) && value.payload_bytes >= 0 &&
    value.payload_bytes <= 67_108_864 &&
    typeof value.replayed === "boolean";
}

function validDestinationPage(page, snapshotId, cursor, limit) {
  if (
    !plainObject(page) || page.snapshot_id !== snapshotId ||
    !validTimestamp(page.captured_at) ||
    !validTimestamp(page.expires_at) ||
    Date.parse(page.expires_at) <= Date.parse(page.captured_at) ||
    typeof page.done !== "boolean" || !Array.isArray(page.catalog_rows) ||
    !Array.isArray(page.tombstones) || page.catalog_rows.length > limit ||
    page.tombstones.length > limit
  ) return false;
  const ids = [
    ...page.catalog_rows.map((row) => row?.id),
    ...page.tombstones.map((row) => row?.id),
  ];
  if (ids.some((id) => !validDocumentId(id))) return false;
  const unique = [...new Set(ids)].sort(compareDocumentIds);
  if (
    unique.length > limit ||
    (cursor !== null &&
      unique.some((id) => compareDocumentIds(id, cursor) <= 0)) ||
    !isSorted(page.catalog_rows.map((row) => row.id)) ||
    !isSorted(page.tombstones.map((row) => row.id))
  ) return false;
  if (!page.done && unique.length !== limit) return false;
  return true;
}

function sanitizeCanonicalData(data) {
  const selected = Object.fromEntries(
    Object.entries(data).filter(([key]) => CANONICAL_FIELDS.has(key)),
  );
  if (selected.publicContactApproved !== true) {
    delete selected.phone;
    delete selected.whatsapp;
    delete selected.instagram;
  }
  return selected;
}

function encodeSnapshot(value) {
  const encoded = btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/u, "");
  const token = `${TOKEN_PREFIX}${encoded}`;
  if (token.length > 256) {
    throw new CatalogReconciliationSnapshotReaderError("invalid_snapshot");
  }
  return token;
}

function decodeSnapshot(value) {
  if (
    typeof value !== "string" || value.length > 256 ||
    !value.startsWith(TOKEN_PREFIX)
  ) return null;
  const encoded = value.slice(TOKEN_PREFIX.length);
  if (!/^[A-Za-z0-9_-]+$/u.test(encoded)) return null;
  try {
    const json = atob(
      encoded.replaceAll("-", "+").replaceAll("_", "/") +
        "=".repeat((4 - encoded.length % 4) % 4),
    );
    const result = JSON.parse(json);
    if (
      !plainObject(result) || Object.keys(result).length !== 4 ||
      result.schemaVersion !== 1 ||
      !UUID_PATTERN.test(result.catalogSnapshotId) ||
      !validTimestamp(result.firestoreReadTime) ||
      !validTimestamp(result.expiresAt)
    ) return null;
    return result;
  } catch {
    return null;
  }
}

function normalizeError(error) {
  if (error instanceof CatalogReconciliationSnapshotReaderError) return error;
  if (
    error?.code === "snapshot_expired" || error?.code === "snapshot-expired" ||
    error?.code === "55000"
  ) {
    return new CatalogReconciliationSnapshotReaderError("snapshot-expired");
  }
  return new CatalogReconciliationSnapshotReaderError("snapshot_read_failed");
}

function safeNow(now) {
  const value = now();
  if (!Number.isFinite(value)) {
    throw new CatalogReconciliationSnapshotReaderError("snapshot_read_failed");
  }
  return value;
}

function validTimestamp(value) {
  return typeof value === "string" && FIRESTORE_TIMESTAMP_PATTERN.test(value) &&
    Number.isFinite(Date.parse(value));
}

function validDocumentId(value) {
  return typeof value === "string" &&
    new TextEncoder().encode(value).byteLength > 0 &&
    new TextEncoder().encode(value).byteLength <= 1500 && value !== "." &&
    value !== ".." && !value.includes("/") &&
    (!value.startsWith("__") || !value.endsWith("__") ||
      /^__id\d+__$/u.test(value));
}

function compareDocumentIds(left, right) {
  const a = Array.from(left, (character) => character.codePointAt(0));
  const b = Array.from(right, (character) => character.codePointAt(0));
  for (let index = 0; index < Math.min(a.length, b.length); index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return a.length - b.length;
}

function isSorted(ids) {
  return ids.every((id, index) =>
    index === 0 || compareDocumentIds(ids[index - 1], id) < 0
  );
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype ||
      Object.getPrototypeOf(value) === null);
}
