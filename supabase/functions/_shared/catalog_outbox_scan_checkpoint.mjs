import { FirestoreRestError } from "./firebase_firestore_rest.mjs";
import { isValidOutboxScanCursor } from "./firebase_firestore_outbox_adapter.mjs";

const COLLECTION = "catalog_outbox_scan_state";
const DOCUMENT_ID = "consumer-v1";
const WORKER_PATTERN = /^[A-Za-z0-9_-]{1,128}$/u;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{16,256}$/u;
const DEFAULT_LEASE_DURATION_MS = 180_000;
const STATE_FIELDS = new Set([
  "schemaVersion",
  "cursor",
  "cursorReadTime",
  "workerId",
  "leaseToken",
  "leaseExpiresAt",
  "updatedAt",
]);

/**
 * Trusted-server-only checkpoint for bounded outbox sweeps. The last document
 * ID survives snapshot expiry; the scanner rebases that ID to a new readTime.
 * A lease serializes scheduled invocations; event leases remain the per-event guard.
 */
export function createCatalogOutboxScanCheckpoint({
  store,
  workerId,
  now = Date.now,
  createLeaseToken,
  leaseDurationMs = DEFAULT_LEASE_DURATION_MS,
}) {
  if (
    !store || typeof store.runTransaction !== "function" ||
    typeof workerId !== "string" || !WORKER_PATTERN.test(workerId) ||
    typeof now !== "function" || typeof createLeaseToken !== "function" ||
    !Number.isSafeInteger(leaseDurationMs) || leaseDurationMs < 10_000 ||
    leaseDurationMs > 10 * 60_000
  ) {
    throw new FirestoreRestError("invalid-request");
  }

  async function acquire() {
    const time = safeNow(now);
    const leaseToken = createLeaseToken();
    const leaseExpiresAt = time + leaseDurationMs;
    if (
      !validEpoch(leaseExpiresAt) || typeof leaseToken !== "string" ||
      !TOKEN_PATTERN.test(leaseToken)
    ) {
      throw new FirestoreRestError("invalid-request");
    }
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, DOCUMENT_ID);
        if (!snapshot) {
          const state = {
            schemaVersion: 1,
            cursor: null,
            cursorReadTime: null,
            workerId,
            leaseToken,
            leaseExpiresAt: new Date(leaseExpiresAt),
            updatedAt: null,
          };
          transaction.create(COLLECTION, DOCUMENT_ID, state, {
            serverTimestampFields: ["updatedAt"],
          });
          return lease(state);
        }
        const current = validateState(snapshot.data);
        if (!current) throw new FirestoreRestError("backend_unavailable");
        if (
          current.leaseToken !== null &&
          timestampMillis(current.leaseExpiresAt) > time
        ) {
          return Object.freeze({ acquired: false, reason: "busy" });
        }
        const next = {
          // Preserve the last ID even after its readTime expires. The outbox
          // adapter opens a fresh snapshot after that ID on the next scan.
          cursor: current.cursor,
          cursorReadTime: current.cursorReadTime,
          workerId,
          leaseToken,
          leaseExpiresAt: new Date(leaseExpiresAt),
          updatedAt: null,
        };
        transaction.update(COLLECTION, DOCUMENT_ID, next, {
          updateTime: snapshot.updateTime,
          serverTimestampFields: ["updatedAt"],
        });
        return lease({
          ...current,
          ...next,
        });
      });
    } catch (error) {
      const safe = safeError(error);
      if (safe.code === "conflict") {
        return Object.freeze({ acquired: false, reason: "busy" });
      }
      throw safe;
    }
  }

  function advance(currentLease, { cursor, readTime } = {}) {
    if (!validLease(currentLease) || !validCheckpoint(cursor, readTime)) {
      return false;
    }
    return complete(currentLease, cursor, readTime);
  }

  function release(currentLease) {
    if (
      !validLease(currentLease) ||
      !validCheckpoint(currentLease.cursor, currentLease.cursorReadTime)
    ) return false;
    return complete(
      currentLease,
      currentLease.cursor,
      currentLease.cursorReadTime,
    );
  }

  async function complete(currentLease, cursor, cursorReadTime) {
    const time = safeNow(now);
    try {
      return await store.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(COLLECTION, DOCUMENT_ID);
        if (!snapshot) return false;
        const current = validateState(snapshot.data);
        if (
          !current || current.workerId !== currentLease.workerId ||
          current.workerId !== workerId ||
          current.leaseToken !== currentLease.leaseToken ||
          timestampMillis(current.leaseExpiresAt) <= time
        ) return false;
        transaction.update(COLLECTION, DOCUMENT_ID, {
          cursor,
          cursorReadTime,
          workerId: null,
          leaseToken: null,
          leaseExpiresAt: null,
          updatedAt: null,
        }, {
          updateTime: snapshot.updateTime,
          serverTimestampFields: ["updatedAt"],
        });
        return true;
      });
    } catch (error) {
      const safe = safeError(error);
      if (safe.code === "conflict") return false;
      throw safe;
    }
  }

  return Object.freeze({ acquire, advance, release });
}

function lease(state) {
  return Object.freeze({
    acquired: true,
    workerId: state.workerId,
    leaseToken: state.leaseToken,
    leaseExpiresAt: timestampMillis(state.leaseExpiresAt),
    cursor: state.cursor,
    cursorReadTime: state.cursorReadTime,
  });
}

function validateState(value) {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== STATE_FIELDS.size ||
    Object.keys(value).some((key) => !STATE_FIELDS.has(key)) ||
    value.schemaVersion !== 1 ||
    !validCheckpoint(value.cursor, value.cursorReadTime) ||
    timestampMillis(value.updatedAt) === null
  ) return null;
  const emptyLease = value.workerId === null && value.leaseToken === null &&
    value.leaseExpiresAt === null;
  const activeLease = typeof value.workerId === "string" &&
    WORKER_PATTERN.test(value.workerId) &&
    typeof value.leaseToken === "string" &&
    TOKEN_PATTERN.test(value.leaseToken) &&
    timestampMillis(value.leaseExpiresAt) !== null;
  return emptyLease || activeLease ? value : null;
}

function validCheckpoint(cursor, readTime) {
  if (cursor === null) return readTime === null;
  return typeof cursor === "string" && typeof readTime === "string" &&
    isValidOutboxScanCursor(cursor, readTime);
}

function validLease(value) {
  return Boolean(
    value && value.acquired === true && typeof value.workerId === "string" &&
      typeof value.leaseToken === "string" &&
      TOKEN_PATTERN.test(value.leaseToken) &&
      validEpoch(value.leaseExpiresAt) &&
      validCheckpoint(value.cursor, value.cursorReadTime),
  );
}

function timestampMillis(value) {
  if (value instanceof Date) {
    return Number.isFinite(value.getTime()) ? value.getTime() : null;
  }
  if (typeof value === "string" && Number.isFinite(Date.parse(value))) {
    return Date.parse(value);
  }
  return null;
}

function validEpoch(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function safeNow(clock) {
  const value = clock();
  if (!validEpoch(value)) throw new FirestoreRestError("invalid-request");
  return value;
}

function safeError(error) {
  if (error instanceof FirestoreRestError) return error;
  if (error?.code === "conflict") return new FirestoreRestError("conflict");
  return new FirestoreRestError("backend_unavailable");
}
