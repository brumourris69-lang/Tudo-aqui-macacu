'use strict';
// Real SDK + real local services. Never run against a non-demo project.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  assert.match(process.env[key] || '', /^127\.0\.0\.1:\d+$/);
}
assert.match(project || '', /^demo-[a-z0-9-]+$/);
assert.equal(process.env.FUNCTIONS_EMULATOR, 'true');
const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { createSearchBackend, buildEntry, INDEX, RATE } = require('../business_search');
const { createFirestoreStore } = require('../business_search_firestore');
const options = { now: Date.now(), isTimestamp: v => v instanceof admin.firestore.Timestamp };
const store = createFirestoreStore(db, admin.firestore);
const backend = createSearchBackend({ store, isTimestamp: options.isTimestamp });
const base = `http://127.0.0.1:5007/${project}/southamerica-east1/searchBusinesses`;
const authBase = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`;
const firestoreBase = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents`;
const run = Date.now().toString();
const passed = [];
async function test(name, body) { await body(); passed.push(name); console.log('PASS', name); }
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(body) {
  const end = Date.now() + 45000;
  do { if (await body()) return; await sleep(250); } while (Date.now() < end);
  throw new Error('Trigger did not converge within 45s');
}
const ref = id => db.collection('establishments').doc(id);
const idx = id => db.collection(INDEX).doc(`establishments__${id}`);
const data = (name, category = 'Comércio') => ({ name, category, published: true,
  description: 'Informação pública', privateNotes: 'DO_NOT_RETURN', ownerEmail: 'private@example.invalid' });
let user;
// The official Functions Emulator decodes tokens without attestation verification.
// This fixture tests transport/context enforcement, NOT production App Check.
const jwt = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url') + '.' +
  Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now()/1000)+3600 })).toString('base64url') + '.';
