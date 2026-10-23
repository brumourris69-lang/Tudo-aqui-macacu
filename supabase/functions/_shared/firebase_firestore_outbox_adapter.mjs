import { isValidCatalogOutboxEvent } from './catalog_outbox_protocol.mjs';
import { FirestoreRestError } from './firebase_firestore_rest.mjs';

const COLLECTION = 'catalog_outbox';
const CURSOR_VERSION = 1;
const MAX_PAGE_SIZE = 100;
const MAX_SCAN_PAGES = 20;
const MAX_CURSOR_AGE_MS = 45 * 60 * 1_000;
const SNAPSHOT_SAFETY_LAG_MS = 5_000;
const MAX_LEASE_MS = 60 * 60 * 1_000;
const LEASE_TOKEN_PATTERN = /^[A-Za-z0-9_-]{16,256}$/u;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;
const TRANSITIONS = new Set(['pending', 'synced', 'superseded', 'dead_letter']);
const STATES = new Set([...TRANSITIONS, 'processing']);
const TERMINAL = new Set(['synced', 'superseded', 'dead_letter']);
const SAFE_ERRORS = new Set([
  'firestore_unavailable', 'catalog_unavailable', 'unknown_transient',
  'permanent_failure', 'event_inconsistent', 'catalog_conflict',
  'invalid_catalog_result', 'retry_exhausted',
]);
const INVALID_TIMESTAMP = Symbol('invalid-firestore-timestamp');
const TIMESTAMP_FIELDS = ['leaseExpiresAt', 'nextAttemptAt', 'syncedAt', 'createdAt', 'updatedAt'];

/**
 * Trusted-server-only adapter for catalog_outbox. The underlying Firestore
 * store must use a server identity with IAM access; serverIdentity.workerId
 * is a lease identity, not an authentication credential. Never bundle this
 * module into Flutter or expose it through a client-callable endpoint.
 *
 * @param {{store: {runTransaction: Function, queryOutboxPage: Function}, serverIdentity: {workerId: string}, now?: () => number, leaseDurationMs?: number}} options
 */
