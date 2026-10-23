'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { Timestamp: FirestoreTimestamp } = require('firebase-admin/firestore');
const { registerAdminJobManagement } = require('../admin_job_management');

const ALLOWED = new Set(['jobs', 'job_private', 'admin_authorizations']);
const PRIVATE = ['contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo'];
const PUBLIC = ['title', 'description', 'imageUrl', 'artwork', 'galleryUrls', 'category', 'location', 'address', 'published', 'active', 'expiresAt'];
const auth = { uid: 'admin-1', token: { admin: true, adminVersion: 'v1' } };
const app = { appId: 'test-app' };
const rawRequest = { headers: { authorization: 'Bearer fixture-token' }, get: name => name.toLowerCase() === 'authorization' ? 'Bearer fixture-token' : undefined };
class Timestamp {
  constructor(seconds, nanoseconds) { this.seconds = seconds; this.nanoseconds = nanoseconds; }
  toMillis() { return this.seconds * 1000 + Math.floor(this.nanoseconds / 1000000); }
  static fromDate(date) {
    const seconds = Math.floor(date.getTime() / 1000);
    return new Timestamp(seconds, (date.getTime() - seconds * 1000) * 1000000);
  }
}
const millis = value => Timestamp.fromDate(new Date(value));
function compareTimestamps(a, b) {
  return a.seconds === b.seconds ? Math.sign(a.nanoseconds - b.nanoseconds) : Math.sign(a.seconds - b.seconds);
}
function clone(value) {
  if (Array.isArray(value)) return value.map(clone);
  if (value && Object.getPrototypeOf(value) === Object.prototype) return Object.fromEntries(Object.entries(value).map(([key, child]) => [key, clone(child)]));
  return value;
}
const toMillis = value => typeof value === 'number' ? value : value?.toMillis?.() ?? value;

