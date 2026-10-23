import assert from 'node:assert/strict';
import test from 'node:test';
import { DEFAULT_RETRY_POLICY, calculateRetryDelayMs, projectCanonicalEstablishment } from './catalog_outbox_protocol.mjs';
import { createCatalogOutboxProcessor } from './catalog_outbox_processor.mjs';

const NOW = Date.parse('2026-10-20T12:00:00.000Z');
const OP_A = '00000000-0000-4000-8000-000000000001';
const OP_B = '00000000-0000-4000-8000-000000000002';
const ENTITY = 'modelo-established-legacy-01';

test('shared default retry policy is bounded and exported for runtime composition', () => {
  assert.deepEqual(DEFAULT_RETRY_POLICY, { baseDelayMs: 1_000, maximumDelayMs: 60_000, maxAttempts: 8 });
  assert.deepEqual([1, 2, 3, 9].map((attempt) => calculateRetryDelayMs(attempt, DEFAULT_RETRY_POLICY)),
    [1_000, 2_000, 4_000, 60_000]);
});

function event(operationId = OP_A, schemaVersion = 2, overrides = {}) {
  return {
    schemaVersion, operationId, entityType: 'establishment', entityId: ENTITY,
    authorUid: 'synthetic-admin', version: 4, operation: 'reconcile', state: 'pending',
    attemptCount: 0,
    ...(schemaVersion === 2 ? {
      createdAt: new Date(NOW), updatedAt: new Date(NOW), workerId: null, leaseToken: null,
      leaseExpiresAt: null, nextAttemptAt: null, lastErrorCode: null, syncedAt: null,
    } : {}),
    ...overrides,
  };
}

function source(overrides = {}) {
  return {
    name: 'Mercado de Teste', description: 'Conteúdo público sintético', category: 'Comércio',
    subcategory: 'Mercado', published: true, active: true, catalogVersion: 4,
    outboxOperationId: OP_A, publicContactApproved: false, deletedAt: null,
    ownerEmail: 'private-sentinel@example.test', adminNote: 'must-not-be-projected', ...overrides,
  };
}

function createMemoryFirestore(events = [event()]) {
  const outbox = new Map(events.map((item) => [item.operationId, { data: structuredClone(item), updateTime: 1 }]));
  const canonical = new Map([[ENTITY, source()]]);
  let sequence = 1;
  let tail = Promise.resolve();
  let failTransitionOnce = false;
  let onQuery;

  return {
    outbox,
    canonical,
    setQueryHook(hook) { onQuery = hook; },
    failNextTransition() { failTransitionOnce = true; },
    async runTransaction(callback) {
      let release;
      const prior = tail;
      tail = new Promise((resolve) => { release = resolve; });
      await prior;
      const writes = [];
      const transaction = {
        async get(collection, id) {
          const map = collection === 'catalog_outbox' ? outbox : canonical;
          const current = map.get(id);
          if (!current) return null;
          return collection === 'catalog_outbox'
            ? { data: structuredClone(current.data), updateTime: String(current.updateTime ?? 1) }
            : { data: structuredClone(current), updateTime: '1' };
        },
        update(collection, id, value, options = {}) { writes.push({ collection, id, value: structuredClone(value), options }); },
      };
      try {
        const result = await callback(transaction);
        for (const write of writes) {
          if (failTransitionOnce && write.collection === 'catalog_outbox' && write.value.state === 'synced') {
            failTransitionOnce = false;
            throw Object.assign(new Error('private synthetic failure'), { code: 'backend_unavailable' });
          }
          const map = write.collection === 'catalog_outbox' ? outbox : canonical;
          const current = map.get(write.id);
          if (!current || (write.options.updateTime && String(current.updateTime) !== write.options.updateTime)) {
            throw Object.assign(new Error('synthetic transaction conflict'), { code: 'conflict' });
          }
          const value = { ...current.data, ...write.value };
          for (const field of write.options.serverTimestampFields ?? []) value[field] = new Date(NOW + sequence);
          map.set(write.id, { data: value, updateTime: ++sequence });
        }
        return result;
      } finally { release(); }
    },
    async queryOutboxPage({ limit, readTime, startAfterDocumentId }) {
      await onQuery?.();
      const all = [...outbox.entries()].sort(([a], [b]) => a.localeCompare(b))
        .filter(([id]) => !startAfterDocumentId || id > startAfterDocumentId)
        .filter(([, value]) => ['pending', 'processing'].includes(value.data.state));
      const selected = all.slice(0, limit);
      const hasMore = all.length > selected.length;
      return {
        documents: selected.map(([id, value]) => ({ id, data: structuredClone(value.data) })),
        readTime, hasMore, nextDocumentId: hasMore ? selected.at(-1)?.[0] : null,
      };
    },
  };
}

