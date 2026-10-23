import test from 'node:test';
import assert from 'node:assert/strict';
import { createFirebaseFirestoreOutboxAdapter } from './firebase_firestore_outbox_adapter.mjs';

const operationId = '00000000-0000-4000-8000-000000000001';
const workerA = Object.freeze({ workerId: 'worker-a' });
const workerB = Object.freeze({ workerId: 'worker-b' });
const now = Date.parse('2026-10-20T12:00:00.000Z');

function v1(overrides = {}) {
  return {
    schemaVersion: 1, operationId, entityType: 'establishment', entityId: 'modelo-legacy-01',
    authorUid: 'admin-user', version: 4, operation: 'reconcile', state: 'pending', attemptCount: 0,
    ...overrides,
  };
}

function v2(overrides = {}) {
  return {
    ...v1({ schemaVersion: 2 }), createdAt: new Date(now), updatedAt: new Date(now),
    workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null,
    lastErrorCode: null, syncedAt: null, ...overrides,
  };
}

function memoryStore(initial = []) {
  const docs = new Map(initial.map(({ id, data }) => [id, { data: structuredClone(data), updateTime: 1 }]));
  let tail = Promise.resolve();
  let clock = 1;
  const queries = [];
  const store = {
    docs,
    queries,
    async runTransaction(callback) {
      let release;
      const previous = tail;
      tail = new Promise((resolve) => { release = resolve; });
      await previous;
      const writes = [];
      const tx = {
        async get(collection, id) {
          assert.equal(collection, 'catalog_outbox');
          const doc = docs.get(id);
          return doc ? { data: structuredClone(doc.data), updateTime: String(doc.updateTime) } : null;
        },
        update(collection, id, data, options = {}) {
          assert.equal(collection, 'catalog_outbox');
          writes.push({ id, data: structuredClone(data), updateTime: options.updateTime });
        },
      };
      try {
        const result = await callback(tx);
        for (const write of writes) {
          const current = docs.get(write.id);
          if (!current || String(current.updateTime) !== write.updateTime) {
            const error = new Error('synthetic conflict'); error.code = 'conflict'; throw error;
          }
          docs.set(write.id, { data: { ...current.data, ...write.data, updatedAt: new Date(now) }, updateTime: ++clock });
        }
        return result;
      } finally { release(); }
    },
    async queryOutboxPage(options) {
      queries.push(structuredClone(options));
      return options.pageIndex === 0
        ? { documents: [], readTime: new Date(now).toISOString(), nextDocumentName: null, exhausted: true }
        : { documents: [], readTime: options.readTime, nextDocumentName: null, exhausted: true };
    },
  };
  return store;
}

function adapter(store, identity = workerA, clock = () => now) {
  return createFirebaseFirestoreOutboxAdapter({ store, serverIdentity: identity, now: clock, leaseDurationMs: 10_000 });
}

test('claims a V1 event without assuming legacy lifecycle fields exist', async () => {
  const store = memoryStore([{ id: operationId, data: v1() }]);
  const outbox = adapter(store);
  const result = await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending',
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  });
  assert.deepEqual(result, { claimed: true });
  const event = store.docs.get(operationId).data;
  assert.equal(event.schemaVersion, 1);
  assert.equal(event.attemptCount, 1);
  assert.equal(event.workerId, workerA.workerId);
  assert.equal(event.leaseToken, 'lease-token-00000001');
  assert.equal(event.leaseExpiresAt.getTime(), now + 10_000);
});

test('reclaims a legacy V1 processing event that has no persisted lease fields', async () => {
  const store = memoryStore([{ id: operationId, data: v1({ state: 'processing', attemptCount: 1 }) }]);
  const outbox = adapter(store);
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'processing',
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  }), { claimed: true });
  assert.equal(store.docs.get(operationId).data.schemaVersion, 1);
  assert.equal(store.docs.get(operationId).data.attemptCount, 2);
});

test('normalizes REST timestamps to Dates while leaving absent V1 lifecycle fields absent', async () => {
  const legacy = v1();
  const current = v2({ createdAt: new Date(now).toISOString(), updatedAt: new Date(now).toISOString() });
  const store = memoryStore([{ id: operationId, data: legacy }]);
  const outbox = adapter(store);
  const readLegacy = await outbox.inspect(operationId);
  assert.equal(Object.hasOwn(readLegacy, 'leaseExpiresAt'), false);
  assert.equal(Object.hasOwn(readLegacy, 'nextAttemptAt'), false);
  store.docs.set(operationId, { data: current, updateTime: 2 });
  const readV2 = await outbox.inspect(operationId);
  assert.ok(readV2.createdAt instanceof Date);
  assert.ok(readV2.updatedAt instanceof Date);
  assert.equal(readV2.operationId, operationId);
  assert.equal(readV2.version, 4);
});

