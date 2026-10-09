'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const core = require('../business_search');
const { createFirestoreStore } = require('../business_search_firestore');
const parity = require('./fixtures/business_search_parity.json');

class Stamp { constructor(ms) { this.ms = ms; } toMillis() { return this.ms; } }
const now = Date.UTC(2026, 9, 8);
const options = { now, isTimestamp: (value) => value instanceof Stamp, authorizeImage: () => false };
const doc = (extra = {}) => ({ published: true, name: 'Elétrica Vieira', category: 'Serviços',
  subcategory: 'Eletricista', description: 'Manutenção residencial', ...extra });
const request = (extra = {}) => ({ auth: { uid: 'user', token: { firebase: { sign_in_provider: 'google.com' } } },
  app: { appId: 'demo-app' }, data: { query: 'eletrica', ...extra } });

test('Node matches shared Dart normalization category and projection fixtures', () => {
  for (const sample of parity.normalization) assert.equal(core.normalize(sample.input), sample.expected);
  for (const [category, expected] of Object.entries(parity.categories)) assert.equal(core.group(category), expected);
  const sample = parity.projection;
  const result = core.buildEntry(sample.id, sample.data, options);
  assert.deepEqual(core.publicResult(result), sample.expected);
  assert.deepEqual(result.terms, sample.terms);
});

function memory() {
  const sources = new Map(); const index = new Map();
  const metrics = { indexReads: 0, sourceReads: 0, writes: 0, admissions: 0 };
  let queue = Promise.resolve();
  const store = {
    sourcesMap: sources, indexMap: index, metrics,
    transaction(body) {
      const work = queue.then(() => body({
        source: async (id) => sources.get(id) || null,
        index: async (id) => index.get(id) || null,
        replace: async (id, entry) => { metrics.writes++; index.set(id, { ...entry, indexedAt: now }); },
        remove: async (id) => { metrics.writes++; index.delete(id); },
      })); queue = work.catch(() => {}); return work;
    },
    async candidates({ anchor, filter, after, count }) {
      const found = [...index.entries()].map(([id, entry]) => ({ ...entry, indexId: `establishments__${id}` }))
        .filter((entry) => entry.prefixes.includes(anchor) && (filter === 'all' || entry.group === filter) &&
          (!after || entry.indexId > after)).sort((a, b) => a.indexId < b.indexId ? -1 : 1).slice(0, count);
      metrics.indexReads += found.length; return found;
    },
    async sources(ids) { metrics.sourceReads += ids.length; return ids.map((id) => sources.get(id) || null); },
    async admit() { metrics.admissions++; },
  };
  const backend = core.createSearchBackend({ store, isTimestamp: options.isTimestamp, now: () => now });
  return { store, backend, async add(id, data = doc()) { sources.set(id, data); await backend.synchronize(id); } };
}