function createDestination() {
  const rows = new Map();
  const tombstones = new Map();
  const calls = [];
  let failNext = null;
  let applyThenLoseAck = false;
  const rpc = async (name, args) => {
    calls.push({ name, args: structuredClone(args) });
    if (failNext) { const error = failNext; failNext = null; throw error; }
    if (applyThenLoseAck) {
      applyThenLoseAck = false;
      const payload = args.p_projection;
      rows.set(payload.id, structuredClone(payload));
      throw Object.assign(new Error('private response body'), { code: 'ECONNRESET' });
    }
    const payload = args.p_projection ?? args.p_tombstone;
    const current = rows.get(payload.id) ?? tombstones.get(payload.id);
    const version = payload.catalog_version;
    if (tombstones.has(payload.id) && args.p_projection) return { data: null, error: { code: '23514', message: 'do not expose' } };
    if (current && current.catalog_version === version) {
      const same = current.outbox_operation_id === payload.outbox_operation_id &&
        JSON.stringify(current) === JSON.stringify(payload);
      return same ? { data: 'replayed', error: null } : { data: null, error: { code: '23514' } };
    }
    if (current && current.catalog_version > version) return { data: null, error: { code: '23514' } };
    if (args.p_tombstone) tombstones.set(payload.id, structuredClone(payload));
    else rows.set(payload.id, structuredClone(payload));
    return { data: 'applied', error: null };
  };
  return {
    rows, tombstones, calls, rpc,
    failNext(error) { failNext = error; },
    applyThenLoseAck() { applyThenLoseAck = true; },
  };
}

function processor(store, destination, options = {}) {
  let token = 0;
  return createCatalogOutboxProcessor({
    store, serverIdentity: { workerId: options.workerId ?? 'worker-a' },
    rpc: destination.rpc, now: () => options.now ?? NOW,
    createLeaseToken: () => `synthetic-lease-token-${String(++token).padStart(4, '0')}`,
    leaseDurationMs: options.leaseDurationMs ?? 1_000,
    pageSize: options.pageSize ?? 25,
  });
}

test('page processing claims a V1 event, calls the private projection RPC and confirms only after applied', async () => {
  const store = createMemoryFirestore([event(OP_A, 1)]);
  const destination = createDestination();
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'synced');
  assert.equal(store.outbox.get(OP_A).data.state, 'synced');
  assert.equal(destination.calls[0].name, 'apply_establishment_projection_v2');
  assert.equal(destination.rows.get(ENTITY).catalog_version, 4);
  assert.equal('ownerEmail' in destination.rows.get(ENTITY), false);
});

test('confirmed duplicate RPC replay is acknowledged without duplicating destination data', async () => {
  const store = createMemoryFirestore([event(OP_A, 2)]);
  const destination = createDestination();
  const existingProjection = projectCanonicalEstablishment(ENTITY, source(), event(OP_A, 2));
  assert.ok(existingProjection);
  assert.equal((await destination.rpc('apply_establishment_projection_v2', { p_projection: existingProjection })).data, 'applied');
  destination.calls.length = 0;
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'synced');
  assert.equal(result.results[0].write, 'duplicate');
  assert.equal(store.outbox.get(OP_A).data.state, 'synced');
});