test('V2 claim rejects incomplete schema and stale expected version', async () => {
  const incomplete = v2(); delete incomplete.syncedAt;
  const store = memoryStore([{ id: operationId, data: incomplete }]);
  const outbox = adapter(store);
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending',
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  }), { claimed: false, reason: 'invalid_event' });
  store.docs.set(operationId, { data: v2(), updateTime: 1 });
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending',
    expectedVersion: 3, now, leaseExpiresAt: now + 10_000,
  }), { claimed: false, reason: 'changed' });
});

test('only one concurrent worker can claim a pending event', async () => {
  const store = memoryStore([{ id: operationId, data: v2() }]);
  const outbox = adapter(store);
  const [a, b] = await Promise.all([
    outbox.claim(operationId, { workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending', expectedVersion: 4, now, leaseExpiresAt: now + 10_000 }),
    outbox.claim(operationId, { workerId: workerB.workerId, leaseToken: 'lease-token-00000002', expectedState: 'pending', expectedVersion: 4, now, leaseExpiresAt: now + 10_000 }),
  ]);
  assert.equal([a, b].filter((item) => item.claimed).length, 1);
  assert.equal(store.docs.get(operationId).data.attemptCount, 1);
});

test('rejects early retry and active lease, then reclaims an expired V2 lease', async () => {
  const store = memoryStore([{ id: operationId, data: v2({
    state: 'pending', attemptCount: 1, nextAttemptAt: new Date(now + 5_000), lastErrorCode: 'firestore_unavailable',
  }) }]);
  const outbox = adapter(store);
  const claim = (expectedState) => outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState,
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  });
  assert.deepEqual(await claim('pending'), { claimed: false, reason: 'retry_scheduled' });
  store.docs.set(operationId, { data: v2({
    state: 'processing', attemptCount: 1, workerId: 'worker-old', leaseToken: 'lease-token-old-000000',
    leaseExpiresAt: new Date(now + 5_000),
  }), updateTime: 1 });
  assert.deepEqual(await claim('processing'), { claimed: false, reason: 'busy' });
  store.docs.get(operationId).data.leaseExpiresAt = new Date(now - 1);
  assert.deepEqual(await claim('processing'), { claimed: true });
});

test('does not trust a caller-supplied clock to bypass retry or an expired lease', async () => {
  const store = memoryStore([{ id: operationId, data: v2({
    state: 'pending', attemptCount: 1, nextAttemptAt: new Date(now + 5_000), lastErrorCode: 'firestore_unavailable',
  }) }]);
  const outbox = adapter(store);
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending',
    expectedVersion: 4, now: now - 60_000, leaseExpiresAt: now + 10_000,
  }), { claimed: false, reason: 'retry_scheduled' });

  store.docs.set(operationId, { data: v2({
    state: 'processing', attemptCount: 1, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now - 1),
  }), updateTime: 1 });
  assert.equal(await outbox.transition({
    eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001',
    expectedState: 'processing', expectedVersion: 4, now: now - 60_000,
    patch: { state: 'synced', syncedAt: now - 60_000 },
  }), false);
});

test('renewal and completion require the current unexpired lease token', async () => {
  const clock = { value: now };
  const store = memoryStore([{ id: operationId, data: v2({
    state: 'processing', attemptCount: 1, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now + 5_000),
  }) }]);
  const outbox = adapter(store, workerA, () => clock.value);
  const lease = { eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedVersion: 4 };
  assert.equal(await outbox.renewLease({ ...lease, expectedState: 'processing', now, leaseExpiresAt: now + 10_000 }), true);
  assert.equal(await outbox.transition({ ...lease, leaseToken: 'wrong-token-00000000', expectedState: 'processing', expectedVersion: 4, now, patch: { state: 'synced', syncedAt: now } }), false);
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now, patch: { state: 'synced', syncedAt: now } }), true);
  const event = store.docs.get(operationId).data;
  assert.equal(event.state, 'synced');
  assert.equal(event.workerId, null);
  assert.equal(event.leaseToken, null);
  assert.equal(event.syncedAt.getTime(), now);
  clock.value = now + 30_000;
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'synced', syncedAt: now } }), false);
});