test('normalization accents combining marks punctuation and shared category policy', () => {
  assert.equal(core.normalize(' ÁGUA — Elétrica\t VIEIRA '), 'agua eletrica vieira');
  assert.equal(core.normalize('E\u0301letrica'), 'eletrica');
  assert.deepEqual(core.words('Elétrica elétrica Vieira'), ['eletrica', 'vieira']);
  for (const category of ['Comércio', 'Onde comer?', 'Tecnologia', 'Saúde', 'Hospedagem']) assert.equal(core.group(category), 'commerce');
  assert.equal(core.group('Profissionais'), 'services'); assert.equal(core.group('desconhecido'), 'other');
});
test('allowlisted projection original ID optional absence unicode summary and images fail closed', () => {
  const entry = core.buildEntry('OriginalID', doc({ adminEmail: 'secret', phone: 'secret', open: false,
    imageUrl: 'https://example.com/a.png', description: '😀'.repeat(181) }), options);
  assert.equal(entry.id, 'OriginalID'); assert.equal(entry.imageUrl, '');
  assert.equal([...entry.summary].length, 180); assert.ok(!JSON.stringify(entry).includes('secret'));
  assert.deepEqual(Object.keys(core.publicResult(entry)), ['id', 'sourceCollection', 'title', 'summary',
    'category', 'subcategory', 'imageUrl', 'type', 'destination']);
  assert.equal(core.buildEntry('id', { published: true, title: 'Nome' }, options).category, '');
  assert.equal(core.buildEntry('id', { published: true }, options), null);
  const image = core.buildEntry('id', doc({ imageUrl: 'http://res.cloudinary.com/demo/image/upload/test.png' }),
    { ...options, authorizeImage: () => true });
  assert.equal(image.imageUrl, 'https://res.cloudinary.com/demo/image/upload/f_auto,q_auto,w_1600,c_limit/test.png');
});
test('create edit category change repeated events suppress redundant writes', async () => {
  const m = memory(); await m.add('one'); assert.equal(m.store.metrics.writes, 1);
  await m.backend.synchronize('one'); assert.equal(m.store.metrics.writes, 1);
  m.store.sourcesMap.set('one', doc({ name: 'Padaria Nova', category: 'Onde comer?' }));
  await m.backend.synchronize('one');
  assert.equal(m.store.indexMap.get('one').group, 'commerce');
  assert.ok(!m.store.indexMap.get('one').prefixes.includes('eletrica'));
  assert.equal(m.store.metrics.writes, 2);
});
test('unpublish deactivate delete expiry invalid state removes projection', async () => {
  const m = memory();
  for (const change of [{ published: false }, { active: false }, { expiresAt: new Stamp(now) },
    { expiresAt: null }, { active: 'true' }, { published: 'true' }]) {
    await m.add('one'); m.store.sourcesMap.set('one', doc(change));
    await m.backend.synchronize('one'); assert.equal(m.store.indexMap.size, 0);
  }
  await m.add('one'); m.store.sourcesMap.delete('one');
  await m.backend.synchronize('one'); await m.backend.synchronize('one');
  assert.equal(m.store.indexMap.size, 0);
});
test('concurrent repeated and late events always converge to current state', async () => {
  const m = memory(); await m.add('one');
  m.store.sourcesMap.set('one', doc({ name: 'Último nome' }));
  await Promise.all([m.backend.synchronize('one'), m.backend.synchronize('one'), m.backend.synchronize('one')]);
  assert.equal(m.store.indexMap.get('one').title, 'Último nome');
  assert.equal(m.store.metrics.writes, 2);
  m.store.sourcesMap.delete('one'); await m.backend.synchronize('one'); // old event after delete
  assert.equal(m.store.indexMap.size, 0);
});
test('accents prefixes multiple words filters and deterministic cursor identity', async () => {
  const m = memory(); await m.add('a'); await m.add('b', doc({ category: 'Tecnologia' }));
  const all = await m.backend.search(request({ query: 'ELÉTRICA vie' })); assert.equal(all.results.length, 2);
  assert.equal((await m.backend.search(request({ filter: 'services' }))).results[0].id, 'a');
  assert.equal((await m.backend.search(request({ filter: 'commerce' }))).results[0].id, 'b');
  assert.equal(core.parseRequest({ query: 'vieira silvaa' }).anchor, core.parseRequest({ query: 'silvaa vieira' }).anchor);
});
test('stale index cannot leak unpublished inactive expired deleted or changed record', async () => {
  const m = memory();
  for (const change of [{ published: false }, { active: false }, { expiresAt: new Stamp(now) },
    { name: 'Outro nome' }, { category: 'Tecnologia' }]) {
    await m.add('a'); m.store.sourcesMap.set('a', doc(change));
    assert.equal((await m.backend.search(request({ filter: 'services' }))).results.length, 0);
  }
  await m.add('a'); m.store.sourcesMap.delete('a');
  assert.equal((await m.backend.search(request())).results.length, 0);
});
test('publication expiry is checked at request time even without a source write', async () => {
  const m = memory(); await m.add('a', doc({ expiresAt: new Stamp(now + 1000) }));
  const later = core.createSearchBackend({ store: m.store, isTimestamp: options.isTimestamp, now: () => now + 2000 });
  assert.equal((await later.search(request())).results.length, 0);
  await later.synchronize('a'); assert.equal(m.store.indexMap.size, 0);
});
test('pagination preserves IDs with bounded remaining-slot batches', async () => {
  const m = memory(); for (const id of ['a', 'b', 'c']) await m.add(id);
  const first = await m.backend.search(request({ limit: 2 }));
  const second = await m.backend.search(request({ limit: 2, cursor: first.nextCursor }));
  assert.deepEqual([...first.results, ...second.results].map((result) => result.id), ['a', 'b', 'c']);
  assert.equal(second.nextCursor, null);
  assert.equal(m.store.metrics.indexReads, 3); assert.equal(m.store.metrics.sourceReads, 3);
});
test('typical five-result query uses five origins, not forty', async () => {
  const m = memory(); for (let n = 0; n < 20; n++) await m.add(`id${n}`);
  await m.backend.search(request({ limit: 5 }));
  assert.equal(m.store.metrics.sourceReads, 5); assert.equal(m.store.metrics.indexReads, 5);
});
test('additional indexed words reject candidates before paid source revalidation', async () => {
  const m = memory(); for (let n = 0; n < 40; n++) await m.add(`id${n}`, doc({ name: 'Eletricista Alpha' }));
  await m.backend.search(request({ query: 'eletricista zzz' }));
  assert.equal(m.store.metrics.indexReads, 40); assert.equal(m.store.metrics.sourceReads, 0);
});
test('worst case capped at forty origins and empty page can continue', async () => {
  const m = memory(); for (let n = 0; n < 45; n++) { await m.add(`id${String(n).padStart(2, '0')}`); }
  for (const source of m.store.sourcesMap.values()) source.published = false;
  const result = await m.backend.search(request());
  assert.equal(m.store.metrics.indexReads, 40); assert.equal(m.store.metrics.sourceReads, 40);
  assert.equal(result.results.length, 0); assert.ok(result.nextCursor);
  const next = await m.backend.search(request({ cursor: result.nextCursor }));
  assert.equal(next.nextCursor, null); assert.equal(m.store.metrics.sourceReads, 45);
});
test('no auth and missing App Check rejected before storage', async () => {
  const m = memory();
  for (const rejected of [{ ...request(), auth: null }, { ...request(), app: null }]) {
    await assert.rejects(m.backend.search(rejected), core.SearchError);
  }
  assert.equal(m.store.metrics.admissions, 0); assert.equal(m.store.metrics.indexReads, 0);
});
test('anonymous Auth can search public records with App Check', async () => {
  const m = memory(); await m.add('visitor-business');
  const r = await m.backend.search({ ...request(), auth: {
    uid: 'visitor', token: { firebase: { sign_in_provider: 'anonymous' } },
  } });
  assert.equal(r.results[0].id, 'visitor-business');
});
test('query limits arbitrary collections and malformed cursors are rejected', async () => {
  const m = memory();
  for (const extra of [{ query: '' }, { query: 'a' }, { query: 'a'.repeat(81) }, { query: 'aa bb cc dd ee' },
    { limit: 21 }, { limit: 0 }, { limit: 1.5 }, { filter: 'users' }, { collection: 'users' },
    { cursor: { queryKey: 'all:eletrica', lastIndexId: 'establishments__../bad' } }]) {
    await assert.rejects(m.backend.search(request(extra)), (error) => error.code === 'invalid-argument');
  }
  assert.equal(m.store.metrics.admissions, 0);
});
test('real adapter rate transaction throttles duplicate queries before index reads', async () => {
  const state = new Map(); let reads = 0; let writes = 0;
  const db = { collection: (name) => ({ doc: (id) => ({ key: `${name}/${id}` }) }),
    runTransaction: (body) => body({ get: async (ref) => { reads++; return { data: () => state.get(ref.key) }; },
      set: (ref, data) => { writes++; state.set(ref.key, data); } }) };
  const store = createFirestoreStore(db, { Timestamp: { fromMillis: (ms) => new Stamp(ms) } });
  await store.admit('user', now);
  await assert.rejects(store.admit('user', now + 100), (error) => error.code === 'resource-exhausted');
  for (let n = 1; n < 30; n++) await store.admit('user', now + n * 400);
  await assert.rejects(store.admit('user', now + 20000), (error) => error.code === 'resource-exhausted');
  assert.equal(writes, 30); assert.equal(reads, 32);
  assert.ok(![...state.keys()][0].endsWith('/user'));
});
test('production gate rejects real projects nonloopback host and absent emulator', () => {
  const demo = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-search', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' };
  assert.equal(core.localOnly(demo), true);
  assert.equal(core.localOnly({ ...demo, GCLOUD_PROJECT: 'tudo-aqui-macacu' }), false);
  assert.equal(core.localOnly({ ...demo, FIRESTORE_EMULATOR_HOST: 'remote:8080' }), false);
  assert.equal(core.localOnly({}), false);
});

