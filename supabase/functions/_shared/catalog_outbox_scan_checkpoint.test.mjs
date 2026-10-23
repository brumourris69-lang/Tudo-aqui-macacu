import assert from 'node:assert/strict';
import test from 'node:test';
import { createCatalogOutboxScanCheckpoint } from './catalog_outbox_scan_checkpoint.mjs';
import { createCatalogOutboxScanRunner } from './catalog_outbox_scan_runner.mjs';

const COLLECTION = 'catalog_outbox_scan_state';
const DOCUMENT_ID = 'consumer-v1';
const START = Date.parse('2026-10-22T12:00:00.000Z');
const READ_TIME = new Date(START - 5_000).toISOString();
const CURSOR = btoa(JSON.stringify({ v: 1, readTime: READ_TIME, lastDocumentId: 'event-legacy-20' }))
  .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
const cursorAfter = (id) => btoa(JSON.stringify({ v: 1, readTime: READ_TIME, lastDocumentId: id }))
  .replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');

function memoryStore(initial = null, { beforeCommit = async () => {} } = {}) {
  const docs = new Map(initial ? [[`${COLLECTION}/${DOCUMENT_ID}`, structuredClone(initial)]] : []);
  let version = 0;
  let tail = Promise.resolve();
  return {
    docs,
    async runTransaction(callback) {
      let release;
      const prior = tail;
      tail = new Promise((resolve) => { release = resolve; });
      await prior;
      const writes = [];
      const tx = {
        async get(collection, id) {
          assert.equal(collection, COLLECTION);
          assert.equal(id, DOCUMENT_ID);
          const document = docs.get(`${collection}/${id}`);
          return document ? { data: structuredClone(document.data), updateTime: String(document.updateTime) } : null;
        },
        create(collection, id, data, options = {}) {
          assert.equal(collection, COLLECTION);
          writes.push({ kind: 'create', key: `${collection}/${id}`, data: structuredClone(data), options });
        },
        update(collection, id, data, options = {}) {
          assert.equal(collection, COLLECTION);
          writes.push({ kind: 'update', key: `${collection}/${id}`, data: structuredClone(data), options });
        },
      };
      try {
        const result = await callback(tx);
        await beforeCommit(writes);
        for (const write of writes) {
          const current = docs.get(write.key);
          if (write.kind === 'create' && current) throw Object.assign(new Error('conflict'), { code: 'conflict' });
          if (write.kind === 'update' && (!current || String(current.updateTime) !== write.options.updateTime)) {
            throw Object.assign(new Error('conflict'), { code: 'conflict' });
          }
          const data = { ...(current?.data ?? {}), ...write.data };
          for (const field of write.options.serverTimestampFields ?? []) data[field] = new Date(START + version + 1);
          docs.set(write.key, { data, updateTime: ++version });
        }
        return result;
      } finally { release(); }
    },
  };
}

function checkpoint(store, clock = () => START, workerId = 'worker-a') {
  let sequence = 0;
  return createCatalogOutboxScanCheckpoint({
    store, workerId, now: clock, createLeaseToken: () => `lease-token-${String(++sequence).padStart(8, '0')}`,
    leaseDurationMs: 180_000,
  });
}

test('checkpoint creates a leased scan state, persists continuation and resumes it after restart', async () => {
  const store = memoryStore();
  const first = checkpoint(store);
  const lease = await first.acquire();
  assert.equal(lease.acquired, true);
  assert.equal(lease.cursor, null);
  assert.equal(await first.advance(lease, { cursor: CURSOR, readTime: READ_TIME }), true);

  const restarted = checkpoint(store, () => START, 'worker-b');
  const resumed = await restarted.acquire();
  assert.equal(resumed.acquired, true);
  assert.equal(resumed.cursor, CURSOR);
  assert.equal(resumed.cursorReadTime, READ_TIME);
});

test('only one concurrent invocation owns the global scan lease', async () => {
  const store = memoryStore();
  const first = checkpoint(store, () => START, 'worker-a');
  const second = checkpoint(store, () => START, 'worker-b');
  const leases = await Promise.all([first.acquire(), second.acquire()]);
  assert.equal(leases.filter((lease) => lease.acquired).length, 1);
  assert.equal(leases.filter((lease) => lease.reason === 'busy').length, 1);
});

test('expired snapshots retain the last ID so scanner can rebase without starvation', async () => {
  const store = memoryStore();
  const first = checkpoint(store);
  const lease = await first.acquire();
  assert.equal(await first.advance(lease, { cursor: CURSOR, readTime: READ_TIME }), true);
  const expiredAt = START + 46 * 60_000;
  const next = await checkpoint(store, () => expiredAt, 'worker-after-snapshot-expiry').acquire();
  assert.equal(next.acquired, true);
  assert.equal(next.cursor, CURSOR, 'preserve the progress point so each expired snapshot does not restart at the head');
  assert.equal(next.cursorReadTime, READ_TIME);
});