function makeHarness(seed = {}, authorizeAdmin = async (_auth, { rawToken }) => rawToken === 'fixture-token',
  { omitNamespaceTimestamp = false } = {}) {
  const data = new Map(Object.entries(seed).map(([name, docs]) => [name, new Map(Object.entries(docs).map(([id, value]) => [id, clone(value)]))]));
  const calls = { collections: [], queries: [], transactions: 0, transactionReads: [], writes: [] };
  let transactionFailure = null;
  function bucket(name) {
    assert.ok(ALLOWED.has(name), `unexpected collection access: ${name}`);
    calls.collections.push(name);
    if (!data.has(name)) data.set(name, new Map());
    return data.get(name);
  }
  const snap = (id, value) => ({ id, exists: value !== undefined, data: () => clone(value) });
  function ref(name, id) {
    return Object.assign({ id, collectionName: name,
      get: async () => snap(id, bucket(name).get(id)),
      set: async value => { calls.writes.push({ type: 'set', collection: name, id }); bucket(name).set(id, clone(value)); },
      update: async value => { calls.writes.push({ type: 'update', collection: name, id }); bucket(name).set(id, { ...bucket(name).get(id), ...clone(value) }); },
      delete: async () => { calls.writes.push({ type: 'delete', collection: name, id }); bucket(name).delete(id); },
    }, { collectionName: name });
  }
  function query(name, clauses) {
    return {
      orderBy: (field, direction) => query(name, [...clauses, { type: 'orderBy', field, direction }]),
      startAfter: (...values) => query(name, [...clauses, { type: 'startAfter', values }]),
      limit: value => query(name, [...clauses, { type: 'limit', value }]),
      async get() {
        calls.queries.push({ collection: name, clauses });
        let rows = [...bucket(name)].map(([id, value]) => ({ id, value }));
        if (clauses.some(c => c.type === 'orderBy' && c.field === 'updatedAt')) rows = rows.filter(row => Object.hasOwn(row.value, 'updatedAt') && row.value.updatedAt !== undefined);
        for (const c of clauses.filter(x => x.type === 'orderBy').reverse()) rows.sort((a, b) => {
          const av = c.field === '__name__' ? a.id : a.value[c.field];
          const bv = c.field === '__name__' ? b.id : b.value[c.field];
          const cmp = c.field !== '__name__' ? compareTimestamps(av, bv) : av < bv ? -1 : av > bv ? 1 : 0;
          return c.direction === 'desc' ? -cmp : cmp;
        });
        const after = clauses.find(c => c.type === 'startAfter');
        if (after) {
          const [t, id] = after.values;
          assert.ok(clauses.filter(c => c.type === 'orderBy').length >= 2, 'cursor query keeps both stable order clauses');
          rows = rows.filter(row => { const cmp = compareTimestamps(row.value.updatedAt, t); return cmp < 0 || (cmp === 0 && row.id < id); });
        }
        const limit = clauses.find(c => c.type === 'limit')?.value;
        if (limit) rows = rows.slice(0, limit);
        return { docs: rows.map(row => snap(row.id, row.value)), size: rows.length };
      },
    };
  }
  const db = {
    collection: name => ({ doc: id => ref(name, id), orderBy: (field, direction) => query(name, [{ type: 'orderBy', field, direction }]) }),
    async runTransaction(callback) {
      calls.transactions++;
      if (transactionFailure) throw transactionFailure;
      const staged = [];
      const coll = r => bucket(r.collectionName);
      const tx = {
        get: async r => { calls.transactionReads.push({ collection: r.collectionName, id: r.id }); return snap(r.id, coll(r).get(r.id)); },
        create: (r, value) => staged.push(() => { calls.writes.push({ type: 'create', collection: r.collectionName, id: r.id }); coll(r).set(r.id, clone(value)); }),
        set: (r, value) => staged.push(() => { calls.writes.push({ type: 'set', collection: r.collectionName, id: r.id }); coll(r).set(r.id, clone(value)); }),
        update: (r, value) => staged.push(() => { calls.writes.push({ type: 'update', collection: r.collectionName, id: r.id }); coll(r).set(r.id, { ...coll(r).get(r.id), ...clone(value) }); }),
        delete: r => staged.push(() => { calls.writes.push({ type: 'delete', collection: r.collectionName, id: r.id }); coll(r).delete(r.id); }),
      };
      const result = await callback(tx);
      staged.forEach(write => write());
      return result;
    },
  };
  const HttpsError = class extends Error { constructor(code, message) { super(message); this.code = code; } };
  const firestore = Object.assign(() => db, omitNamespaceTimestamp ? {} : { Timestamp });
  const admin = { firestore, auth: () => ({ verifyIdToken: async () => ({ uid: auth.uid }) }) };
  const handler = registerAdminJobManagement({ admin, onCall: (_opts, fn) => fn, HttpsError, authorizeAdmin, now: () => millis(1000) }).manageAdminJob;
  return { handler, db, data, calls, failTransaction(error = new Error('transaction failed')) { transactionFailure = error; } };
}
const request = (data, overrides = {}) => ({ data, auth, app, rawRequest, ...overrides });
const publicData = (overrides = {}) => ({ title: 'Engineer', description: 'Role description', published: true, active: true, ...overrides });
const privateData = (overrides = {}) => ({ contact: 'Hiring team', phone: '123', ...overrides });
const seedJob = (id, pub = publicData(), priv = privateData()) => ({ jobs: { [id]: { ...pub, updatedAt: millis(10) } }, job_private: priv === null ? {} : { [id]: priv } });