test('Firestore adapter uses array index paginated projection and batched point reads', async () => {
  const calls = [];
  const chain = {};
  for (const method of ['where', 'orderBy', 'startAfter', 'limit', 'select']) {
    chain[method] = (...args) => { calls.push([method, ...args]); return chain; };
  }
  chain.get = async () => ({ docs: [{ id: 'establishments__one', data: () => ({ id: 'one' }) }] });
  const db = { collection: (name) => {
    calls.push(['collection', name]); return name === core.INDEX ? chain : { doc: (id) => ({ id }) };
  }, getAll: async (...refs) => refs.map((ref) => ({ data: () => ({ name: ref.id }) })) };
  const store = createFirestoreStore(db, { FieldPath: { documentId: () => '__name__' } });
  await store.candidates({ anchor: 'ele', filter: 'services', after: 'establishments__a', count: 5 });
  assert.deepEqual(calls.slice(0, 6), [['collection', core.INDEX], ['where', 'prefixes', 'array-contains', 'ele'],
    ['where', 'group', '==', 'services'], ['orderBy', '__name__'], ['startAfter', 'establishments__a'], ['limit', 5]]);
  assert.equal(calls[6][0], 'select');
  assert.deepEqual(await store.sources(['one', 'two']), [{ name: 'one' }, { name: 'two' }]);
});

