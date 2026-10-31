'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  BETA_BACKFILL_MAX_DOCUMENTS,
  createFirestoreSourcePageReader,
  runBetaSearchBackfill,
} = require('../beta_search_backfill');

function syntheticSources() {
  return {
    establishments: ['est-001', 'est-002', 'est-003', 'est-004'],
    routes: ['route-001', 'route-002'],
    events: ['event-001'],
  };
}

function pageReader(sources) {
  return async ({ collection, afterId, limit }) => sources[collection]
    .filter((id) => afterId == null || id > afterId)
    .slice(0, limit)
    .map((id) => ({ id }));
}

test('Beta initial indexing is capped per run and resumes from the returned cursor', async () => {
  const sources = syntheticSources();
  const index = new Map();
  const syncCalls = [];
  const synchronize = async (collection, id) => {
    syncCalls.push(`${collection}/${id}`);
    // Same semantics as the canonical backend: re-running the source sync
    // replaces one stable key instead of duplicating an index row.
    index.set(`${collection}__${id}`, { sourceCollection: collection, id });
  };

  const first = await runBetaSearchBackfill({
    listPage: pageReader(sources), synchronize, maxDocuments: 3, pageSize: 2,
  });
  assert.equal(first.processed, 3);
  assert.equal(first.complete, false);
  assert.equal(first.checkpoint.collections.establishments, 'est-003');
  assert.deepEqual([...index.keys()], [
    'establishments__est-001', 'establishments__est-002', 'establishments__est-003',
  ]);

  const second = await runBetaSearchBackfill({
    listPage: pageReader(sources), synchronize, checkpoint: first.checkpoint,
    maxDocuments: 10, pageSize: 2,
  });
  assert.equal(second.complete, true);
  assert.equal(second.processed, 4);
  assert.equal(index.size, 7);
  assert.equal(new Set(syncCalls).size, 7);
  assert.deepEqual(second.checkpoint.completed, ['establishments', 'routes', 'events']);
});

test('Beta backfill replay uses the same stable keys and skips completed collections', async () => {
  const sources = syntheticSources();
  const rows = new Map();
  const synchronize = async (collection, id) => rows.set(`${collection}__${id}`, id);
  const full = await runBetaSearchBackfill({ listPage: pageReader(sources), synchronize,
    maxDocuments: 20, pageSize: 3 });
  const replayCalls = [];
  const replay = await runBetaSearchBackfill({ listPage: async () => {
    assert.fail('completed checkpoint must not scan again');
  }, synchronize: async (collection, id) => replayCalls.push(`${collection}/${id}`),
  checkpoint: full.checkpoint, maxDocuments: 20, pageSize: 3 });
  assert.equal(full.complete, true);
  assert.equal(replay.complete, true);
  assert.equal(replay.processed, 0);
  assert.equal(rows.size, 7);
  assert.deepEqual(replayCalls, []);
});

test('Beta backfill rejects unbounded limits, bad cursors, duplicate and unknown source IDs', async () => {
  const noOp = async () => {};
  const read = pageReader(syntheticSources());
  await assert.rejects(runBetaSearchBackfill({ listPage: read, synchronize: noOp,
    maxDocuments: BETA_BACKFILL_MAX_DOCUMENTS + 1 }), /limits/u);
  await assert.rejects(runBetaSearchBackfill({ listPage: read, synchronize: noOp,
    checkpoint: { collections: { users: 'person-1' }, completed: [] } }), /cursor/u);
  await assert.rejects(runBetaSearchBackfill({ listPage: async () => [{ id: 'same' }, { id: 'same' }],
    synchronize: noOp, maxDocuments: 2, pageSize: 2 }), /ascending/u);
  await assert.rejects(runBetaSearchBackfill({ listPage: async () => [{ id: '' }],
    synchronize: noOp, maxDocuments: 1, pageSize: 1 }), /ascending/u);
});

test('Firestore page reader is allowlisted and uses stable document ID pagination', async () => {
  const calls = [];
  const snapshot = { docs: [{ id: 'est-002' }, { id: 'est-003' }] };
  const query = {
    orderBy(field) { calls.push(['orderBy', field]); return this; },
    limit(count) { calls.push(['limit', count]); return this; },
    startAfter(cursor) { calls.push(['startAfter', cursor]); return this; },
    select(field) { calls.push(['select', field]); return this; },
    async get() { return snapshot; },
  };
  const FieldPath = { documentId: () => '__name__' };
  const reader = createFirestoreSourcePageReader({ collection(name) {
    calls.push(['collection', name]); return query;
  } }, FieldPath);

  assert.deepEqual(await reader({ collection: 'establishments', afterId: 'est-001', limit: 2 }),
    [{ id: 'est-002' }, { id: 'est-003' }]);
  assert.deepEqual(calls, [
    ['collection', 'establishments'], ['orderBy', '__name__'], ['limit', 2],
    ['startAfter', 'est-001'], ['select', '__name__'],
  ]);
  await assert.rejects(reader({ collection: 'users', afterId: null, limit: 2 }), /allowlist/u);
});