test('rejects missing Auth/App Check before job access', async () => {
  for (const overrides of [{ auth: null }, { app: null }]) { const h = makeHarness(); await assert.rejects(h.handler(request({ operation: 'list' }, overrides))); assert.equal(h.calls.collections.filter(x => x === 'jobs' || x === 'job_private').length, 0); }
});
test('central authorization denial and unavailability precede job access', async () => {
  for (const deny of [async () => false, async () => { throw Error('central unavailable'); }]) {
    let calls = 0; const h = makeHarness({}, async (currentAuth, options) => { calls++; assert.equal(currentAuth, auth); assert.equal(options.db, h.db); assert.equal(options.rawToken, 'fixture-token'); await options.firebaseAuth.verifyIdToken(options.rawToken, true); return deny(); });
    await assert.rejects(h.handler(request({ operation: 'list' }))); assert.equal(calls, 1); assert.equal(h.calls.queries.length, 0); assert.equal(h.calls.collections.filter(x => x === 'jobs' || x === 'job_private').length, 0);
  }
});
test('revoked token verification denies before job access', async () => {
  const h = makeHarness({}, async (_a, options) => { await options.firebaseAuth.verifyIdToken(options.rawToken, true); return true; });
  h.handler = registerAdminJobManagement({ admin: { firestore: () => h.db, auth: () => ({ verifyIdToken: async (_token, revoked) => { assert.equal(revoked, true); throw Error('revoked'); } }) }, onCall: (_o, fn) => fn, HttpsError: class extends Error {}, authorizeAdmin: async (_a, options) => { await options.firebaseAuth.verifyIdToken(options.rawToken, true); } }).manageAdminJob;
  await assert.rejects(h.handler(request({ operation: 'list' }))); assert.equal(h.calls.queries.length, 0); assert.equal(h.calls.collections.filter(x => x === 'jobs' || x === 'job_private').length, 0);
});
test('rejects unsupported operations, extra envelope keys, and malformed body shapes', async () => {
  for (const body of [{ operation: 'publish' }, { operation: 'list', extra: true }, { operation: 1 }, null, []]) { const h = makeHarness(); await assert.rejects(h.handler(request(body))); assert.equal(h.calls.queries.length, 0); }
});
test('rejects malformed IDs, payload types, page limits, and malformed or decodable-invalid cursors', async () => {
  const invalid = [
    { operation: 'get', jobId: '' }, { operation: 'get', jobId: 'a/b' }, { operation: 'get', jobId: 'x'.repeat(300) },
    { operation: 'create', jobId: 'j', publicData: [], privateData: {} }, { operation: 'update', jobId: 'j', publicData: {}, privateData: 'bad' },
    { operation: 'list', pageSize: 0 }, { operation: 'list', pageSize: 41 }, { operation: 'list', pageSize: 1.5 }, { operation: 'list', cursor: 'not base64url!' },
    ...[
      { updatedAtMillis: '10', id: 'job-1' }, { updatedAtMillis: 10, id: 'job-1', extra: true },
      { updatedAtMillis: 10, id: 'a/b' }, { updatedAtMillis: -1, id: 'job-1' },
    ].map(value => ({ operation: 'list', cursor: Buffer.from(JSON.stringify(value)).toString('base64url') })),
    { operation: 'list', cursor: Buffer.from('{').toString('base64url') },
  ];
  for (const body of invalid) { const h = makeHarness(); await assert.rejects(h.handler(request(body))); assert.equal(h.calls.queries.length, 0); }
});
test('rejects public/private fields outside allowlists and server metadata', async () => {
  for (const body of [
    { operation: 'create', jobId: 'j', publicData: { privateData: { phone: 'x' } }, privateData: {} },
    { operation: 'create', jobId: 'j', publicData: { unknown: true }, privateData: {} },
    { operation: 'create', jobId: 'j', publicData: {}, privateData: { unknown: 'x' } },
    { operation: 'update', jobId: 'j', publicData: { updatedAt: 'client' }, privateData: {} },
    { operation: 'update', jobId: 'j', publicData: {}, privateData: { schemaVersion: 1 } },
    { operation: 'update', jobId: 'j', publicData: {}, privateData: { updatedAt: 'client' } },
  ]) { const h = makeHarness(); await assert.rejects(h.handler(request(body))); assert.equal(h.calls.transactions, 0); }
});
test('validates public/private field types, limits, URLs, expiry, and UTF-8 aggregate private bytes', async () => {
  const bad = [
    { publicData: { title: 42 }, privateData: {} }, { publicData: { title: 't'.repeat(141) }, privateData: {} },
    { publicData: { description: 'd'.repeat(3001) }, privateData: {} }, { publicData: { imageUrl: 'http://example.com/x' }, privateData: {} },
    { publicData: { imageUrl: `https://${'x'.repeat(2041)}.com` }, privateData: {} }, { publicData: { artwork: 1.5 }, privateData: {} },
    { publicData: { galleryUrls: ['https://example.com/x', 'http://example.com/no'] }, privateData: {} },
    { publicData: { galleryUrls: Array(21).fill('https://example.com/x') }, privateData: {} }, { publicData: { category: 'c'.repeat(121) }, privateData: {} },
    { publicData: { location: 'l'.repeat(241) }, privateData: {} }, { publicData: { address: 'a'.repeat(241) }, privateData: {} },
    { publicData: { published: 'yes' }, privateData: {} }, { publicData: { active: 1 }, privateData: {} },
    { publicData: { expiresAt: 'not-a-date' }, privateData: {} }, { publicData: { expiresAt: 1000 }, privateData: {} },
    { publicData: {}, privateData: { contact: 3 } }, { publicData: {}, privateData: { contact: 'c'.repeat(321) } },
    { publicData: {}, privateData: { phone: 'p'.repeat(65) } }, { publicData: {}, privateData: { whatsapp: 'w'.repeat(2049) } },
    { publicData: {}, privateData: { link: 'l'.repeat(2049) } }, { publicData: {}, privateData: { instagram: 'i'.repeat(2049) } },
    { publicData: {}, privateData: { maps: 'm'.repeat(2049) } }, { publicData: {}, privateData: { mapsUrl: 'm'.repeat(2049) } },
    { publicData: {}, privateData: { additionalInfo: 'a'.repeat(3001) } },
    { publicData: {}, privateData: Object.fromEntries(PRIVATE.map((field, i) => [field, '\u754c'.repeat([320,64,2048,2048,2048,2048,2048,3000][i])])) },
  ];
  for (const payload of bad) { const h = makeHarness(); await assert.rejects(h.handler(request({ operation: 'create', jobId: 'j', ...payload }))); assert.equal(h.calls.transactions, 0); }
  const h = makeHarness();
  await h.handler(request({ operation: 'create', jobId: 'valid', publicData: { title: 't'.repeat(140), description: 'd'.repeat(3000), imageUrl: 'https://example.com/x', artwork: 0, galleryUrls: ['https://example.com/x'], category: 'c'.repeat(120), location: 'l'.repeat(240), address: 'a'.repeat(240), published: false, active: true, expiresAt: '2030-01-02T03:04:05.000Z' }, privateData: Object.fromEntries(PRIVATE.map(key => [key, 'ok'])) }));
});