test('transaction retry rebuilds from latest source and replaces whole projection', async () => {
  let version = doc(); let writes = 0; let pending;
  const db = { collection: (name) => ({ doc: (id) => ({ name, id }) }),
    async runTransaction(body) {
      const tx = { get: async (ref) => ({ data: () => ref.name === core.SOURCE ? version : null }),
        set: (_ref, data) => { pending = data; }, delete: () => {} };
      await body(tx); // pretend SDK detects source conflict and discards first writes
      version = doc({ name: 'Estado atual' });
      await body(tx); writes++; return undefined;
    } };
  const backend = core.createSearchBackend({ store: createFirestoreStore(db, {
    FieldValue: { serverTimestamp: () => 'SERVER_TIME' } }), isTimestamp: options.isTimestamp, now: () => now });
  await backend.synchronize('one');
  assert.equal(pending.title, 'Estado atual'); assert.equal(writes, 1);
});

test('callable wrapper enforces App Check local gate and sanitized errors', async () => {
  const keys = ['FUNCTIONS_EMULATOR', 'GCLOUD_PROJECT', 'FIRESTORE_EMULATOR_HOST'];
  const saved = keys.map((key) => process.env[key]);
  try {
    process.env.FUNCTIONS_EMULATOR = 'true'; process.env.GCLOUD_PROJECT = 'demo-search';
    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
    const firestore = () => ({ collection: () => ({ doc: () => ({}) }),
      runTransaction: async () => { throw new Error('private SDK credential details'); } });
    firestore.Timestamp = Stamp;
    class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
    const capture = (settings, handler) => ({ settings, handler });
    const { registerLocalSearch } = require('../business_search_functions');
    const handlers = registerLocalSearch({ admin: { firestore }, onCall: capture, HttpsError, onDocumentWritten: capture });
    assert.equal(handlers.searchBusinesses.settings.enforceAppCheck, true);
    assert.equal(handlers.syncBusinessSearchIndex.settings.document, 'establishments/{id}');
    await assert.rejects(handlers.searchBusinesses.handler({ ...request(), auth: null }), (error) => error.code === 'unauthenticated');
    await assert.rejects(handlers.searchBusinesses.handler(request()), (error) => error.code === 'unavailable' && !error.message.includes('credential'));
    process.env.GCLOUD_PROJECT = 'tudo-aqui-macacu';
    await assert.rejects(handlers.searchBusinesses.handler(request()), (error) => error.code === 'failed-precondition');
    assert.throws(() => registerLocalSearch({}), /demo local/);
  } finally {
    keys.forEach((key, n) => { if (saved[n] === undefined) delete process.env[key]; else process.env[key] = saved[n]; });
  }
});

test('production entrypoint preserves upload/push exports and adds no search export', () => {
  const fs = require('node:fs'); const vm = require('node:vm'); const path = require('node:path');
  const exported = {};
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return { initializeApp() {} };
    if (name === 'firebase-admin/firestore') return require('firebase-admin/firestore');
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => handler, HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({}) };
    if (name === './business_search') return { localOnly: () => core.localOnly({}) };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => require('../secure_backend_environment').secureBackendAllowed({}) };
    if (name === './home_image_upload') return require('../home_image_upload');
    if (name === './notification_delivery') return require('../notification_delivery');
    if (name === './admin_authorization') return require('../admin_authorization');
    throw new Error(`Unexpected production import: ${name}`);
  };
  vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8'), { require: fakeRequire, exports: exported });
  assert.deepEqual(Object.keys(exported).sort(), ['deliverPushNotification', 'uploadHomeImage']);
});