test('release after a processing failure preserves the checkpoint for safe replay', async () => {
  const store = memoryStore();
  const first = checkpoint(store);
  const lease = await first.acquire();
  await first.advance(lease, { cursor: CURSOR, readTime: READ_TIME });
  const nextLease = await first.acquire();
  assert.equal(nextLease.cursor, CURSOR);
  assert.equal(await first.release(nextLease), true);
  const retry = await checkpoint(store, () => START, 'worker-retry').acquire();
  assert.equal(retry.cursor, CURSOR);
});

test('lease takeover rejects completion by the expired worker', async () => {
  const store = memoryStore();
  let time = START;
  const first = checkpoint(store, () => time, 'worker-a');
  const stale = await first.acquire();
  time += 181_000;
  const second = checkpoint(store, () => time, 'worker-b');
  const current = await second.acquire();
  assert.equal(current.acquired, true);
  assert.equal(await first.advance(stale, { cursor: CURSOR, readTime: READ_TIME }), false);
  assert.equal(await second.advance(current, { cursor: null, readTime: null }), true);
});

test('malformed checkpoint and mismatched cursor snapshot fail closed', async () => {
  const malformed = memoryStore({ schemaVersion: 9 });
  await assert.rejects(checkpoint(malformed).acquire(), { code: 'backend_unavailable' });
  const store = memoryStore();
  const runner = checkpoint(store);
  const lease = await runner.acquire();
  assert.equal(await runner.advance(lease, { cursor: CURSOR, readTime: new Date(START).toISOString() }), false);
});

test('failed initial checkpoint creation is sanitized and leaves no partial state', async () => {
  const store = memoryStore(null, {
    beforeCommit: async () => { throw new Error('synthetic credential or transport detail'); },
  });
  await assert.rejects(checkpoint(store).acquire(), {
    code: 'backend_unavailable', message: 'Firestore is unavailable.',
  });
  assert.equal(store.docs.size, 0);
});

test('failed checkpoint renewal is sanitized and preserves the active lease for retry', async () => {
  let failCommit = false;
  const store = memoryStore(null, {
    beforeCommit: async () => {
      if (failCommit) throw new Error('synthetic internal Firestore detail');
    },
  });
  const first = checkpoint(store);
  const lease = await first.acquire();
  failCommit = true;
  await assert.rejects(first.advance(lease, { cursor: CURSOR, readTime: READ_TIME }), {
    code: 'backend_unavailable', message: 'Firestore is unavailable.',
  });
  const persisted = store.docs.get(`${COLLECTION}/${DOCUMENT_ID}`).data;
  assert.equal(persisted.leaseToken, lease.leaseToken);
  assert.equal(persisted.cursor, null);
  failCommit = false;
  assert.equal(await first.advance(lease, { cursor: CURSOR, readTime: READ_TIME }), true);
});

test('failed lease cleanup does not clear state and another worker waits for expiry', async () => {
  let time = START;
  let failCommit = false;
  const store = memoryStore(null, {
    beforeCommit: async () => {
      if (failCommit) throw new Error('synthetic cleanup detail');
    },
  });
  const first = checkpoint(store, () => time, 'worker-a');
  const lease = await first.acquire();
  failCommit = true;
  await assert.rejects(first.release(lease), {
    code: 'backend_unavailable', message: 'Firestore is unavailable.',
  });
  const persisted = store.docs.get(`${COLLECTION}/${DOCUMENT_ID}`).data;
  assert.equal(persisted.leaseToken, lease.leaseToken);
  failCommit = false;
  assert.deepEqual(await checkpoint(store, () => time, 'worker-b').acquire(), {
    acquired: false, reason: 'busy',
  });
  time = lease.leaseExpiresAt + 1;
  assert.equal((await checkpoint(store, () => time, 'worker-b').acquire()).acquired, true);
});

test('consecutive bounded invocations eventually reach the end of a larger backlog and restart safely', async () => {
  const store = memoryStore();
  const cursors = [];
  const nextCursors = [cursorAfter('event-25'), cursorAfter('event-50'), null];
  let invocation = 0;
  const worker = createCatalogOutboxScanRunner({
    checkpoint: checkpoint(store), pageSize: 2,
    processPage: async ({ cursor }) => {
      cursors.push(cursor);
      const nextCursor = nextCursors[invocation++];
      return { readTime: READ_TIME, nextCursor, results: [], scannedPages: 4,
        scannedDocuments: 100, eligibleCount: 0, claimedCount: 0 };
    },
  });
  for (let index = 0; index < 3; index += 1) {
    assert.equal((await worker.run()).busy, false);
  }
  assert.deepEqual(cursors, [null, cursorAfter('event-25'), cursorAfter('event-50')]);
  const completed = await checkpoint(store, () => START, 'worker-restarted').acquire();
  assert.equal(completed.acquired, true);
  assert.equal(completed.cursor, null, 'the completed snapshot must be discarded before the next sweep');
});