test('readClaimed returns data only to the current server worker while its lease remains active', async () => {
  const clock = { value: now };
  const store = memoryStore([{ id: operationId, data: v2({
    state: 'processing', attemptCount: 1, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now + 5_000),
  }) }]);
  const outbox = adapter(store, workerA, () => clock.value);
  const lease = { eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedVersion: 4 };
  assert.equal((await outbox.readClaimed(lease)).operationId, operationId);
  assert.equal(await outbox.readClaimed({ ...lease, workerId: workerB.workerId }), null);
  clock.value += 5_000;
  assert.equal(await outbox.readClaimed(lease), null);
});

test('retry persists a Timestamp-compatible Date and only allowlisted error codes', async () => {
  const store = memoryStore([{ id: operationId, data: v1({
    state: 'processing', attemptCount: 1, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now + 5_000),
  }) }]);
  const outbox = adapter(store);
  const lease = { eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedVersion: 4 };
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'pending', nextAttemptAt: now + 2_000, lastErrorCode: 'firestore_unavailable' } }), true);
  const event = store.docs.get(operationId).data;
  assert.equal(event.nextAttemptAt.getTime(), now + 2_000);
  assert.equal(event.leaseToken, null);
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'pending', nextAttemptAt: now + 2_000, lastErrorCode: 'raw private backend detail' } }), false);
});

test('terminal transitions clear the lease and cannot be replayed or claimed again', async () => {
  const store = memoryStore([{ id: operationId, data: v1({
    state: 'processing', attemptCount: 2, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now + 5_000),
  }) }]);
  const outbox = adapter(store);
  const lease = { eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedVersion: 4 };
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'dead_letter', lastErrorCode: 'permanent_failure' } }), true);
  const event = store.docs.get(operationId).data;
  assert.equal(event.state, 'dead_letter');
  assert.equal(event.leaseExpiresAt, null);
  assert.equal(event.lastErrorCode, 'permanent_failure');
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'superseded' } }), false);
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerA.workerId, leaseToken: 'lease-token-00000002', expectedState: 'dead_letter',
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  }), { claimed: false, reason: 'terminal' });
});

test('superseded transition clears retry and lease metadata without changing event identity', async () => {
  const store = memoryStore([{ id: operationId, data: v1({
    state: 'processing', attemptCount: 1, workerId: workerA.workerId,
    leaseToken: 'lease-token-00000001', leaseExpiresAt: new Date(now + 5_000),
    lastErrorCode: 'unknown_transient',
  }) }]);
  const outbox = adapter(store);
  const lease = { eventId: operationId, workerId: workerA.workerId, leaseToken: 'lease-token-00000001', expectedVersion: 4 };
  assert.equal(await outbox.transition({ ...lease, expectedState: 'processing', expectedVersion: 4, now,
    patch: { state: 'superseded' } }), true);
  const event = store.docs.get(operationId).data;
  assert.equal(event.state, 'superseded');
  assert.equal(event.operationId, operationId);
  assert.equal(event.version, 4);
  assert.equal(event.leaseToken, null);
  assert.equal(event.nextAttemptAt, null);
  assert.equal(event.lastErrorCode, null);
});

test('paged eligible query pins readTime and advances by stable document name', async () => {
  const store = memoryStore();
  const snapshotReadTime = new Date(now - 5_000).toISOString();
  const pages = [
    { documents: [{ id: 'event-1', data: v1() }], readTime: snapshotReadTime, nextDocumentId: 'event-1', hasMore: true },
    { documents: [{ id: 'event-2', data: v2() }], readTime: snapshotReadTime, nextDocumentId: null, hasMore: false },
  ];
  store.queryOutboxPage = async (options) => { store.queries.push(structuredClone(options)); return pages.shift(); };
  const outbox = adapter(store);
  const first = await outbox.listEligibleEvents({ limit: 1 });
  assert.equal(first.events.length, 1);
  assert.ok(first.nextCursor);
  const second = await outbox.listEligibleEvents({ limit: 1, cursor: first.nextCursor });
  assert.equal(second.events.length, 1);
  assert.equal(second.nextCursor, null);
  assert.equal(store.queries[0].readTime, snapshotReadTime);
  assert.equal(store.queries[1].readTime, snapshotReadTime);
  assert.equal(store.queries[1].startAfterDocumentId, 'event-1');
});