export function createFirebaseFirestoreOutboxAdapter({
  store,
  serverIdentity,
  now = Date.now,
  leaseDurationMs = 30_000,
}) {
  if (!store || typeof store.runTransaction !== 'function' ||
    typeof store.queryOutboxPage !== 'function' ||
    !serverIdentity || typeof serverIdentity.workerId !== 'string' ||
    !/^[A-Za-z0-9_-]{1,128}$/u.test(serverIdentity.workerId) ||
    typeof now !== 'function' || !Number.isSafeInteger(leaseDurationMs) ||
    leaseDurationMs < 1 || leaseDurationMs > MAX_LEASE_MS) {
    throw new FirestoreRestError('invalid-request');
  }
  const trustedWorkerId = serverIdentity.workerId;

  async function inspect(eventId) {
    validateId(eventId);
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, eventId);
        return snapshot ? normalizeEvent(snapshot.data) : null;
      });
    } catch (error) { throw safeError(error); }
  }

  async function claim(eventId, request) {
    validateId(eventId);
    const trustedNow = safeNow(now);
    const leaseCeiling = trustedNow + leaseDurationMs;
    const leaseExpiresAt = Number.isSafeInteger(request?.leaseExpiresAt)
      ? Math.min(request.leaseExpiresAt, leaseCeiling) : null;
    if (!request || request.workerId !== trustedWorkerId ||
      !LEASE_TOKEN_PATTERN.test(request.leaseToken ?? '') ||
      !STATES.has(request.expectedState) ||
      !validVersion(request.expectedVersion) || !validEpoch(request.now) ||
      !validEpoch(request.leaseExpiresAt) || request.leaseExpiresAt <= request.now ||
      !validEpoch(leaseCeiling) || leaseExpiresAt === null || leaseExpiresAt <= trustedNow) {
      return { claimed: false, reason: 'invalid_request' };
    }

    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, eventId);
        if (!snapshot) return { claimed: false, reason: 'missing' };
        const event = normalizeEvent(snapshot.data);
        if (!isValidCatalogOutboxEvent(event) || event.operationId !== eventId ||
          !Number.isSafeInteger(event.attemptCount + 1)) {
          return { claimed: false, reason: 'invalid_event' };
        }
        if (TERMINAL.has(event.state)) return { claimed: false, reason: 'terminal' };
        if (event.state !== request.expectedState || event.version !== request.expectedVersion) {
          return { claimed: false, reason: 'changed' };
        }
        const eligibility = claimEligibility(event, trustedNow);
        if (eligibility !== null) return { claimed: false, reason: eligibility };

        transaction.update(COLLECTION, eventId, {
          state: 'processing',
          attemptCount: event.attemptCount + 1,
          workerId: trustedWorkerId,
          leaseToken: request.leaseToken,
          leaseExpiresAt: new Date(leaseExpiresAt),
          nextAttemptAt: null,
          lastErrorCode: null,
          syncedAt: null,
        }, { updateTime: snapshot.updateTime, serverTimestampFields: ['updatedAt'] });
        return { claimed: true };
      });
    } catch (error) {
      const safe = safeError(error);
      if (safe.code === 'conflict') return { claimed: false, reason: 'changed' };
      throw safe;
    }
  }

  async function readClaimed(lease) {
    validateLease(lease);
    if (lease.workerId !== trustedWorkerId) return null;
    const time = safeNow(now);
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, lease.eventId);
        if (!snapshot) return null;
        const event = normalizeEvent(snapshot.data);
        if (!isValidCatalogOutboxEvent(event) || event.operationId !== lease.eventId ||
          event.state !== 'processing' || event.version !== lease.expectedVersion ||
          event.workerId !== lease.workerId || event.leaseToken !== lease.leaseToken ||
          timestampMillis(event.leaseExpiresAt) <= time) return null;
        return event;
      });
    } catch (error) { throw safeError(error); }
  }

  async function renewLease(request) {
    const trustedNow = safeNow(now);
    const leaseCeiling = trustedNow + leaseDurationMs;
    const leaseExpiresAt = Number.isSafeInteger(request?.leaseExpiresAt)
      ? Math.min(request.leaseExpiresAt, leaseCeiling) : null;
    const trustedRequest = { ...request, serverWorkerId: trustedWorkerId };
    trustedRequest.now = trustedNow;
    trustedRequest.leaseExpiresAt = leaseExpiresAt;
    if (!validEpoch(leaseCeiling) || !validTransitionLease(trustedRequest) ||
      !validEpoch(leaseExpiresAt) || leaseExpiresAt <= trustedNow) return false;
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, trustedRequest.eventId);
        if (!snapshot) return false;
        const event = normalizeEvent(snapshot.data);
        if (!matchesLease(event, trustedRequest) || timestampMillis(event.leaseExpiresAt) <= trustedNow ||
          leaseExpiresAt <= timestampMillis(event.leaseExpiresAt)) return false;
        transaction.update(COLLECTION, trustedRequest.eventId, {
          leaseExpiresAt: new Date(trustedRequest.leaseExpiresAt),
        }, { updateTime: snapshot.updateTime, serverTimestampFields: ['updatedAt'] });
        return true;
      });
    } catch (error) {
      const safe = safeError(error);
      if (safe.code === 'conflict') return false;
      throw safe;
    }
  }

  async function transition(request) {
    const trustedNow = safeNow(now);
    const trustedRequest = { ...request, serverWorkerId: trustedWorkerId };
    trustedRequest.now = trustedNow;
    if (!validTransitionLease(trustedRequest) || !trustedRequest.patch ||
      !TRANSITIONS.has(trustedRequest.patch.state)) return false;
    const values = transitionFields(trustedRequest.patch);
    if (!values || (values.state === 'pending' && timestampMillis(values.nextAttemptAt) <= trustedNow)) return false;
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, trustedRequest.eventId);
        if (!snapshot) return false;
        const event = normalizeEvent(snapshot.data);
        if (!matchesLease(event, trustedRequest) || timestampMillis(event.leaseExpiresAt) <= trustedRequest.now) return false;
        transaction.update(COLLECTION, trustedRequest.eventId, {
          ...values,
          workerId: null,
          leaseToken: null,
          leaseExpiresAt: null,
        }, { updateTime: snapshot.updateTime, serverTimestampFields: ['updatedAt'] });
        return true;
      });
    } catch (error) {
      const safe = safeError(error);
      if (safe.code === 'conflict') return false;
      throw safe;
    }
  }

  async function listEligibleEvents({ limit = 25, cursor = null, scanPageSize = limit, maxPages = 1 } = {}) {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE ||
      !Number.isSafeInteger(scanPageSize) || scanPageSize < 1 || scanPageSize > MAX_PAGE_SIZE ||
      !Number.isSafeInteger(maxPages) || maxPages < 1 || maxPages > MAX_SCAN_PAGES) {
      throw new FirestoreRestError('invalid-request');
    }
    const decoded = cursor === null ? null : decodeCursor(cursor);
    const time = safeNow(now);
    if (decoded && time < Date.parse(decoded.readTime) - 60_000) {
      throw new FirestoreRestError('invalid-request');
    }
    const expiredSnapshot = decoded && time - Date.parse(decoded.readTime) > MAX_CURSOR_AGE_MS;
    const snapshotReadTime = decoded && !expiredSnapshot
      ? decoded.readTime : new Date(time - SNAPSHOT_SAFETY_LAG_MS).toISOString();
    let previousId = decoded?.lastDocumentId ?? '';
    let lastDocumentId = decoded?.lastDocumentId ?? null;
    let scannedPages = 0;
    let scannedDocuments = 0;
    const events = [];
    while (scannedPages < maxPages) {
      let page;
      try {
        page = await store.queryOutboxPage({
          limit: scanPageSize,
          readTime: snapshotReadTime,
          ...(lastDocumentId === null ? {} : { startAfterDocumentId: lastDocumentId }),
        });
      } catch (error) { throw safeError(error); }
      scannedPages += 1;
      if (!page || !Array.isArray(page.documents) || typeof page.hasMore !== 'boolean' ||
        (page.readTime !== null && !validTimestampString(page.readTime)) ||
        page.documents.length > scanPageSize || (page.hasMore && page.documents.length === 0)) {
        throw new FirestoreRestError('backend_unavailable');
      }
      const readTime = page.readTime ?? snapshotReadTime;
      if (Date.parse(readTime) !== Date.parse(snapshotReadTime)) throw new FirestoreRestError('backend_unavailable');
      for (const [index, item] of page.documents.entries()) {
        if (!item || !ID_PATTERN.test(item.id ?? '') || !item.data || typeof item.data !== 'object') {
          throw new FirestoreRestError('backend_unavailable');
        }
        if (item.id <= previousId) throw new FirestoreRestError('backend_unavailable');
        previousId = item.id;
        lastDocumentId = item.id;
        scannedDocuments += 1;
        const event = normalizeEvent(item.data);
        if (isEligible(event, time)) events.push(Object.freeze({ ...event, id: item.id }));
        if (events.length === limit) {
          const hasMore = page.hasMore || index < page.documents.length - 1;
          return Object.freeze({
            events: Object.freeze(events),
            nextCursor: hasMore ? encodeCursor({ v: CURSOR_VERSION, readTime, lastDocumentId }) : null,
            readTime, scannedPages, scannedDocuments, eligibleCount: events.length,
          });
        }
      }
      if (!page.hasMore) {
        return Object.freeze({
          events: Object.freeze(events), nextCursor: null, readTime,
          scannedPages, scannedDocuments, eligibleCount: events.length,
        });
      }
      if (!readTime || page.nextDocumentId !== page.documents.at(-1)?.id ||
        !ID_PATTERN.test(page.nextDocumentId ?? '')) throw new FirestoreRestError('backend_unavailable');
      lastDocumentId = page.nextDocumentId;
    }
    const readTime = decoded?.readTime ?? snapshotReadTime;
    return Object.freeze({
      events: Object.freeze(events),
      nextCursor: lastDocumentId === null ? null : encodeCursor({ v: CURSOR_VERSION, readTime, lastDocumentId }),
      readTime, scannedPages, scannedDocuments, eligibleCount: events.length,
    });
  }

  return Object.freeze({ inspect, claim, readClaimed, renewLease, transition, listEligibleEvents });
}