test('list defaults to 30, caps at 40, orders stably by updatedAt desc then ID desc and excludes missing updatedAt', async () => {
  const jobs = {}; for (let i = 0; i < 45; i++) jobs[`job-${String(i).padStart(2, '0')}`] = { title: `Job ${i}`, published: i % 2 === 0, active: true, updatedAt: millis(i) };
  const h = makeHarness({ jobs, job_private: { secret: privateData() } });
  const result = await h.handler(request({ operation: 'list', pageSize: 40 })); assert.equal(result.items.length, 40); assert.equal(result.items[0].id, 'job-44');
  assert.deepEqual(result.items[0].summary, { title: 'Job 44', published: true, active: true }); assert.equal(JSON.stringify(result).includes('Hiring team'), false);
  assert.deepEqual(h.calls.queries[0].clauses.filter(x => x.type === 'orderBy'), [{ type: 'orderBy', field: 'updatedAt', direction: 'desc' }, { type: 'orderBy', field: '__name__', direction: 'desc' }]);
  assert.equal(h.calls.queries[0].clauses.find(x => x.type === 'limit').value, 41);
  const d = makeHarness({ jobs: { only: { title: 'Only', updatedAt: millis(1) }, missingTimestamp: { title: 'Excluded' } } });
  const defaultPage = await d.handler(request({ operation: 'list' })); assert.deepEqual(defaultPage.items.map(x => x.id), ['only']); assert.equal(defaultPage.nextCursor, null); assert.equal(d.calls.queries[0].clauses.find(x => x.type === 'limit').value, 31);
});
test('list cursor handles tied timestamps without duplicates and ends at final page', async () => {
  const jobs = Object.fromEntries(Array.from({ length: 5 }, (_, i) => [`job-${i}`, { title: `Job ${i}`, published: true, active: true, updatedAt: millis(i < 3 ? 100 : 90) }]));
  const h = makeHarness({ jobs }); const a = await h.handler(request({ operation: 'list', pageSize: 2 })); const b = await h.handler(request({ operation: 'list', pageSize: 2, cursor: a.nextCursor })); const c = await h.handler(request({ operation: 'list', pageSize: 2, cursor: b.nextCursor }));
  const ids = [...a.items, ...b.items, ...c.items].map(x => x.id); assert.equal(new Set(ids).size, ids.length); assert.equal(ids.length, 5); assert.equal(c.nextCursor, null);
  assert.deepEqual(ids, ['job-2', 'job-1', 'job-0', 'job-4', 'job-3']);
});