test('bounded scanning skips future retries and active leases, then returns later eligible V1/V2 events', async () => {
  const store = memoryStore();
  const snapshotReadTime = new Date(now - 5_000).toISOString();
  const pages = [
    { documents: [
      { id: 'event-a-backoff', data: v2({ attemptCount: 1, nextAttemptAt: new Date(now + 1_000), lastErrorCode: 'catalog_unavailable' }) },
      { id: 'event-b-lease', data: v2({ state: 'processing', attemptCount: 1, workerId: workerB.workerId, leaseToken: 'lease-token-00000002', leaseExpiresAt: new Date(now + 1_000) }) },
    ], readTime: snapshotReadTime, nextDocumentId: 'event-b-lease', hasMore: true },
    { documents: [
      { id: 'event-c-malformed', data: v2({ attemptCount: 1, nextAttemptAt: 'bad-timestamp', lastErrorCode: 'catalog_unavailable' }) },
      { id: 'event-d-legacy', data: v1({ operationId: '00000000-0000-4000-8000-000000000004' }) },
    ], readTime: snapshotReadTime, nextDocumentId: 'event-d-legacy', hasMore: true },
  ];
  store.queryOutboxPage = async (options) => { store.queries.push(structuredClone(options)); return pages.shift(); };
  const outbox = adapter(store);
  const page = await outbox.listEligibleEvents({ limit: 1, scanPageSize: 2, maxPages: 3 });

  assert.deepEqual(page.events.map((event) => event.id), ['event-d-legacy']);
  assert.equal(page.scannedPages, 2);
  assert.equal(page.scannedDocuments, 4);
  assert.equal(page.eligibleCount, 1);
  assert.equal(store.queries.length, 2);
  assert.equal(store.queries[1].readTime, snapshotReadTime);
  assert.equal(store.queries[1].startAfterDocumentId, 'event-b-lease');
  assert.ok(page.nextCursor, 'unscanned documents in the second page must resume after this batch');
});

test('bounded scanning returns a continuation cursor after exhausting its scan budget', async () => {
  const store = memoryStore();
  const snapshotReadTime = new Date(now - 5_000).toISOString();
  const pages = [
    { documents: [{ id: 'event-a', data: v2({ attemptCount: 1, nextAttemptAt: new Date(now + 1_000), lastErrorCode: 'catalog_unavailable' }) }], readTime: snapshotReadTime, nextDocumentId: 'event-a', hasMore: true },
    { documents: [{ id: 'event-b', data: v2({ state: 'processing', attemptCount: 1, workerId: workerB.workerId, leaseToken: 'lease-token-00000002', leaseExpiresAt: new Date(now + 1_000) }) }], readTime: snapshotReadTime, nextDocumentId: 'event-b', hasMore: true },
    { documents: [{ id: 'event-c', data: v1({ operationId: '00000000-0000-4000-8000-000000000003' }) }], readTime: snapshotReadTime, nextDocumentId: null, hasMore: false },
  ];
  store.queryOutboxPage = async (options) => { store.queries.push(structuredClone(options)); return pages.shift(); };
  const outbox = adapter(store);
  const first = await outbox.listEligibleEvents({ limit: 2, scanPageSize: 1, maxPages: 2 });
  assert.equal(first.events.length, 0);
  assert.equal(first.scannedPages, 2);
  assert.ok(first.nextCursor);
  const second = await outbox.listEligibleEvents({ limit: 2, scanPageSize: 1, maxPages: 2, cursor: first.nextCursor });
  assert.deepEqual(second.events.map((event) => event.id), ['event-c']);
  assert.equal(second.scannedPages, 1);
  assert.equal(store.queries.length, 3);
  assert.equal(store.queries[2].readTime, snapshotReadTime);
  assert.equal(store.queries[2].startAfterDocumentId, 'event-b');
});

test('insertions behind a stable snapshot cursor are seen on the next sweep, not lost', async () => {
  let clock = now;
  const store = memoryStore();
  const readTimes = [];
  let firstSweep = true;
  store.queryOutboxPage = async (options) => {
    store.queries.push(structuredClone(options));
    readTimes.push(options.readTime);
    if (firstSweep && !options.startAfterDocumentId) {
      firstSweep = false;
      return { documents: [{ id: 'event-a', data: v1({ operationId }) }], readTime: options.readTime,
        nextDocumentId: 'event-a', hasMore: true };
    }
    if (options.startAfterDocumentId === 'event-a') {
      return { documents: [{ id: 'event-z', data: v1({ operationId: '00000000-0000-4000-8000-000000000009' }) }],
        readTime: options.readTime, nextDocumentId: null, hasMore: false };
    }
    return { documents: [{ id: 'event-0-inserted', data: v1({ operationId: '00000000-0000-4000-8000-000000000008' }) }],
      readTime: options.readTime, nextDocumentId: null, hasMore: false };
  };
  const outbox = adapter(store, workerA, () => clock);

  const currentSweep = await outbox.listEligibleEvents({ limit: 10, scanPageSize: 1, maxPages: 3 });
  assert.deepEqual(currentSweep.events.map((item) => item.id), ['event-a', 'event-z']);
  assert.equal(currentSweep.nextCursor, null);
  clock += 10_000;
  const nextSweep = await outbox.listEligibleEvents({ limit: 10, scanPageSize: 1, maxPages: 3 });
  assert.deepEqual(nextSweep.events.map((item) => item.id), ['event-0-inserted']);
  assert.notEqual(readTimes[0], readTimes.at(-1));
  assert.equal(readTimes[0], readTimes[1], 'all pages in one sweep must use the same readTime');
});

