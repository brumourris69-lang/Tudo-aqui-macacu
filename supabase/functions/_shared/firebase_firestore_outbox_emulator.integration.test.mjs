import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { createCatalogOutboxProcessor } from './catalog_outbox_processor.mjs';
import { createFirebaseFirestoreOutboxAdapter } from './firebase_firestore_outbox_adapter.mjs';
import { createFirebaseFirestoreRestStore, FirestoreRestError } from './firebase_firestore_rest.mjs';

const projectId = 'demo-universal-search';
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const address = parseLoopbackAddress(emulatorHost);
const emulatorOrigin = address && `http://${address.host === '::1' ? '[::1]' : address.host}:${address.port}`;

test('Firestore Emulator transactions, paging, V1/V2 processing and recovery', {
  skip: !address && 'FIRESTORE_EMULATOR_HOST must point to the isolated loopback Emulator.',
}, async () => {
  const requests = [];
  let claimBarrierEnabled = false;
  let claimTransactions = [];
  let claimBarrier = createClaimCommitBarrier();
  const fetchImpl = async (url, init) => {
    const target = String(url);
    if (!target.startsWith(`${emulatorOrigin}/v1/projects/${projectId}/`)) {
      throw new Error('Emulator request escaped the configured loopback origin.');
    }
    requests.push(target);
    if (claimBarrierEnabled && target.endsWith(':commit')) {
      const transaction = JSON.parse(init.body).transaction;
      claimTransactions.push(transaction);
      if (claimTransactions.length === 2) {
        claimBarrierEnabled = false;
        claimBarrier.resolveReady();
      }
      await (claimTransactions.length === 1 ? claimBarrier.firstCommit : claimBarrier.secondCommit);
    }
    try {
      const response = await fetch(url, init);
      if (process.env.FIRESTORE_EMULATOR_TRACE_ERRORS === '1' && !response.ok) {
        let status;
        try { status = (await response.clone().json())?.error?.status; } catch { status = 'unclassified'; }
        console.error(JSON.stringify({ event: 'emulator_http_error', method: init?.method ?? 'GET',
          route: new URL(target).pathname.replace(/\/(?:establishments|catalog_outbox)\/[^/]+/gu, '/{document}'),
          httpStatus: response.status, errorStatus: typeof status === 'string' ? status : 'unclassified' }));
      }
      return response;
    } catch (error) {
      if (process.env.FIRESTORE_EMULATOR_TRACE_ERRORS === '1') {
        console.error(JSON.stringify({ event: 'emulator_transport_error', method: init?.method ?? 'GET',
          route: new URL(target).pathname.replace(/\/(?:establishments|catalog_outbox)\/[^/]+/gu, '/{document}'),
          errorClass: error?.name === 'TimeoutError' ? 'timeout' : 'transport' }));
      }
      throw error;
    }
  };
  const makeStore = () => createFirebaseFirestoreRestStore({
    projectId,
    emulator: { host: address.host, port: address.port },
    fetchImpl,
  });
  const store = makeStore();
  const ids = Object.fromEntries(['race', 'v1', 'invalid', 'projection', 'ack', 'tombstone', 'retry']
    .map((key) => [key, randomUUID()]));
  const entityIds = Object.fromEntries(Object.keys(ids).map((key) => [key, `emulator-${key}-${randomUUID()}`]));
  const createdAt = new Date();
  const eventV2 = (operationId, entityId, overrides = {}) => ({
    schemaVersion: 2, operationId, entityType: 'establishment', entityId, authorUid: 'synthetic-admin',
    version: 1, operation: 'reconcile', state: 'pending', attemptCount: 0,
    createdAt, updatedAt: createdAt, workerId: null, leaseToken: null, leaseExpiresAt: null,
    nextAttemptAt: null, lastErrorCode: null, syncedAt: null, ...overrides,
  });
  const eventV1 = {
    schemaVersion: 1, operationId: ids.v1, entityType: 'establishment', entityId: entityIds.v1,
    authorUid: 'synthetic-admin', version: 1, operation: 'reconcile', state: 'pending', attemptCount: 0,
  };
  const canonicalSource = (operationId, overrides = {}) => ({
    name: 'Emulator Synthetic Listing', description: 'Test-only public summary', category: 'Comércio',
    subcategory: 'Teste', published: true, active: true, catalogVersion: 1,
    outboxOperationId: operationId, publicContactApproved: false, deletedAt: null,
    ownerEmail: 'private-sentinel@example.test', adminNote: 'must-not-be-projected', ...overrides,
  });
  const invalidV2 = eventV2(ids.invalid, entityIds.invalid);
  delete invalidV2.syncedAt;
  await store.runTransaction(async (transaction) => {
    for (const [key, operationId] of Object.entries(ids)) {
      const entityId = entityIds[key];
      if (key !== 'invalid') transaction.create('establishments', entityId, canonicalSource(operationId, {
        ...(key === 'tombstone' ? { deletedAt: new Date(Date.now() - 1_000).toISOString() } : {}),
      }));
      transaction.create('catalog_outbox', operationId,
        key === 'v1' ? eventV1 : key === 'invalid' ? invalidV2 : eventV2(operationId, entityId),
        { serverTimestampFields: ['createdAt', 'updatedAt'] });
    }
  });

  // The adapter pins queries to now - 5s so the initial snapshot cannot race
  // documents just created by this test.
  await new Promise((resolve) => setTimeout(resolve, 5_200));

  let clock = Date.now();
  const workerA = createFirebaseFirestoreOutboxAdapter({
    store: makeStore(), serverIdentity: { workerId: 'emulator-worker-a' },
    now: () => clock, leaseDurationMs: 5_000,
  });
  const workerB = createFirebaseFirestoreOutboxAdapter({
    store: makeStore(), serverIdentity: { workerId: 'emulator-worker-b' },
    now: () => clock, leaseDurationMs: 5_000,
  });
  const [snapshotA, snapshotB] = await Promise.all([
    workerA.inspect(ids.race), workerB.inspect(ids.race),
  ]);
  assert.equal(snapshotA.state, 'pending');
  assert.equal(snapshotB.state, 'pending');
  claimTransactions = [];
  claimBarrier = createClaimCommitBarrier();
  claimBarrierEnabled = true;
  const claimA = workerA.claim(ids.race, {
    workerId: 'emulator-worker-a', leaseToken: 'emulator-lease-token-worker-a',
    expectedState: 'pending', expectedVersion: 1, now: clock, leaseExpiresAt: clock + 5_000,
  });
  const claimB = workerB.claim(ids.race, {
    workerId: 'emulator-worker-b', leaseToken: 'emulator-lease-token-worker-b',
    expectedState: 'pending', expectedVersion: 1, now: clock, leaseExpiresAt: clock + 5_000,
  });
  const settledA = claimA.then((value) => ({ value }), (error) => ({ error }));
  const settledB = claimB.then((value) => ({ value }), (error) => ({ error }));
  const readyTimeout = setTimeout(() => claimBarrier.resolveReady(), 5_000);
  await claimBarrier.ready;
  clearTimeout(readyTimeout);
  if (claimTransactions.length !== 2) {
    claimBarrier.resolveFirst();
    claimBarrier.resolveSecond();
    await Promise.allSettled([claimA, claimB]);
    assert.equal(claimTransactions.length, 2, 'both transactions must reach commit before either is released');
  }
  claimBarrier.resolveFirst();
  await Promise.race([settledA, settledB]);
  claimBarrier.resolveSecond();
  const claimOutcomes = await Promise.all([settledA, settledB]);
  if (claimOutcomes.some((item) => item.error)) throw claimOutcomes.find((item) => item.error).error;
  const simultaneousClaims = claimOutcomes.map((item) => item.value);
  assert.equal(claimTransactions.length, 2);
  assert.equal(new Set(claimTransactions).size, 2, 'claims must use distinct Firestore transactions');
  assert.equal(simultaneousClaims.filter((item) => item.claimed).length, 1,
    `exactly one transaction should claim the event: ${JSON.stringify(simultaneousClaims)}`);
  const winningIndex = simultaneousClaims.findIndex((item) => item.claimed);
  const winningWorker = winningIndex === 0 ? workerA : workerB;
  const winningId = winningIndex === 0 ? 'emulator-worker-a' : 'emulator-worker-b';
  const winningToken = winningIndex === 0 ? 'emulator-lease-token-worker-a' : 'emulator-lease-token-worker-b';
  const winningLease = { eventId: ids.race, workerId: winningId, leaseToken: winningToken, expectedVersion: 1 };
  let persisted = await winningWorker.inspect(ids.race);
  assert.equal(persisted.state, 'processing');
  assert.equal(persisted.attemptCount, 1);
  assert.equal(persisted.leaseToken, winningToken);

  clock += 100;
  assert.equal(await winningWorker.renewLease({
    ...winningLease, expectedState: 'processing', expectedVersion: 1,
    now: clock, leaseExpiresAt: clock + 20_000,
  }), true);
  persisted = await winningWorker.inspect(ids.race);
  assert.ok(persisted.leaseExpiresAt.getTime() > clock);
  clock = persisted.leaseExpiresAt.getTime() + 1;
  const successor = winningIndex === 0 ? workerB : workerA;
  const successorId = winningIndex === 0 ? 'emulator-worker-b' : 'emulator-worker-a';
  const successorToken = winningIndex === 0 ? 'emulator-lease-token-successor-b' : 'emulator-lease-token-successor-a';
  assert.deepEqual(await successor.claim(ids.race, {
    workerId: successorId, leaseToken: successorToken, expectedState: 'processing',
    expectedVersion: 1, now: clock, leaseExpiresAt: clock + 5_000,
  }), { claimed: true });
  assert.equal(await winningWorker.transition({
    ...winningLease, expectedState: 'processing', expectedVersion: 1, now: clock,
    patch: { state: 'synced', syncedAt: clock },
  }), false, 'the former lease holder must not confirm after takeover');
  assert.equal(await successor.transition({
    eventId: ids.race, workerId: successorId, leaseToken: successorToken,
    expectedState: 'processing', expectedVersion: 1, now: clock,
    patch: { state: 'dead_letter', lastErrorCode: 'permanent_failure' },
  }), true);
  assert.equal((await successor.inspect(ids.race)).state, 'dead_letter');

  const v1Adapter = createFirebaseFirestoreOutboxAdapter({
    store, serverIdentity: { workerId: 'emulator-v1-worker' }, now: () => clock, leaseDurationMs: 5_000,
  });
  assert.deepEqual(await v1Adapter.claim(ids.v1, {
    workerId: 'emulator-v1-worker', leaseToken: 'emulator-lease-token-v1-worker',
    expectedState: 'pending', expectedVersion: 1, now: clock, leaseExpiresAt: clock + 5_000,
  }), { claimed: true });
  let v1Persisted = await v1Adapter.inspect(ids.v1);
  assert.equal(v1Persisted.schemaVersion, 1);
  assert.equal(v1Persisted.attemptCount, 1);
  assert.equal(await v1Adapter.transition({
    eventId: ids.v1, workerId: 'emulator-v1-worker', leaseToken: 'emulator-lease-token-v1-worker',
    expectedState: 'processing', expectedVersion: 1, now: clock,
    patch: { state: 'pending', nextAttemptAt: clock + 1_000, lastErrorCode: 'firestore_unavailable' },
  }), true);
  clock += 1_001;
  assert.deepEqual(await v1Adapter.claim(ids.v1, {
    workerId: 'emulator-v1-worker', leaseToken: 'emulator-lease-token-v1-retry',
    expectedState: 'pending', expectedVersion: 1, now: clock, leaseExpiresAt: clock + 5_000,
  }), { claimed: true });
  v1Persisted = await v1Adapter.inspect(ids.v1);
  assert.equal(v1Persisted.attemptCount, 2);

  const invalidAdapter = createFirebaseFirestoreOutboxAdapter({
    store, serverIdentity: { workerId: 'emulator-invalid-worker' }, now: () => Date.now(),
  });
  assert.deepEqual(await invalidAdapter.claim(ids.invalid, {
    workerId: 'emulator-invalid-worker', leaseToken: 'emulator-lease-token-invalid',
    expectedState: 'pending', expectedVersion: 1, now: Date.now(), leaseExpiresAt: Date.now() + 10_000,
  }), { claimed: false, reason: 'invalid_event' });

  const pager = createFirebaseFirestoreOutboxAdapter({
    store, serverIdentity: { workerId: 'emulator-pager' }, now: () => Date.now(),
  });
  const firstPage = await pager.listEligibleEvents({ limit: 2 });
  assert.ok(firstPage.nextCursor);
  const secondPage = await pager.listEligibleEvents({ limit: 2, cursor: firstPage.nextCursor });
  assert.equal(secondPage.readTime, firstPage.readTime);
  assert.ok(secondPage.events.every((item) => item.id > firstPage.events.at(-1).id));
  const expiredCursorData = JSON.parse(Buffer.from(firstPage.nextCursor, 'base64url').toString('utf8'));
  const expiredReadTime = new Date(Date.now() - 46 * 60 * 1_000).toISOString();
  const expiredCursor = Buffer.from(JSON.stringify({ ...expiredCursorData, readTime: expiredReadTime }))
    .toString('base64url');
  const expiredPager = createFirebaseFirestoreOutboxAdapter({
    store, serverIdentity: { workerId: 'emulator-expired-cursor' }, now: () => Date.now(),
  });
  const rebasedPage = await expiredPager.listEligibleEvents({ limit: 2, cursor: expiredCursor });
  assert.notEqual(rebasedPage.readTime, expiredReadTime);
  assert.ok(rebasedPage.events.every((item) => item.id > expiredCursorData.lastDocumentId));

  const rpcRows = new Map();
  const rpcTombstones = new Map();
  let retryFailure = true;
  const rpc = async (name, args) => {
    const value = args.p_projection ?? args.p_tombstone;
    if (name === 'apply_establishment_projection_v2' && value.outbox_operation_id === ids.retry && retryFailure) {
      retryFailure = false;
      throw Object.assign(new Error('synthetic transport detail'), { code: 'ECONNRESET' });
    }
    const current = rpcRows.get(value.id) ?? rpcTombstones.get(value.id);
    if (current && current.catalog_version === value.catalog_version &&
      current.outbox_operation_id === value.outbox_operation_id) return { data: 'replayed', error: null };
    if (current && current.catalog_version >= value.catalog_version) return { data: null, error: { code: '23514' } };
    if (name === 'apply_establishment_tombstone_v2') rpcTombstones.set(value.id, structuredClone(value));
    else rpcRows.set(value.id, structuredClone(value));
    return { data: 'applied', error: null };
  };

  let failAck = true;
  const faultStore = {
    queryOutboxPage: store.queryOutboxPage,
    runTransaction(callback) {
      return store.runTransaction((transaction) => callback({
        get: (...args) => transaction.get(...args),
        create: (...args) => transaction.create(...args),
        update(collection, id, value, options) {
          if (collection === 'catalog_outbox' && id === ids.ack && value.state === 'synced' && failAck) {
            failAck = false;
            throw new FirestoreRestError('backend_unavailable');
          }
          transaction.update(collection, id, value, options);
        },
      }));
    },
  };
  const consumer = createCatalogOutboxProcessor({
    store: faultStore, serverIdentity: { workerId: 'emulator-consumer' }, rpc,
    now: () => Date.now(), createLeaseToken: () => `emulator-processor-lease-${randomUUID()}`,
    leaseDurationMs: 1_000, pageSize: 100,
  });
  const processed = await consumer.processPage();
  const outcomes = new Map(processed.results.map((item) => [item.eventId, item]));
  assert.equal(outcomes.get(ids.projection)?.state, 'synced');
  assert.equal(outcomes.get(ids.tombstone)?.state, 'synced');
  assert.equal(outcomes.get(ids.invalid)?.reason, 'invalid_event');
  assert.equal(outcomes.get(ids.retry)?.state, 'pending');
  assert.equal(outcomes.get(ids.ack)?.state, 'ack_pending');
  assert.equal(rpcRows.has(entityIds.ack), true);
  assert.equal(rpcTombstones.has(entityIds.tombstone), true);
  assert.equal(rpcRows.has(entityIds.projection), true);
  assert.equal(Object.keys(rpcRows.get(entityIds.projection)).includes('ownerEmail'), false);
  await new Promise((resolve) => setTimeout(resolve, 1_100));
  const recovered = await consumer.processPage();
  const recoveredOutcomes = new Map(recovered.results.map((item) => [item.eventId, item]));
  assert.equal(recoveredOutcomes.get(ids.ack)?.state, 'synced');
  assert.equal(recoveredOutcomes.get(ids.ack)?.write, 'duplicate');
  assert.equal(recoveredOutcomes.get(ids.retry)?.state, 'synced');
  assert.equal(recoveredOutcomes.get(ids.retry)?.write, 'applied');
  assert.equal(rpcRows.get(entityIds.ack).outbox_operation_id, ids.ack);
  assert.equal(requests.every((item) => item.startsWith(`${emulatorOrigin}/`)), true);
});

function parseLoopbackAddress(value) {
  const match = /^(127\.0\.0\.1|::1):(\d{1,5})$/u.exec(value ?? '');
  if (!match) return null;
  const port = Number(match[2]);
  return Number.isSafeInteger(port) && port > 0 && port <= 65_535
    ? { host: match[1], port } : null;
}

function createClaimCommitBarrier() {
  let resolveReady;
  let resolveFirst;
  let resolveSecond;
  return {
    ready: new Promise((resolve) => { resolveReady = resolve; }),
    firstCommit: new Promise((resolve) => { resolveFirst = resolve; }),
    secondCommit: new Promise((resolve) => { resolveSecond = resolve; }),
    resolveReady: () => resolveReady(),
    resolveFirst: () => resolveFirst(),
    resolveSecond: () => resolveSecond(),
  };
}