test('pageSize 1 preserves exact nanoseconds within the same millisecond without skips or duplicates', async () => {
  const seconds = 1800000000;
  const jobs = {
    a: { title: 'Newest', updatedAt: new Timestamp(seconds, 123000003) },
    z: { title: 'Middle z', updatedAt: new Timestamp(seconds, 123000002) },
    b: { title: 'Middle b', updatedAt: new Timestamp(seconds, 123000002) },
    y: { title: 'Oldest', updatedAt: new Timestamp(seconds, 123000001) },
  };
  assert.equal(new Set(Object.values(jobs).map(job => Math.floor(job.updatedAt.toMillis()))).size, 1);
  const h = makeHarness({ jobs }), ids = [];
  let cursor;
  for (let i = 0; i < 4; i++) {
    const page = await h.handler(request({ operation: 'list', pageSize: 1, ...(cursor ? { cursor } : {}) }));
    assert.equal(page.items.length, 1);
    const id = page.items[0].id;
    ids.push(id);
    cursor = page.nextCursor;
    if (i < 3) assert.deepEqual(JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')),
      { updatedAt: { seconds, nanoseconds: jobs[id].updatedAt.nanoseconds }, id });
  }
  assert.deepEqual(ids, ['a', 'z', 'b', 'y']);
  assert.equal(new Set(ids).size, 4);
  assert.equal(cursor, null);
  for (const call of h.calls.queries.slice(1)) {
    const after = call.clauses.find(clause => clause.type === 'startAfter');
    assert.ok(after.values[0] instanceof FirestoreTimestamp);
    assert.equal(after.values[0].nanoseconds, jobs[after.values[1]].updatedAt.nanoseconds);
  }
});

test('rejects malformed exact timestamp cursors before querying jobs', async () => {
  const bad = [null, [], { seconds: 1 }, { nanoseconds: 1 },
    { seconds: '1', nanoseconds: 0 }, { seconds: 1.5, nanoseconds: 0 },
    { seconds: -62135596801, nanoseconds: 0 }, { seconds: 253402300800, nanoseconds: 0 },
    { seconds: 1, nanoseconds: -1 }, { seconds: 1, nanoseconds: 1000000000 },
    { seconds: 1, nanoseconds: 0.5 }, { seconds: 1, nanoseconds: '0' },
    { seconds: 1, nanoseconds: null }, { seconds: 1, nanoseconds: 0, extra: true }];
  for (const updatedAt of bad) {
    const h = makeHarness();
    const cursor = Buffer.from(JSON.stringify({ updatedAt, id: 'job-1' })).toString('base64url');
    await assert.rejects(h.handler(request({ operation: 'list', cursor })), error => error.code === 'invalid-argument');
    assert.equal(h.calls.queries.length, 0);
  }
});

