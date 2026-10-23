/**
 * Resumable, single-run coordinator. Its checkpoint lease prevents overlapping
 * scheduled sweeps; per-event Firestore leases still arbitrate individual work.
 */
export function createCatalogOutboxScanRunner(
  { checkpoint, processPage, pageSize = 2 },
) {
  if (
    !checkpoint || typeof checkpoint.acquire !== "function" ||
    typeof checkpoint.advance !== "function" ||
    typeof checkpoint.release !== "function" ||
    typeof processPage !== "function" || !Number.isSafeInteger(pageSize) ||
    pageSize < 1 || pageSize > 25
  ) {
    throw new TypeError("Invalid scan runner configuration.");
  }

  return Object.freeze({
    async run() {
      const lease = await checkpoint.acquire();
      if (!lease || lease.acquired !== true) {
        if (lease?.reason !== "busy") throw new Error("scan-lease-unavailable");
        return emptyBusyResult();
      }

      let completed = false;
      try {
        const page = await processPage({
          limit: pageSize,
          cursor: lease.cursor,
        });
        if (!validPage(page, lease.cursor)) {
          throw new Error("invalid-scan-page");
        }
        const nextCheckpoint = page.nextCursor === null
          ? { cursor: null, readTime: null }
          : { cursor: page.nextCursor, readTime: page.readTime };
        if (!await checkpoint.advance(lease, nextCheckpoint)) {
          throw new Error("checkpoint-lost");
        }
        completed = true;
        return Object.freeze({ busy: false, ...page });
      } catch {
        throw new Error("scan-failed");
      } finally {
        if (!completed) {
          try {
            await checkpoint.release(lease);
          } catch { /* Lease expiry safely permits takeover. */ }
        }
      }
    },
  });
}

function validPage(page, leaseCursor) {
  return Boolean(
    page && typeof page === "object" && Array.isArray(page.results) &&
      page.results.length <= 25 && Number.isSafeInteger(page.scannedPages) &&
      page.scannedPages >= 0 &&
      Number.isSafeInteger(page.scannedDocuments) &&
      page.scannedDocuments >= 0 &&
      Number.isSafeInteger(page.eligibleCount) &&
      page.eligibleCount >= page.results.length &&
      Number.isSafeInteger(page.claimedCount) && page.claimedCount >= 0 &&
      page.claimedCount <= page.results.length &&
      (page.nextCursor === null || typeof page.nextCursor === "string") &&
      (page.nextCursor === null
        ? page.readTime === null || validReadTime(page.readTime)
        : typeof page.readTime === "string" && page.nextCursor !== leaseCursor),
  );
}

function validReadTime(value) {
  return typeof value === "string" && Number.isFinite(Date.parse(value)) &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/u
      .test(value);
}

function emptyBusyResult() {
  return Object.freeze({
    busy: true,
    results: Object.freeze([]),
    scannedPages: 0,
    scannedDocuments: 0,
    eligibleCount: 0,
    claimedCount: 0,
    readTime: null,
    nextCursor: null,
  });
}