test('writer transport failure schedules retry and does not confirm the event', async () => {
  const store = createMemoryFirestore([event(OP_A, 2)]);
  const destination = createDestination();
  destination.failNext(Object.assign(new Error('sensitive body'), { code: 'ECONNRESET' }));
  const result = await processor(store, destination).processPage();
  const persisted = store.outbox.get(OP_A).data;
  assert.equal(result.results[0].state, 'pending');
  assert.equal(persisted.state, 'pending');
  assert.equal(persisted.lastErrorCode, 'catalog_unavailable');
  assert.equal(JSON.stringify(persisted).includes('sensitive body'), false);
});

test('canonical version newer than an event marks it superseded without a writer call', async () => {
  const store = createMemoryFirestore([event(OP_A, 2)]);
  store.canonical.set(ENTITY, source({ catalogVersion: 5, outboxOperationId: OP_B }));
  const destination = createDestination();
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'superseded');
  assert.equal(destination.calls.length, 0);
});

test('permanent tombstone rejection prevents an old or later projection from resurrecting the ID', async () => {
  const store = createMemoryFirestore([event(OP_B, 2, { version: 5 })]);
  store.canonical.set(ENTITY, source({ catalogVersion: 5, outboxOperationId: OP_B }));
  const destination = createDestination();
  destination.tombstones.set(ENTITY, {
    id: ENTITY, catalog_version: 4, outbox_operation_id: OP_A, deleted_at: '2026-10-20T11:00:00.000Z',
  });
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'dead_letter');
  assert.equal(store.outbox.get(OP_B).data.lastErrorCode, 'catalog_conflict');
  assert.equal(destination.rows.has(ENTITY), false);
});

test('logical deletion is sent through the tombstone RPC and confirmed only after applied', async () => {
  const deletedAt = '2026-10-20T11:59:00.000Z';
  const store = createMemoryFirestore([event(OP_A, 2)]);
  store.canonical.set(ENTITY, source({ deletedAt }));
  const destination = createDestination();
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'synced');
  assert.equal(destination.calls[0].name, 'apply_establishment_tombstone_v2');
  assert.deepEqual(destination.calls[0].args.p_tombstone, {
    id: ENTITY, catalog_version: 4, outbox_operation_id: OP_A, deleted_at: deletedAt,
  });
  assert.equal(destination.tombstones.get(ENTITY).catalog_version, 4);
});

test('concurrent workers produce one destination write and one lease winner', async () => {
  const store = createMemoryFirestore([event(OP_A, 2)]);
  const destination = createDestination();
  const [a, b] = await Promise.all([
    processor(store, destination, { workerId: 'worker-a' }).processPage(),
    processor(store, destination, { workerId: 'worker-b' }).processPage(),
  ]);
  const outcomes = [...a.results, ...b.results];
  assert.equal(outcomes.filter((item) => item.state === 'synced').length, 1);
  assert.equal(outcomes.filter((item) => ['busy', 'changed'].includes(item.reason)).length, 1);
  assert.equal(destination.calls.length, 1);
});

test('lost lease prevents confirmation after writer returns success', async () => {
  const store = createMemoryFirestore([event(OP_A, 2)]);
  const destination = createDestination();
  store.setQueryHook(async () => {});
  // Replace the RPC with a deterministic lease takeover while the writer call is in flight.
  const rpc = destination.rpc;
  destination.rpc = async (...args) => {
    const current = store.outbox.get(OP_A).data;
    store.outbox.set(OP_A, { data: { ...current, workerId: 'worker-b', leaseToken: 'synthetic-lease-token-worker-b' }, updateTime: current.updateTime + 1 });
    return rpc(...args);
  };
  const worker = processor(store, destination);
  const result = await worker.processPage();
  assert.equal(result.results[0].state, 'lease_lost');
  assert.equal(store.outbox.get(OP_A).data.state, 'processing');
  assert.equal(destination.rows.has(ENTITY), true);
});