async function call(input, { token = user?.idToken, app = jwt, reset = true } = {}) {
  if (reset && user) await db.collection(RATE).doc(crypto.createHash('sha256').update(user.localId).digest('hex')).delete();
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (app) headers['X-Firebase-AppCheck'] = app;
  const response = await fetch(base, { method: 'POST', headers, body: JSON.stringify({ data: input }) });
  return { status: response.status, body: await response.json() };
}
async function main() {
  // This suite exclusively owns this local demo database; discard prior fixtures.
  const cleared = await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${project}/databases/(default)/documents`, { method: 'DELETE' });
  assert.equal(cleared.status, 200);
  const response = await fetch(`${authBase}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `search-${run}@example.invalid`, password: 'LocalTest123!', returnSecureToken: true }) });
  assert.equal(response.status, 200); user = await response.json();
  await test('Auth Emulator account/token', async () => {
    assert.equal((await admin.auth().verifyIdToken(user.idToken)).uid, user.localId);
  });
  const id = `integration-${run}`;
  await test('Automatic create trigger + public projection', async () => {
    await ref(id).set(data('Elétrica Vieira', 'Tecnologia'));
    await until(async () => (await idx(id).get()).data()?.title === 'Elétrica Vieira');
    const entry = (await idx(id).get()).data();
    assert.equal(entry.id, id); assert.equal(entry.group, 'commerce');
    assert.equal(entry.privateNotes, undefined); assert.equal(entry.ownerEmail, undefined);
  });
  await test('Callable name/accent/prefix + original ID', async () => {
    for (const query of ['Elétrica Vieira', 'eletrica vieira', 'elet vie']) {
      const result = await call({ query }); assert.equal(result.status, 200);
      assert.equal(result.body.result.results[0].id, id);
      assert.equal(result.body.result.results[0].privateNotes, undefined);
    }
  });
  await test('Automatic name/category update', async () => {
    await ref(id).update({ name: 'Elétrica Renovada', category: 'Profissionais' });
    await until(async () => (await idx(id).get()).data()?.group === 'services');
    assert.equal((await call({ query: 'renovada', filter: 'commerce' })).body.result.results.length, 0);
    assert.equal((await call({ query: 'renovada', filter: 'services' })).body.result.results[0].title, 'Elétrica Renovada');
  });
  for (const [name, changes] of [['Unpublish', { published: false }], ['Deactivate', { active: false }],
    ['Expired', { expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) }]]) {
    await test(`Automatic ${name} removes index`, async () => {
      await ref(id).set({ ...data('Elétrica Renovada', 'Profissionais'), ...changes });
      await until(async () => !(await idx(id).get()).exists);
      assert.equal((await call({ query: 'renovada' })).body.result.results.length, 0);
      await ref(id).set(data('Elétrica Renovada', 'Profissionais'));
      await until(async () => (await idx(id).get()).exists);
    });
  }
  await test('Expired without another write is revalidated', async () => {
    await ref(id).set({ ...data('Temporal Expiração'), expiresAt: admin.firestore.Timestamp.fromMillis(Date.now()+2000) });
    await until(async () => (await idx(id).get()).data()?.title === 'Temporal Expiração');
    await sleep(2200);
    assert.equal((await call({ query: 'temporal' })).body.result.results.length, 0);
  });
  await test('Automatic delete', async () => {
    await ref(id).delete(); await until(async () => !(await idx(id).get()).exists);
  });
  await test('Duplicate/out-of-order handler + concurrent real transactions', async () => {
    await ref(id).set(data('Estado Antigo'));
    await until(async () => (await idx(id).get()).exists);
    await Promise.all([ref(id).update({ name: 'Concorrente Um' }), ref(id).update({ name: 'Concorrente Dois' })]);
    await ref(id).update({ name: 'Estado Final', category: 'Serviços' });
    // Old payload is intentionally ignored: same real handler, real Firestore transaction.
    const { onCall, HttpsError } = require('firebase-functions/v2/https');
    const { onDocumentWritten } = require('firebase-functions/v2/firestore');
    const fn = require('../business_search_functions').registerLocalSearch({ admin, onCall, HttpsError, onDocumentWritten });
    await Promise.all(Array.from({ length: 6 }, () => fn.syncBusinessSearchIndex.run({ params: { id }, data: { after: data('Estado Antigo') } })));
    await until(async () => (await idx(id).get()).data()?.title === 'Estado Final');
    const before = (await idx(id).get()).updateTime;
    await fn.syncBusinessSearchIndex.run({ params: { id } });
    assert.ok(before.isEqual((await idx(id).get()).updateTime));
  });
  await test('Pagination/limits/filters with optional fields absent', async () => {
    for (let n = 0; n < 5; n++) await ref(`page-${run}-${n}`).set(data('Paginacao Exemplo', n < 3 ? 'Onde comer?' : 'Serviços'));
    await until(async () => (await idx(`page-${run}-4`).get()).exists);
    let cursor = null; const ids = [];
    do {
      const r = await call({ query: 'paginacao', limit: 2, cursor }); assert.equal(r.status, 200);
      assert.ok(r.body.result.results.length <= 2); ids.push(...r.body.result.results.map(v => v.id)); cursor = r.body.result.nextCursor;
    } while (cursor);
    assert.equal(ids.length, 5); assert.equal(new Set(ids).size, 5);
    assert.equal((await call({ query: 'paginacao', filter: 'commerce' })).body.result.results.length, 3);
    assert.equal((await call({ query: 'paginacao', filter: 'services' })).body.result.results.length, 2);
  });
  await test('Repeated delayed CloudEvents through Functions HTTP transport', async () => {
    const event = { specversion: '1.0', id: `delayed-${run}`, type: 'google.cloud.firestore.document.v1.written',
      source: `//firestore.googleapis.com/projects/${project}/databases/(default)`,
      subject: `documents/establishments/${id}`, project, database: '(default)', location: 'southamerica-east1',
      document: `establishments/${id}`, time: '2020-01-01T00:00:00Z', datacontenttype: 'application/json',
      data: { value: { name: `projects/${project}/databases/(default)/documents/establishments/${id}`,
        fields: { name: { stringValue: 'Estado Antigo' } }, createTime: '2020-01-01T00:00:00Z', updateTime: '2020-01-01T00:00:00Z' } } };
    event.data.oldValue = { ...event.data.value };
    for (let n = 0; n < 2; n++) {
      const response = await fetch(`http://127.0.0.1:5007/functions/projects/${project}/triggers/southamerica-east1-syncBusinessSearchIndex-0`, {
        method: 'POST', headers: { 'Content-Type': 'application/cloudevents+json' }, body: JSON.stringify(event) });
      assert.equal(response.status, 200);
    }
    assert.equal((await idx(id).get()).data().title, 'Estado Final');
  });
  await test('Stale indices: unpublished/inactive/expired/deleted/renamed/category changed', async () => {
    const original = data('Obsoleto Busca');
    for (const [suffix, changes] of [['unpublished', { published: false }], ['inactive', { active: false }],
      ['expired', { expiresAt: admin.firestore.Timestamp.fromMillis(1) }], ['deleted', null],
      ['renamed', { name: 'Outro Nome' }], ['category', { category: 'Serviços' }]]) {
      const stale = `stale-${run}-${suffix}`;
      if (changes) { await ref(stale).set({ ...original, ...changes }); await backend.synchronize(stale); }
      await idx(stale).set(buildEntry(stale, original, options));
    }
    assert.equal((await call({ query: 'obsoleto', filter: 'commerce' })).body.result.results.length, 0);
  });
  await test('No full scan: actual limited queries and exact origin IDs', async () => {
    const counts = { index: 0, origin: 0, batches: [] };
    const measured = { ...store, candidates: async q => { assert.ok(q.count <= 20); const rows = await store.candidates(q);
      counts.index += rows.length; counts.batches.push(q.count); return rows; },
    sources: async ids => { counts.origin += ids.length; return store.sources(ids); } };
    const b = createSearchBackend({ store: measured, isTimestamp: options.isTimestamp });
    await db.collection(RATE).doc(crypto.createHash('sha256').update(user.localId).digest('hex')).delete();
    const r = await b.search({ auth: { uid: user.localId }, app: { appId: 'demo-local-app' }, data: { query: 'paginacao', limit: 2 } });
    assert.equal(r.results.length, 2); assert.deepEqual(counts, { index: 2, origin: 2, batches: [2] });
    console.log('READ_COUNTS', JSON.stringify(counts));
  });
  await test('Invalid queries and cursors safely rejected', async () => {
    for (const input of [{ query: '' }, { query: 'x' }, { query: 'a'.repeat(81) }, { query: 'teste', limit: 21 },
      { query: 'teste', filter: 'invalid' }, { query: 'teste', cursor: { queryKey: 'wrong', lastIndexId: 'x' } }]) {
      const r = await call(input); assert.equal(r.body.error.status, 'INVALID_ARGUMENT');
      assert.ok(!JSON.stringify(r.body).includes('stack'));
    }
  });
  await test('Real worst-case scan capped at 40 index and origin documents', async () => {
    const batch = db.batch();
    for (let n = 0; n < 45; n++) {
      const missing = `missing-${run}-${String(n).padStart(2, '0')}`;
      batch.set(idx(missing), buildEntry(missing, data('Orfaocandidato'), options));
    }
    await batch.commit();
    let index = 0; let origin = 0;
    const measured = { ...store,
      candidates: async q => { const rows = await store.candidates(q); index += rows.length; return rows; },
      sources: async ids => { origin += ids.length; return store.sources(ids); } };
    await db.collection(RATE).doc(crypto.createHash('sha256').update(user.localId).digest('hex')).delete();
    const r = await createSearchBackend({ store: measured, isTimestamp: options.isTimestamp }).search({
      auth: { uid: user.localId }, app: { appId: 'demo-local-app' }, data: { query: 'orfaocandidato', limit: 20 } });
    assert.equal(r.results.length, 0); assert.ok(r.nextCursor); assert.equal(index, 40); assert.equal(origin, 40);
    console.log('WORST_CASE_READ_COUNTS', JSON.stringify({ index, origin }));
  });
  await test('Visitor / invalid token / missing and malformed App Check denied', async () => {
    for (const args of [{ token: null }, { token: 'bad-token' }, { app: null }, { app: 'bad-token' }]) {
      const r = await call({ query: 'paginacao' }, args);
      assert.ok(['UNAUTHENTICATED', 'FAILED_PRECONDITION'].includes(r.body.error?.status));
      console.log('DENIED', Object.keys(args)[0], r.body.error.status);
    }
    const anonymous = await fetch(`${authBase}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ returnSecureToken: true }) });
    const a = await anonymous.json();
    const result = await call({ query: 'paginacao' }, { token: a.idToken });
    assert.equal(result.status, 200);
    assert.equal(result.body.result.results.length, 5);
  });
  await test('Rate limiter: interval and minute quota', async () => {
    const rate = db.collection(RATE).doc(crypto.createHash('sha256').update(user.localId).digest('hex'));
    await rate.set({ minute: Math.floor(Date.now()/60000), count: 1, lastAt: Date.now()+1000 });
    assert.equal((await call({ query: 'paginacao' }, { reset: false })).body.error.status, 'RESOURCE_EXHAUSTED');
    await rate.set({ minute: Math.floor(Date.now()/60000), count: 30, lastAt: Date.now()-1000 });
    assert.equal((await call({ query: 'paginacao' }, { reset: false })).body.error.status, 'RESOURCE_EXHAUSTED');
  });
  await test('Unchanged Firestore rules deny private index/rate direct access', async () => {
    for (const token of [null, user.idToken]) {
      const headers = token ? { Authorization: `Bearer ${token}` } : {};
      for (const path of [`${INDEX}/establishments__${id}`, `${RATE}/anything`]) {
        const r = await fetch(`${firestoreBase}/${path}`, { headers }); assert.equal(r.status, 403);
      }
      const r = await fetch(`${firestoreBase}/${INDEX}/forbidden`, { method: 'PATCH',
        headers: { ...headers, 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: { title: { stringValue: 'forbidden' } } }) });
      assert.equal(r.status, 403);
      const query = await fetch(`${firestoreBase}:runQuery`, { method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ structuredQuery: { from: [{ collectionId: INDEX }], limit: 1 } }) });
      assert.equal(query.status, 403);
    }
  });
  console.log(JSON.stringify({ project, services: ['Firestore','Functions','Auth'], passed: passed.length, tests: passed }, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => { await admin.app().delete(); });
