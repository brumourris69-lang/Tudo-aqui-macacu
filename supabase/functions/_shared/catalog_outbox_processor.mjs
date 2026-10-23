import { createCatalogOutboxProtocol, DEFAULT_RETRY_POLICY } from './catalog_outbox_protocol.mjs';
import { createFirebaseFirestoreOutboxAdapter } from './firebase_firestore_outbox_adapter.mjs';
import { FirestoreRestError } from './firebase_firestore_rest.mjs';
import { createSupabaseCatalogWriterV2 } from './supabase_catalog_writer_v2.mjs';

const MAX_PAGE_SIZE = 100;
const MAX_SCAN_PAGE_SIZE = 100;
const MAX_SCAN_PAGES = 20;
const OUTCOME_STATES = new Set([
  'synced', 'superseded', 'dead_letter', 'pending', 'lease_lost', 'ack_pending',
  'state_unconfirmed', 'not_processed', 'unavailable',
]);

/**
 * Creates a trusted-server batch processor. Firestore credentials remain in
 * the injected store/token provider and the private Supabase credential stays
 * inside the injected RPC client; neither is accepted from event payloads.
 */
export function createCatalogOutboxProcessor({
  store,
  serverIdentity,
  rpc,
  now = Date.now,
  createLeaseToken,
  leaseDurationMs = 30_000,
  retryPolicy = DEFAULT_RETRY_POLICY,
  pageSize = 25,
  scanPageSize = 25,
  maxScanPages = 4,
}) {
  if (!store || typeof store.runTransaction !== 'function' ||
    typeof store.queryOutboxPage !== 'function' ||
    !serverIdentity || typeof serverIdentity.workerId !== 'string' ||
    typeof now !== 'function' || typeof createLeaseToken !== 'function' ||
    !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE ||
    !Number.isSafeInteger(scanPageSize) || scanPageSize < 1 || scanPageSize > MAX_SCAN_PAGE_SIZE ||
    !Number.isSafeInteger(maxScanPages) || maxScanPages < 1 || maxScanPages > MAX_SCAN_PAGES ||
    scanPageSize * maxScanPages > MAX_SCAN_PAGE_SIZE) {
    throw new FirestoreRestError('invalid-request');
  }

  const workerId = serverIdentity.workerId;
  const outbox = createFirebaseFirestoreOutboxAdapter({
    store, serverIdentity, now, leaseDurationMs,
  });
  const canonical = Object.freeze({
    get(id) {
      return store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get('establishments', id);
        return snapshot?.data ?? null;
      });
    },
  });
  const catalog = createSupabaseCatalogWriterV2({ rpc });
  const protocol = createCatalogOutboxProtocol({
    outbox, canonical, catalog, now, createLeaseToken, leaseDurationMs,
    ...(retryPolicy ? { retryPolicy } : {}),
  });

  async function processPage(request = {}) {
    if (!request || typeof request !== 'object' || Array.isArray(request) ||
      Object.keys(request).some((key) => !['cursor', 'limit'].includes(key))) {
      throw new FirestoreRestError('invalid-request');
    }
    const { cursor = null, limit = pageSize } = request;
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > pageSize ||
      !(cursor === null || typeof cursor === 'string')) {
      throw new FirestoreRestError('invalid-request');
    }
    const page = await outbox.listEligibleEvents({ limit, cursor, scanPageSize, maxPages: maxScanPages });
    const results = [];
    for (const event of page.events) {
      const outcome = await protocol.processOnce(event.id, workerId);
      results.push(sanitizeOutcome(event.id, outcome));
    }
    return Object.freeze({
      readTime: page.readTime,
      nextCursor: page.nextCursor,
      scannedPages: page.scannedPages,
      scannedDocuments: page.scannedDocuments,
      eligibleCount: page.eligibleCount,
      claimedCount: results.reduce((count, item) => count +
        (!['not_processed', 'unavailable'].includes(item.state) ? 1 : 0), 0),
      results: Object.freeze(results),
    });
  }

  return Object.freeze({ processPage });
}

function sanitizeOutcome(eventId, outcome) {
  const state = OUTCOME_STATES.has(outcome?.state) ? outcome.state : 'unavailable';
  const result = { eventId, state };
  if (typeof outcome?.reason === 'string' && /^[a-z_]{1,40}$/u.test(outcome.reason)) result.reason = outcome.reason;
  if (['applied', 'duplicate'].includes(outcome?.write)) result.write = outcome.write;
  if (typeof outcome?.errorCode === 'string' && /^[a-z_]{1,40}$/u.test(outcome.errorCode)) {
    result.errorCode = outcome.errorCode;
  }
  if (Number.isSafeInteger(outcome?.nextAttemptAt)) result.nextAttemptAt = outcome.nextAttemptAt;
  return Object.freeze(result);
}
