import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import test from 'node:test';
import { createCatalogOutboxProcessor } from './catalog_outbox_processor.mjs';
import { createCatalogOutboxScanCheckpoint } from './catalog_outbox_scan_checkpoint.mjs';
import { createCatalogOutboxScanRunner } from './catalog_outbox_scan_runner.mjs';
import { createFirebaseFirestoreOutboxAdapter } from './firebase_firestore_outbox_adapter.mjs';
import { createFirebaseFirestoreRestStore } from './firebase_firestore_rest.mjs';

const projectId = 'demo-universal-search';
const emulatorHost = process.env.FIRESTORE_EMULATOR_HOST;
const enabled = process.env.CATALOG_OUTBOX_SCAN_EMULATOR_TEST === '1';
const address = parseLoopbackAddress(emulatorHost);

test('Firestore Emulator scan checkpoint advances past backoff and active leases without starvation', {
  skip: !enabled || !address
    ? 'Requires explicit opt-in and a loopback Firestore Emulator.'
    : false,
}, async () => {
  const emulatorOrigin = `http://${address.host === '::1' ? '[::1]' : address.host}:${address.port}`;
  const fetchImpl = async (url, init) => {
    if (!String(url).startsWith(`${emulatorOrigin}/v1/projects/${projectId}/`)) {
      throw new Error('Firestore Emulator request escaped the configured loopback origin.');
    }
    return fetch(url, init);
  };
  const store = createFirebaseFirestoreRestStore({
    projectId,
    emulator: { host: address.host, port: address.port },
    fetchImpl,
  });
  const adapter = createFirebaseFirestoreOutboxAdapter({
    store,
    serverIdentity: { workerId: 'sweep-emulator-worker' },
  });
  const checkpoint = createCatalogOutboxScanCheckpoint({
    store,
    workerId: 'sweep-emulator-worker',
    createLeaseToken: randomUUID,
  });
  const processedOperations = [];
  const processor = createCatalogOutboxProcessor({
    store,
    serverIdentity: { workerId: 'sweep-emulator-worker' },
    createLeaseToken: randomUUID,
    pageSize: 1,
    scanPageSize: 10,
    maxScanPages: 3,
    leaseDurationMs: 60_000,
    rpc: async (name, args) => {
      const value = args.p_projection ?? args.p_tombstone;
      assert.equal(name, 'apply_establishment_projection_v2');
      processedOperations.push(value.outbox_operation_id);
      return { data: 'applied', error: null };
    },
  });
  const runner = createCatalogOutboxScanRunner({
    checkpoint,
    processPage: processor.processPage,
    pageSize: 1,
  });

  const now = Date.now();
  const timestamp = new Date(now);
  const operationIdFor = (sequence) =>
    `00000000-0000-4000-8000-${String(sequence).padStart(12, '0')}`;
  await store.runTransaction(async (transaction) => {
    for (let sequence = 1; sequence <= 27; sequence += 1) {
      const operationId = operationIdFor(sequence);
      const entityId = `scan-emulator-${sequence}`;
      const pending = sequence <= 12;
      const activeLease = sequence >= 13 && sequence <= 25;
      const event = sequence === 27
        ? {
          schemaVersion: 1,
          operationId,
          entityType: 'establishment',
          entityId,
          authorUid: 'synthetic-admin',
          version: 1,
          operation: 'reconcile',
          state: 'pending',
          attemptCount: 0,
        }
        : {
          schemaVersion: 2,
          operationId,
          entityType: 'establishment',
          entityId,
          authorUid: 'synthetic-admin',
          version: 1,
          operation: 'reconcile',
          state: activeLease ? 'processing' : 'pending',
          attemptCount: activeLease ? 1 : 0,
          workerId: activeLease ? 'unrelated-live-worker' : null,
          leaseToken: activeLease ? `active-lease-token-${sequence}` : null,
          leaseExpiresAt: activeLease ? new Date(now + 60_000) : null,
          nextAttemptAt: pending ? new Date(now + 60_000) : null,
          lastErrorCode: null,
          syncedAt: null,
          createdAt: timestamp,
          updatedAt: timestamp,
        };
      transaction.create('catalog_outbox', operationId, event);

      if (sequence >= 26) {
        transaction.create('establishments', entityId, {
          name: `Emulator listing ${sequence}`,
          description: 'Synthetic pagination fixture.',
          category: 'Comércio',
          subcategory: 'Teste',
          published: true,
          active: true,
          catalogVersion: 1,
          outboxOperationId: operationId,
          publicContactApproved: false,
          deletedAt: null,
          ownerEmail: 'private-sentinel@example.test',
        });
      }
    }
  });

  // The scanner intentionally starts 5 seconds behind its clock to avoid
  // racing recent commits; wait until this synthetic snapshot is queryable.
  await new Promise((resolve) => setTimeout(resolve, 5_200));

  const first = await runner.run();
  assert.equal(first.scannedPages, 3);
  assert.equal(first.scannedDocuments, 26);
  assert.equal(first.eligibleCount, 1);
  assert.equal(first.results[0]?.state, 'synced');
  assert.deepEqual(processedOperations, [operationIdFor(26)]);

  const checkpointAfterFirst = await store.runTransaction((transaction) =>
    transaction.get('catalog_outbox_scan_state', 'consumer-v1'));
  assert.ok(checkpointAfterFirst?.data.cursor);
  assert.equal(checkpointAfterFirst.data.cursorReadTime, first.readTime);
  assert.equal((await adapter.inspect(operationIdFor(26))).state, 'synced');
  assert.equal((await adapter.inspect(operationIdFor(27))).state, 'pending');

  const second = await runner.run();
  assert.equal(second.scannedPages, 1);
  assert.equal(second.scannedDocuments, 1);
  assert.equal(second.eligibleCount, 1);
  assert.equal(second.results[0]?.state, 'synced');
  assert.deepEqual(processedOperations, [operationIdFor(26), operationIdFor(27)]);

  const checkpointAfterSecond = await store.runTransaction((transaction) =>
    transaction.get('catalog_outbox_scan_state', 'consumer-v1'));
  assert.equal(checkpointAfterSecond.data.cursor, null);
  assert.equal(checkpointAfterSecond.data.cursorReadTime, null);
  assert.equal((await adapter.inspect(operationIdFor(27))).state, 'synced');
  assert.equal((await adapter.inspect(operationIdFor(1))).state, 'pending');
  assert.equal((await adapter.inspect(operationIdFor(13))).state, 'processing');
});

function parseLoopbackAddress(value) {
  const match = /^(127\.0\.0\.1|::1):(\d{1,5})$/u.exec(value ?? '');
  if (!match) return null;
  const port = Number(match[2]);
  return Number.isSafeInteger(port) && port > 0 && port <= 65_535
    ? { host: match[1], port }
    : null;
}