/** Validates the opaque scan cursor and its snapshot before persisting a checkpoint. */
export function isValidOutboxScanCursor(cursor, readTime) {
  try { return decodeCursor(cursor).readTime === readTime; } catch { return false; }
}

function claimEligibility(event, now) {
  if (event.state === 'pending') {
    if (!Object.hasOwn(event, 'nextAttemptAt') || event.nextAttemptAt === null) return null;
    const retryAt = timestampMillis(event.nextAttemptAt);
    if (retryAt === null) return 'invalid_event';
    return retryAt > now ? 'retry_scheduled' : null;
  }
  if (event.state === 'processing') {
    if (!Object.hasOwn(event, 'leaseExpiresAt') || event.leaseExpiresAt === null) return null;
    const expiresAt = timestampMillis(event.leaseExpiresAt);
    if (expiresAt === null) return 'invalid_event';
    return expiresAt > now ? 'busy' : null;
  }
  return 'terminal';
}

function isEligible(event, now) {
  if (!event || !['pending', 'processing'].includes(event.state)) return false;
  if (event.state === 'pending') {
    if (!Object.hasOwn(event, 'nextAttemptAt') || event.nextAttemptAt === null) return true;
    const retryAt = timestampMillis(event.nextAttemptAt);
    return retryAt !== null && retryAt <= now;
  }
  if (!Object.hasOwn(event, 'leaseExpiresAt') || event.leaseExpiresAt === null) return true;
  const expiresAt = timestampMillis(event.leaseExpiresAt);
  return expiresAt !== null && expiresAt <= now;
}