test('empty imageUrl creates an absent image and clears an existing image while nonempty URLs require HTTPS', async () => {
  const h = makeHarness();
  await h.handler(request({ operation: 'create', jobId: 'empty-image', publicData: { imageUrl: '' }, privateData: {} }));
  assert.equal(h.data.get('jobs').get('empty-image').imageUrl, '');
  const existing = makeHarness(seedJob('image', publicData({ imageUrl: 'https://example.com/image.png' })));
  await existing.handler(request({ operation: 'update', jobId: 'image', publicData: { imageUrl: '' }, privateData: {} }));
  assert.equal(existing.data.get('jobs').get('image').imageUrl, '');
  for (const imageUrl of ['http://example.com/x', 'javascript:alert(1)', ' ', null, 1]) {
    const invalid = makeHarness();
    await assert.rejects(invalid.handler(request({ operation: 'create', jobId: 'bad', publicData: { imageUrl }, privateData: {} })), error => error.code === 'invalid-argument');
    assert.equal(invalid.calls.transactions, 0);
  }
});
test('get returns only editable public fields and exact private fields from paired transactional reads', async () => {
  const pub = { ...publicData(), updatedAt: millis(10), privateContact: 'hidden', createdBy: 'internal' }; const priv = Object.fromEntries(PRIVATE.map((x, i) => [x, `value-${i}`]));
  const h = makeHarness(seedJob('job-1', pub, priv)); const result = await h.handler(request({ operation: 'get', jobId: 'job-1' }));
  assert.equal(result.status, 'available'); assert.equal(result.jobId, 'job-1'); assert.deepEqual(Object.keys(result.privateData).sort(), [...PRIVATE].sort()); assert.deepEqual(Object.keys(result.publicData).sort(), [...PUBLIC].sort());
  PRIVATE.forEach((field, i) => assert.equal(result.privateData[field], `value-${i}`)); assert.equal(result.publicData.updatedAt, undefined); assert.equal(result.publicData.privateContact, undefined);
  assert.equal(h.calls.transactions, 1); assert.deepEqual(h.calls.transactionReads.map(x => x.collection).sort(), ['job_private', 'jobs']);
});
test('get reports missing public and legacy private records with controlled errors', async () => {
  await assert.rejects(makeHarness().handler(request({ operation: 'get', jobId: 'absent' })), e => e.code === 'not-found');
  await assert.rejects(makeHarness(seedJob('legacy', publicData(), null)).handler(request({ operation: 'get', jobId: 'legacy' })), e => e.code === 'failed-precondition');
});
test('create creates a pair, writes server metadata and converted expiry, and rejects either one-sided collision', async () => {
  const h = makeHarness(); const result = await h.handler(request({ operation: 'create', jobId: 'job-new', publicData: publicData(), privateData: privateData() }));
  assert.deepEqual(result, { status: 'created', jobId: 'job-new' }); const pub = h.data.get('jobs').get('job-new'), priv = h.data.get('job_private').get('job-new');
  assert.equal(toMillis(pub.updatedAt), 1000); assert.equal(toMillis(priv.updatedAt), 1000); assert.ok(Number.isInteger(priv.schemaVersion) && priv.schemaVersion > 0);
  const expiry = makeHarness(); await expiry.handler(request({ operation: 'create', jobId: 'exp', publicData: { expiresAt: '2030-01-02T03:04:05.000Z' }, privateData: {} })); assert.equal(toMillis(expiry.data.get('jobs').get('exp').expiresAt), Date.parse('2030-01-02T03:04:05.000Z'));
  for (const seed of [{ jobs: { 'job-new': { title: 'Public only' } } }, { job_private: { 'job-new': privateData({ contact: 'Private only' }) } }]) {
    const collision = makeHarness(seed); await assert.rejects(collision.handler(request({ operation: 'create', jobId: 'job-new', publicData: publicData({ title: 'Overwrite' }), privateData: privateData() })));
    if (seed.jobs) assert.equal(collision.data.get('jobs').get('job-new').title, 'Public only');
    if (seed.job_private) assert.equal(collision.data.get('job_private').get('job-new').contact, 'Private only');
    assert.equal(collision.data.get('jobs').has('job-new'), Boolean(seed.jobs)); assert.equal(collision.data.get('job_private').has('job-new'), Boolean(seed.job_private));
  }
});
test('timestamps use the supported Admin Firestore export, not the namespace alias', async () => {
  const h = makeHarness({}, undefined, { omitNamespaceTimestamp: true });
  await h.handler(request({ operation: 'create', jobId: 'supported-timestamp',
    publicData: {}, privateData: {} }));
  assert.equal(h.data.get('jobs').get('supported-timestamp').updatedAt.toMillis(), 1000);
  assert.equal(h.data.get('job_private').get('supported-timestamp').updatedAt.toMillis(), 1000);
});
test('update requires both records, preserves omitted private fields, and clears explicit blanks', async () => {
  const h = makeHarness(seedJob('job-1', publicData(), { contact: 'Original', phone: '123' })); await h.handler(request({ operation: 'update', jobId: 'job-1', publicData: { title: 'Updated' }, privateData: { contact: '' } }));
  assert.equal(h.data.get('jobs').get('job-1').title, 'Updated'); assert.equal(h.data.get('job_private').get('job-1').contact, undefined); assert.equal(h.data.get('job_private').get('job-1').phone, '123');
  await assert.rejects(makeHarness().handler(request({ operation: 'update', jobId: 'missing', publicData: {}, privateData: {} })));
  await assert.rejects(makeHarness(seedJob('legacy', publicData(), null)).handler(request({ operation: 'update', jobId: 'legacy', publicData: {}, privateData: {} })), e => e.code === 'failed-precondition');
});
test('delete removes paired records and explicit legacy, but missing public record preserves orphan private', async () => {
  const h = makeHarness(seedJob('job-1')); assert.deepEqual(await h.handler(request({ operation: 'delete', jobId: 'job-1' })), { status: 'deleted', jobId: 'job-1' }); assert.equal(h.data.get('jobs').has('job-1'), false); assert.equal(h.data.get('job_private').has('job-1'), false);
  const legacy = makeHarness(seedJob('legacy', publicData(), null)); await legacy.handler(request({ operation: 'delete', jobId: 'legacy' }));
  const orphan = makeHarness({ job_private: { orphan: privateData() } }); await assert.rejects(orphan.handler(request({ operation: 'delete', jobId: 'orphan' })), e => e.code === 'not-found'); assert.equal(orphan.data.get('job_private').has('orphan'), true);
});
test('transaction failures never report success or stage partial writes', async () => {
  const original = console.error;
  console.error = () => {};
  try {
    for (const operation of ['create', 'update', 'delete']) { const h = makeHarness(operation === 'create' ? {} : seedJob('job-1')); h.failTransaction(); const body = operation === 'delete' ? { operation, jobId: 'job-1' } : { operation, jobId: 'job-1', publicData: publicData({ title: 'Changed' }), privateData: privateData({ contact: 'Changed' }) }; await assert.rejects(h.handler(request(body))); assert.equal(h.calls.writes.length, 0); }
  } finally { console.error = original; }
});
test('unexpected failures log only sanitized operation metadata', async () => {
  const secret = 'private-fixture-must-not-enter-logs';
  const h = makeHarness(); h.failTransaction(Object.assign(new Error(secret), { code: 13 }));
  const original = console.error, logged = [];
  console.error = (...args) => logged.push(args);
  try {
    await assert.rejects(h.handler(request({ operation: 'create', jobId: 'job-new',
      publicData: { title: 'Public' }, privateData: { contact: secret } })));
  } finally { console.error = original; }
  assert.equal(logged.length, 1);
  assert.equal(logged[0][0], 'manageAdminJob failed');
  assert.deepEqual({ operation: logged[0][1].operation, errorName: logged[0][1].errorName,
    errorCode: logged[0][1].errorCode }, { operation: 'create', errorName: 'Error', errorCode: 13 });
  assert.match(logged[0][1].errorOrigin, /^[A-Za-z0-9_.$<>@:-]{1,120}$/);
  assert.equal(JSON.stringify(logged).includes(secret), false);
});
test('accesses only jobs, job_private, and admin_authorizations', async () => {
  const h = makeHarness(seedJob('job-1')); await h.handler(request({ operation: 'list' })); await h.handler(request({ operation: 'get', jobId: 'job-1' })); await h.handler(request({ operation: 'update', jobId: 'job-1', publicData: {}, privateData: {} })); await h.handler(request({ operation: 'delete', jobId: 'job-1' })); assert.ok(h.calls.collections.length); assert.ok(h.calls.collections.every(name => ALLOWED.has(name)));
});