test('expired snapshot reopens at a fresh readTime while preserving the last document ID', async () => {
  let clock = now;
  const expiredReadTime = new Date(now - 56 * 60_000).toISOString();
  const expiredCursor = btoa(JSON.stringify({ v: 1, readTime: expiredReadTime, lastDocumentId: 'event-legacy-20' }))
    .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
  const store = memoryStore();
  store.queryOutboxPage = async (options) => {
    store.queries.push(structuredClone(options));
    return { documents: [{ id: 'event-legacy-21', data: v1({ operationId: '00000000-0000-4000-8000-000000000021' }) }],
      readTime: options.readTime, nextDocumentId: null, hasMore: false };
  };
  const outbox = adapter(store, workerA, () => clock);

  const page = await outbox.listEligibleEvents({ limit: 1, cursor: expiredCursor });

  assert.deepEqual(page.events.map((event) => event.id), ['event-legacy-21']);
  assert.equal(store.queries[0].startAfterDocumentId, 'event-legacy-20');
  assert.equal(store.queries[0].readTime, new Date(now - 5_000).toISOString());
  assert.notEqual(store.queries[0].readTime, expiredReadTime);
  assert.equal(page.nextCursor, null);
});

test('filters active leases and delayed retries and rejects a changed snapshot or unstable ordering', async () => {
  const store = memoryStore();
  const snapshotReadTime = new Date(now - 5_000).toISOString();
  const pages = [
    { documents: [
      { id: 'event-a', data: v1() },
      { id: 'event-b', data: v2({ state: 'pending', attemptCount: 1, nextAttemptAt: new Date(now + 1), lastErrorCode: 'firestore_unavailable' }) },
      { id: 'event-c', data: v2({ state: 'processing', attemptCount: 1, workerId: workerB.workerId, leaseToken: 'lease-token-00000002', leaseExpiresAt: new Date(now + 1) }) },
      { id: 'event-d', data: v1({ state: 'processing', attemptCount: 1 }) },
    ], readTime: snapshotReadTime, nextDocumentId: null, hasMore: false },
  ];
  store.queryOutboxPage = async () => pages.shift();
  const outbox = adapter(store);
  const page = await outbox.listEligibleEvents({ limit: 4 });
  assert.deepEqual(page.events.map((event) => event.id), ['event-a', 'event-d']);

  store.queryOutboxPage = async () => ({ documents: [
    { id: 'event-b', data: v1() }, { id: 'event-a', data: v1() },
  ], readTime: snapshotReadTime, nextDocumentId: 'event-a', hasMore: true });
  await assert.rejects(outbox.listEligibleEvents({ limit: 2 }), { code: 'backend_unavailable' });
});

test('pagination cursor and limits are validated, and permission failures fail closed', async () => {
  const store = memoryStore();
  const outbox = adapter(store);
  await assert.rejects(outbox.listEligibleEvents({ limit: 101 }), { code: 'invalid-request' });
  await assert.rejects(outbox.listEligibleEvents({ limit: 1, cursor: 'not-a-cursor' }), { code: 'invalid-request' });
  store.queryOutboxPage = async () => { const error = new Error('sensitive body'); error.code = 'backend_unavailable'; throw error; };
  await assert.rejects(outbox.listEligibleEvents({ limit: 1 }), (error) => {
    assert.equal(error.code, 'backend_unavailable');
    assert.equal(error.message.includes('sensitive'), false);
    return true;
  });
  store.runTransaction = async () => { const error = new Error('permission denied with details'); error.code = 'backend_unavailable'; throw error; };
  await assert.rejects(outbox.inspect(operationId), { code: 'backend_unavailable' });
});

test('server identity is mandatory and caller identity cannot impersonate it', async () => {
  const store = memoryStore([{ id: operationId, data: v1() }]);
  assert.throws(() => createFirebaseFirestoreOutboxAdapter({ store }), { code: 'invalid-request' });
  const outbox = adapter(store, workerA);
  assert.deepEqual(await outbox.claim(operationId, {
    workerId: workerB.workerId, leaseToken: 'lease-token-00000001', expectedState: 'pending',
    expectedVersion: 4, now, leaseExpiresAt: now + 10_000,
  }), { claimed: false, reason: 'invalid_request' });
});