test('confirmed destination write followed by Firestore acknowledgement failure replays safely after lease expiry', async () => {
  let clock = NOW;
  const store = createMemoryFirestore([event(OP_A, 2)]);
  const destination = createDestination();
  store.failNextTransition();
  const worker = processor(store, destination, { now: clock });
  const first = await worker.processPage();
  assert.equal(first.results[0].state, 'ack_pending');
  assert.equal(store.outbox.get(OP_A).data.state, 'processing');
  assert.equal(destination.rows.size, 1);

  clock += 5_000;
  const replayWorker = processor(store, destination, { workerId: 'worker-b', now: clock });
  const second = await replayWorker.processPage();
  assert.equal(second.results[0].state, 'synced');
  assert.equal(second.results[0].write, 'duplicate');
  assert.equal(destination.rows.size, 1);
});

test('expired processing lease is reclaimed and page cursors retain snapshot pagination', async () => {
  const oldLease = event(OP_A, 2, {
    state: 'processing', attemptCount: 1, workerId: 'worker-old',
    leaseToken: 'synthetic-lease-token-old', leaseExpiresAt: new Date(NOW - 1),
  });
  const secondEvent = event(OP_B, 1, { entityId: 'modelo-established-legacy-02', version: 4 });
  const store = createMemoryFirestore([oldLease, secondEvent]);
  store.canonical.set('modelo-established-legacy-02', source({
    outboxOperationId: OP_B, catalogVersion: 4,
  }));
  const destination = createDestination();
  const first = await processor(store, destination, { pageSize: 1 }).processPage();
  assert.equal(first.results.length, 1);
  assert.ok(first.nextCursor);
  const next = await processor(store, destination, { pageSize: 1 }).processPage({ cursor: first.nextCursor });
  assert.equal(next.results.length, 1);
  assert.equal(next.results[0].state, 'synced');
});

test('invalid outbox events are not sent to the writer', async () => {
  const invalid = event(OP_A, 2, { attemptCount: -1 });
  const store = createMemoryFirestore([invalid]);
  const destination = createDestination();
  const result = await processor(store, destination).processPage();
  assert.equal(result.results[0].state, 'not_processed');
  assert.equal(destination.calls.length, 0);
});

test('processor uses fixed bounded scan limits and reports scanned, eligible, and claimed separately', async () => {
  const store = createMemoryFirestore([event(OP_A, 1)]);
  const observed = [];
  const queryOutboxPage = store.queryOutboxPage.bind(store);
  store.queryOutboxPage = async (request) => {
    observed.push(request);
    return queryOutboxPage(request);
  };
  const destination = createDestination();
  const worker = createCatalogOutboxProcessor({
    store, serverIdentity: { workerId: 'worker-a' }, rpc: destination.rpc,
    now: () => NOW, createLeaseToken: () => 'synthetic-lease-token-0001',
    pageSize: 2, scanPageSize: 5, maxScanPages: 3,
  });

  const result = await worker.processPage();

  assert.equal(observed.length, 1);
  assert.equal(observed[0].limit, 5);
  assert.equal(result.scannedPages, 1);
  assert.equal(result.scannedDocuments, 1);
  assert.equal(result.eligibleCount, 1);
  assert.equal(result.claimedCount, 1);
  assert.equal(result.results[0].state, 'synced');
});

test('processor rejects unbounded, malformed, and unknown pagination inputs', async () => {
  const worker = processor(createMemoryFirestore(), createDestination(), { pageSize: 2 });
  await assert.rejects(worker.processPage({ limit: 3 }), { code: 'invalid-request' });
  await assert.rejects(worker.processPage({ cursor: 42 }), { code: 'invalid-request' });
  await assert.rejects(worker.processPage({ cursor: null, shell: true }), { code: 'invalid-request' });
  await assert.rejects(worker.processPage(null), { code: 'invalid-request' });
});
