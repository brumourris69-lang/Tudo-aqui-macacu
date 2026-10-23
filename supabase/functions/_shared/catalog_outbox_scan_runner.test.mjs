import assert from 'node:assert/strict';
import test from 'node:test';
import { createCatalogOutboxScanRunner } from './catalog_outbox_scan_runner.mjs';

const CURSOR = 'eyJ2IjoxLCJyZWFkVGltZSI6IjIwMjYtMTAtMjJUMTE6NTk6NTUuMDAwWiIsImxhc3REb2N1bWVudElkIjoiZXZlbnQtMDAxIn0';
const READ_TIME = '2026-10-22T11:59:55.000Z';

function fakeCheckpoint({ busy = false, cursor = null, failAdvance = false } = {}) {
  const calls = [];
  const lease = { acquired: !busy, reason: busy ? 'busy' : undefined, workerId: 'worker-a',
    leaseToken: 'lease-token-00000001', leaseExpiresAt: 1_800_000_000_000,
    cursor, cursorReadTime: cursor ? READ_TIME : null };
  return {
    calls,
    async acquire() { calls.push(['acquire']); return lease; },
    async advance(value, checkpoint) { calls.push(['advance', value, checkpoint]); return !failAdvance; },
    async release(value) { calls.push(['release', value]); return true; },
  };
}

test('runner resumes the persisted cursor and advances only after processor completion', async () => {
  const checkpoint = fakeCheckpoint({ cursor: CURSOR });
  const seen = [];
  const runner = createCatalogOutboxScanRunner({
    checkpoint, pageSize: 2,
    processPage: async (request) => {
      seen.push(request);
      return { readTime: READ_TIME, nextCursor: null, scannedPages: 3, scannedDocuments: 75,
        eligibleCount: 2, claimedCount: 1, results: [{ state: 'synced' }, { state: 'busy' }] };
    },
  });

  const result = await runner.run();

  assert.deepEqual(seen, [{ limit: 2, cursor: CURSOR }]);
  assert.equal(checkpoint.calls[1][0], 'advance');
  assert.deepEqual(checkpoint.calls[1][2], { cursor: null, readTime: null });
  assert.equal(result.scannedPages, 3);
  assert.equal(result.scannedDocuments, 75);
  assert.equal(result.claimedCount, 1);
  assert.equal(result.busy, false);
});

test('runner does not invoke processing while another scheduled invocation holds the lease', async () => {
  const checkpoint = fakeCheckpoint({ busy: true });
  let calls = 0;
  const runner = createCatalogOutboxScanRunner({
    checkpoint, processPage: async () => { calls += 1; return { results: [] }; },
  });
  assert.deepEqual(await runner.run(), { busy: true, results: [], scannedPages: 0, scannedDocuments: 0,
    eligibleCount: 0, claimedCount: 0, readTime: null, nextCursor: null });
  assert.equal(calls, 0);
});

test('runner releases its lease with the same cursor after processor failure', async () => {
  const checkpoint = fakeCheckpoint({ cursor: CURSOR });
  const runner = createCatalogOutboxScanRunner({
    checkpoint, processPage: async () => { throw new Error('private transport detail'); },
  });
  await assert.rejects(runner.run(), /scan-failed/u);
  assert.equal(checkpoint.calls[1][0], 'release');
  assert.equal(checkpoint.calls[1][1].cursor, CURSOR);
});

test('runner fails closed if checkpoint commit is rejected after processing', async () => {
  const checkpoint = fakeCheckpoint({ failAdvance: true });
  const runner = createCatalogOutboxScanRunner({
    checkpoint, processPage: async () => ({ readTime: READ_TIME, nextCursor: CURSOR,
      scannedPages: 1, scannedDocuments: 25, eligibleCount: 0, claimedCount: 0, results: [] }),
  });
  await assert.rejects(runner.run(), /scan-failed/u);
  assert.equal(checkpoint.calls.some((call) => call[0] === 'advance'), true);
  assert.equal(checkpoint.calls.at(-1)[0], 'release', 'a still-owned lease is released after an unconfirmed checkpoint write');
});