function transitionFields(patch) {
  const { state } = patch;
  if (state === 'pending') {
    const retryAt = timestampMillis(patch.nextAttemptAt);
    if (retryAt === null || typeof patch.lastErrorCode !== 'string' || !SAFE_ERRORS.has(patch.lastErrorCode)) return null;
    return { state, nextAttemptAt: new Date(retryAt), lastErrorCode: patch.lastErrorCode, syncedAt: null };
  }
  if (state === 'synced') {
    const syncedAt = timestampMillis(patch.syncedAt);
    if (syncedAt === null) return null;
    return { state, nextAttemptAt: null, lastErrorCode: null, syncedAt: new Date(syncedAt) };
  }
  if (state === 'superseded') return { state, nextAttemptAt: null, lastErrorCode: null, syncedAt: null };
  if (state === 'dead_letter') {
    if (typeof patch.lastErrorCode !== 'string' || !SAFE_ERRORS.has(patch.lastErrorCode)) return null;
    return { state, nextAttemptAt: null, lastErrorCode: patch.lastErrorCode, syncedAt: null };
  }
  return null;
}

function matchesLease(event, request) {
  return event && event.state === 'processing' && event.version === request.expectedVersion &&
    event.workerId === request.workerId && request.workerId === request.serverWorkerId &&
    event.leaseToken === request.leaseToken && isValidCatalogOutboxEvent(event) &&
    event.operationId === request.eventId;
}

function validTransitionLease(request) {
  return Boolean(request && ID_PATTERN.test(request.eventId ?? '') &&
    request.expectedState === 'processing' && validVersion(request.expectedVersion) &&
    request.workerId && request.workerId === request.serverWorkerId &&
    LEASE_TOKEN_PATTERN.test(request.leaseToken ?? '') && validEpoch(request.now));
}

function validateLease(lease) {
  if (!lease || !ID_PATTERN.test(lease.eventId ?? '') ||
    lease.workerId === undefined || !LEASE_TOKEN_PATTERN.test(lease.leaseToken ?? '') ||
    !validVersion(lease.expectedVersion)) throw new FirestoreRestError('invalid-request');
}

function normalizeEvent(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return value;
  const event = { ...value };
  for (const key of TIMESTAMP_FIELDS) {
    if (Object.hasOwn(event, key) && event[key] !== null) {
      event[key] = normalizeTimestamp(event[key]) ?? INVALID_TIMESTAMP;
    }
  }
  return event;
}

function normalizeTimestamp(value) {
  if (value instanceof Date) return Number.isFinite(value.getTime()) ? new Date(value.getTime()) : null;
  if (typeof value === 'string' && validTimestampString(value)) return new Date(value);
  if (value && typeof value === 'object' && Number.isSafeInteger(value.seconds) &&
    Number.isInteger(value.nanoseconds) && value.nanoseconds >= 0 && value.nanoseconds < 1_000_000_000) {
    return new Date(value.seconds * 1_000 + Math.floor(value.nanoseconds / 1_000_000));
  }
  return null;
}

function timestampMillis(value) {
  if (validEpoch(value)) return value;
  const date = normalizeTimestamp(value);
  return date && Number.isSafeInteger(date.getTime()) && date.getTime() >= 0 ? date.getTime() : null;
}

function validTimestampString(value) {
  return typeof value === 'string' &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/u.test(value) &&
    Number.isFinite(Date.parse(value));
}

function encodeCursor(value) {
  return btoa(JSON.stringify(value)).replace(/\+/gu, '-').replace(/\//gu, '_').replace(/=+$/u, '');
}

function decodeCursor(value) {
  if (typeof value !== 'string' || value.length > 2048 || !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw new FirestoreRestError('invalid-request');
  }
  try {
    const base64 = value.replace(/-/gu, '+').replace(/_/gu, '/');
    const parsed = JSON.parse(atob(base64.padEnd(Math.ceil(base64.length / 4) * 4, '=')));
    if (!parsed || Object.keys(parsed).length !== 3 || parsed.v !== CURSOR_VERSION ||
      !validTimestampString(parsed.readTime) || !ID_PATTERN.test(parsed.lastDocumentId ?? '')) {
      throw new Error();
    }
    return parsed;
  } catch { throw new FirestoreRestError('invalid-request'); }
}

function safeNow(clock) {
  const time = clock();
  if (!validEpoch(time)) throw new FirestoreRestError('invalid-request');
  return time;
}

function validEpoch(value) { return Number.isSafeInteger(value) && value >= 0; }
function validVersion(value) { return Number.isSafeInteger(value) && value > 0; }
function validateId(value) {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) throw new FirestoreRestError('invalid-request');
}
function safeError(error) {
  if (error instanceof FirestoreRestError) return error;
  if (error?.code === 'conflict') return new FirestoreRestError('conflict');
  if (error?.code === 'invalid-request') return new FirestoreRestError('invalid-request');
  return new FirestoreRestError('backend_unavailable');
}
