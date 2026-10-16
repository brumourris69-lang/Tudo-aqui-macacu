'use strict';
// Real SDK + real local services. Never run against a non-demo project.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');
const environment = readDemoEmulatorEnvironment();
const project = environment.project;
const ownedRefs = new Map();
const sourceRefs = new Map();
const indexRefs = new Map();
const createdUsers = new Set();
const createdPaths = new Set();
let stage = 'environment preflight';
function track(ref, { source = false, index = false } = {}) {
  ownedRefs.set(ref.path, ref);
  if (source) sourceRefs.set(ref.path, ref);
  if (index) indexRefs.set(ref.path, ref);
  return ref;
}
const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const auth = admin.auth();
const { createSearchBackend, buildEntry, INDEX, RATE } = require('../business_search');
const { createFirestoreStore } = require('../business_search_firestore');
const options = { now: Date.now(), isTimestamp: v => v instanceof admin.firestore.Timestamp };
const store = createFirestoreStore(db, admin.firestore);
const backend = createSearchBackend({ store, isTimestamp: options.isTimestamp });
const functionsBase = environment.functionsOrigin;
const base = `${functionsBase}/${project}/southamerica-east1/searchBusinesses`;
const tourismBase = `${functionsBase}/${project}/southamerica-east1/getSearchTourismSpot`;
const newsDetailBase = `${functionsBase}/${project}/southamerica-east1/getSearchNewsArticle`;
const authBase = `http://${environment.authHost}`;
const firestoreBase = `http://${environment.firestoreHost}/v1/projects/${project}/databases/(default)/documents`;
const run = crypto.randomUUID();
const passed = [];
async function test(name, body) { stage = name; await body(); passed.push(name); console.log('PASS', name); }
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(body) {
  const end = Date.now() + 45000;
  do { if (await body()) return; await sleep(250); } while (Date.now() < end);
  throw new Error('Trigger did not converge within 45s');
}
const ref = id => track(db.collection('establishments').doc(id), { source: true });
const idx = id => track(db.collection(INDEX).doc(`establishments__${id}`), { index: true });
const routeRef = id => track(db.collection('routes').doc(id), { source: true });
const routeIdx = id => track(db.collection(INDEX).doc(`routes__${id}`), { index: true });
const newsRef = id => track(db.collection('news').doc(id), { source: true });
const newsIdx = id => track(db.collection(INDEX).doc(`news__${id}`), { index: true });
const rateRef = () => track(db.collection(RATE).doc(crypto.createHash('sha256').update(user.localId).digest('hex')));
const newsRateRef = () => track(db.collection(RATE).doc(crypto.createHash('sha256').update(`news-detail:${user.localId}`).digest('hex')));
async function createFixture(ref, data) {
  assert.equal((await ref.get()).exists, false, 'UUID-scoped fixture ID must be unused');
  const [collection, id] = ref.path.split('/');
  if (['establishments', 'routes', 'news'].includes(collection)) {
    const index = collection === 'establishments' ? idx(id) : collection === 'routes' ? routeIdx(id) : newsIdx(id);
    assert.equal((await index.get()).exists, false, 'UUID-scoped search index ID must be unused');
  }
  await ref.create(data);
  createdPaths.add(ref.path);
  if (['establishments', 'routes', 'news'].includes(collection)) {
    const index = collection === 'establishments' ? idx(id) : collection === 'routes' ? routeIdx(id) : newsIdx(id);
    createdPaths.add(index.path); // Trigger output is owned only after the source collision check.
  }
}
async function setFixture(ref, data) {
  if (!createdPaths.has(ref.path)) return createFixture(ref, data);
  await ref.set(data);
}
async function setOwned(ref, data) {
  if (!createdPaths.has(ref.path)) {
    assert.equal((await ref.get()).exists, false, 'UUID-scoped auxiliary fixture ID must be unused');
    await ref.create(data);
    createdPaths.add(ref.path);
  } else {
    await ref.set(data);
  }
}
async function claimRateFixture(ref) {
  assert.equal((await ref.get()).exists, false, 'temporary-user rate fixture must be unused');
  createdPaths.add(ref.path);
}
const data = (name, category = 'Comércio') => ({ name, category, published: true,
  description: 'Informação pública', privateNotes: 'DO_NOT_RETURN', ownerEmail: 'private@example.invalid' });
let user;
// The official Functions Emulator decodes tokens without attestation verification.
// This fixture tests transport/context enforcement, NOT production App Check.
const jwt = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url') + '.' +
  Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now()/1000)+3600 })).toString('base64url') + '.';
async function call(input, { token = user?.idToken, app = jwt, reset = true } = {}) {
  if (reset && user) await rateRef().delete();
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (app) headers['X-Firebase-AppCheck'] = app;
  const response = await fetch(base, { method: 'POST', headers, body: JSON.stringify({ data: input }) });
  return { status: response.status, body: await response.json() };
}
async function resolveRoute(id, { token = user?.idToken, app = jwt } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (app) headers['X-Firebase-AppCheck'] = app;
  const response = await fetch(tourismBase, { method: 'POST', headers, body: JSON.stringify({ data: { id } }) });
  return { status: response.status, body: await response.json() };
}
async function resolveNews(id, { token = user?.idToken, app = jwt, reset = true } = {}) {
  if (reset && user) {
    await newsRateRef().delete();
  }
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (app) headers['X-Firebase-AppCheck'] = app;
  const response = await fetch(newsDetailBase, { method: 'POST', headers, body: JSON.stringify({ data: { id } }) });
  return { status: response.status, body: await response.json() };
}
async function main() {
  const response = await fetch(`${authBase}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `search-${run}@example.invalid`, password: 'LocalTest123!', returnSecureToken: true }) });
  assert.equal(response.status, 200); user = await response.json(); createdUsers.add(user.localId);
  await claimRateFixture(rateRef());
  await claimRateFixture(newsRateRef());
  await test('Auth Emulator account/token', async () => {
    assert.equal((await admin.auth().verifyIdToken(user.idToken)).uid, user.localId);
  });
  const id = `integration-${run}`;
  await test('Automatic create trigger + public projection', async () => {
    await createFixture(ref(id), data('Elétrica Vieira', 'Tecnologia'));
    await until(async () => (await idx(id).get()).data()?.title === 'Elétrica Vieira');
    const entry = (await idx(id).get()).data();
    assert.equal(entry.id, id); assert.equal(entry.group, 'commerce');
    assert.equal(entry.privateNotes, undefined); assert.equal(entry.ownerEmail, undefined);
  });
  const routeId = id; // Same ID in both collections remains a distinct record.
  await test('Tourism trigger, prefixes, and safe detail resolution', async () => {
    await createFixture(routeRef(routeId), { published: true, active: true, title: 'VeuUnico Cachoeira',
      category: 'Cachoeiras', description: 'Águas da região', location: 'Bacia do Rio Macacu',
      maps: 'https://maps.example.invalid', additionalInfo: 'Leve água', ownerEmail: 'private@example.invalid' });
    await until(async () => (await routeIdx(routeId).get()).data()?.title === 'VeuUnico Cachoeira');
    const routeEntry = (await routeIdx(routeId).get()).data();
    assert.equal(routeEntry.sourceCollection, 'routes'); assert.equal(routeEntry.type, 'tourism');
    assert.ok(routeEntry.prefixes.includes('cach')); assert.ok(routeEntry.prefixes.includes('bacia'));
    assert.equal(routeEntry.ownerEmail, undefined);
    const found = await call({ query: 'veuuni', filter: 'tourism' });
    assert.equal(found.status, 200); assert.equal(found.body.result.results[0].id, routeId);
    assert.equal(found.body.result.results[0].destination, 'touristSpotDetail');
    await routeRef(routeId).update({ title: 'Trilha Nova', category: 'Trilhas', location: 'Serra Macacu' });
    await until(async () => (await routeIdx(routeId).get()).data()?.title === 'Trilha Nova');
    assert.equal((await call({ query: 'nova', filter: 'tourism' })).body.result.results[0].title, 'Trilha Nova');
    assert.equal((await call({ query: 'veuuni', filter: 'tourism' })).body.result.results.length, 0);
    const { onCall, HttpsError } = require('firebase-functions/v2/https');
    const { onDocumentWritten } = require('firebase-functions/v2/firestore');
    const handlers = require('../business_search_functions').registerLocalSearch({ admin, onCall, HttpsError, onDocumentWritten });
    const before = (await routeIdx(routeId).get()).updateTime;
    await Promise.all(Array.from({ length: 5 }, () => handlers.syncTourismSearchIndex.run({
      params: { id: routeId }, data: { after: { title: 'Estado anterior' } },
    })));
    await handlers.syncTourismSearchIndex.run({ params: { id: routeId } });
    assert.ok(before.isEqual((await routeIdx(routeId).get()).updateTime));
    const detail = await resolveRoute(routeId);
    assert.equal(detail.status, 200); assert.equal(detail.body.result.id, routeId);
    assert.equal(detail.body.result.data.additionalInfo, 'Leve água');
    assert.equal(detail.body.result.data.ownerEmail, undefined);
  });
  const newsId = `news-${run}`;
  await test('News trigger indexes public terms and rejects stale/hidden content', async () => {
    await createFixture(newsRef(newsId), { published: true, active: true, title: 'Festival Fictício de Macacu abre inscrições',
      category: 'Notícias de teste', description: 'Conteúdo fictício; atualização pública', location: 'Cachoeiras de Macacu',
      additionalInfo: 'Serviço comunitário', imageUrl: 'https://images.example.invalid/noticia.jpg',
      privateNotes: 'DO_NOT_RETURN', targetEmail: 'private@example.invalid' });
    await until(async () => (await newsIdx(newsId).get()).data()?.title === 'Festival Fictício de Macacu abre inscrições');
    const entry = (await newsIdx(newsId).get()).data();
    assert.equal(entry.sourceCollection, 'news'); assert.equal(entry.type, 'news');
    assert.equal(entry.group, 'news'); assert.equal(entry.destination, 'newsArticle');
    assert.ok(entry.prefixes.includes('noticia')); assert.ok(entry.prefixes.includes('comunitario'));
    assert.ok(entry.prefixes.includes('festival')); assert.ok(entry.prefixes.includes('inscricoes'));
    assert.equal(entry.privateNotes, undefined); assert.equal(entry.targetEmail, undefined);
    assert.equal(entry.imageUrl, ''); // Local network image authorization remains fail-closed.
    const found = await call({ query: 'festival maca', filter: 'news' });
    assert.equal(found.status, 200); assert.equal(found.body.result.results[0].id, newsId);
    assert.equal(found.body.result.results[0].destination, 'newsArticle');
    for (const filter of ['all', 'news']) {
      const festival = await call({ query: 'festival', filter });
      assert.equal(festival.status, 200);
      assert.ok(festival.body.result.results.some(result => result.id === newsId), `${filter} includes the published news article`);
    }
    const prefix = await call({ query: 'inscricoes', filter: 'all' });
    assert.equal(prefix.status, 200);
    assert.ok(prefix.body.result.results.some(result => result.id === newsId), 'Todos includes the news prefix match');
    const detail = await resolveNews(newsId);
    assert.equal(detail.status, 200); assert.equal(detail.body.result.status, 'available');
    assert.equal(detail.body.result.id, newsId);
    assert.equal(detail.body.result.data.title, 'Festival Fictício de Macacu abre inscrições');
    assert.equal(detail.body.result.data.description, 'Conteúdo fictício; atualização pública');
    assert.equal(detail.body.result.data.category, 'Notícias de teste');
    assert.equal(detail.body.result.data.targetEmail, undefined);
    assert.equal(detail.body.result.data.privateNotes, undefined);
    assert.equal(detail.body.result.data.admin, undefined);
    assert.deepEqual(await resolveNews('missing-news-id').then(result => result.body.result), { status: 'unavailable' });
    assert.equal((await resolveNews('bad/id')).body.error.status, 'INVALID_ARGUMENT');
    assert.ok(['UNAUTHENTICATED', 'FAILED_PRECONDITION'].includes(
      (await resolveNews(newsId, { token: null })).body.error.status));
    assert.ok(['UNAUTHENTICATED', 'FAILED_PRECONDITION'].includes(
      (await resolveNews(newsId, { app: null })).body.error.status));
    assert.ok(['UNAUTHENTICATED', 'FAILED_PRECONDITION'].includes(
      (await resolveNews(newsId, { app: 'bad-token' })).body.error.status));
    await newsRef(newsId).update({ title: 'Notícia Atualizada Macacu', category: 'Serviços' });
    await until(async () => (await newsIdx(newsId).get()).data()?.title === 'Notícia Atualizada Macacu');
    assert.equal((await call({ query: 'atualizada', filter: 'news' })).body.result.results[0].id, newsId);
    assert.equal((await call({ query: 'acao', filter: 'news' })).body.result.results.length, 0);
    const { onCall, HttpsError } = require('firebase-functions/v2/https');
    const { onDocumentWritten } = require('firebase-functions/v2/firestore');
    const handlers = require('../business_search_functions').registerLocalSearch({ admin, onCall, HttpsError, onDocumentWritten });
    const before = (await newsIdx(newsId).get()).updateTime;
    await Promise.all(Array.from({ length: 4 }, () => handlers.syncNewsSearchIndex.run({
      params: { id: newsId }, data: { after: { title: 'Estado antigo' } },
    })));
    assert.ok(before.isEqual((await newsIdx(newsId).get()).updateTime));
    await newsRef(newsId).update({ published: false });
    await until(async () => !(await newsIdx(newsId).get()).exists);
    assert.equal((await call({ query: 'atualizada', filter: 'news' })).body.result.results.length, 0);
    assert.deepEqual((await resolveNews(newsId)).body.result, { status: 'unavailable' });
    // A deliberately stale projection still cannot return a now-private source.
    await setFixture(newsIdx(newsId), entry);
    assert.equal((await call({ query: 'noticia', filter: 'news' })).body.result.results.length, 0);
    for (const [name, changes] of [['deactivation', { active: false }],
      ['expiry', { expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) }]]) {
      await setFixture(newsRef(newsId), { published: true, title: 'Notícia Temporal Macacu' });
      await until(async () => (await newsIdx(newsId).get()).exists);
      await newsRef(newsId).update(changes);
      await until(async () => !(await newsIdx(newsId).get()).exists);
      assert.equal((await call({ query: 'temporal', filter: 'news' })).body.result.results.length, 0, name);
      assert.deepEqual((await resolveNews(newsId)).body.result, { status: 'unavailable' }, name);
    }
    await newsRef(newsId).delete();
    await until(async () => !(await newsIdx(newsId).get()).exists);
    assert.deepEqual((await resolveNews(newsId)).body.result, { status: 'unavailable' });
    await setOwned(newsRateRef(), { minute: Math.floor(Date.now() / 60000), count: 60, lastAt: Date.now() });
    assert.equal((await resolveNews(newsId, { reset: false })).body.error.status, 'RESOURCE_EXHAUSTED');
    await newsRateRef().delete();
  });
  await test('Todos paginates across establishments, routes and news in stable order', async () => {
    const routeId2 = `route-${run}`;
    const businessId2 = `combo-${run}`;
    const newsId2 = `news-combo-${run}`;
    await createFixture(routeRef(routeId2), { published: true, title: 'Paginacao Macacu', category: 'Trilhas',
      description: 'Bacia do Rio Macacu', location: 'Cachoeiras locais' });
    await createFixture(ref(businessId2), data('Paginacao Macacu'));
    await createFixture(newsRef(newsId2), { published: true, title: 'Paginacao Macacu', category: 'Cidade' });
    await until(async () => (await routeIdx(routeId2).get()).exists && (await idx(businessId2).get()).exists &&
      (await newsIdx(newsId2).get()).exists);
    const collected = []; let cursor = null;
    do {
      const response = await call({ query: 'paginacao', limit: 1, cursor });
      assert.equal(response.status, 200);
      collected.push(...response.body.result.results.map(row => `${row.sourceCollection}:${row.id}`));
      cursor = response.body.result.nextCursor;
    } while (cursor);
    assert.deepEqual(collected, [`establishments:${businessId2}`, `news:${newsId2}`, `routes:${routeId2}`].sort());
    assert.equal(new Set(collected).size, collected.length);
    assert.equal((await call({ query: 'paginacao', filter: 'tourism' })).body.result.results.length, 1);
    assert.equal((await call({ query: 'paginacao', filter: 'news' })).body.result.results.length, 1);
    await Promise.all([routeRef(routeId2).delete(), ref(businessId2).delete(), newsRef(newsId2).delete()]);
    await until(async () => !(await routeIdx(routeId2).get()).exists && !(await idx(businessId2).get()).exists &&
      !(await newsIdx(newsId2).get()).exists);
  });
  await test('Tourism visibility, expiry, removal, and source revalidation', async () => {
    await routeRef(routeId).update({ published: false });
    await until(async () => !(await routeIdx(routeId).get()).exists);
    assert.equal((await call({ query: 'nova', filter: 'tourism' })).body.result.results.length, 0);
    assert.equal((await resolveRoute(routeId)).body.result, null);
    const expiredId = `expired-route-${run}`;
    await createFixture(routeRef(expiredId), { published: true, title: 'Cachoeira Expirada', category: 'Cachoeiras',
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 1000) });
    await until(async () => (await routeIdx(expiredId).get()).exists);
    await sleep(1200);
    assert.equal((await call({ query: 'expirada', filter: 'tourism' })).body.result.results.length, 0);
    assert.equal((await resolveRoute(expiredId)).body.result, null);
    await routeRef(expiredId).delete();
    await until(async () => !(await routeIdx(expiredId).get()).exists);
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
      await setFixture(ref(id), { ...data('Elétrica Renovada', 'Profissionais'), ...changes });
      await until(async () => !(await idx(id).get()).exists);
      assert.equal((await call({ query: 'renovada' })).body.result.results.length, 0);
      await setFixture(ref(id), data('Elétrica Renovada', 'Profissionais'));
      await until(async () => (await idx(id).get()).exists);
    });
  }
  await test('Expired without another write is revalidated', async () => {
    await setFixture(ref(id), { ...data('Temporal Expiração'), expiresAt: admin.firestore.Timestamp.fromMillis(Date.now()+2000) });
    await until(async () => (await idx(id).get()).data()?.title === 'Temporal Expiração');
    await sleep(2200);
    assert.equal((await call({ query: 'temporal' })).body.result.results.length, 0);
  });
  await test('Automatic delete', async () => {
    await ref(id).delete(); await until(async () => !(await idx(id).get()).exists);
  });
  await test('Duplicate/out-of-order handler + concurrent real transactions', async () => {
    await setFixture(ref(id), data('Estado Antigo'));
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
    for (let n = 0; n < 5; n++) await createFixture(ref(`page-${run}-${n}`), data('Paginacao Exemplo', n < 3 ? 'Onde comer?' : 'Serviços'));
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
      const response = await fetch(`${functionsBase}/functions/projects/${project}/triggers/southamerica-east1-syncBusinessSearchIndex-0`, {
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
      if (changes) { await createFixture(ref(stale), { ...original, ...changes }); await backend.synchronize(stale); }
      // The source trigger may already have created this owned index. Replace it
      // with the intentionally stale projection instead of requiring absence.
      await setFixture(idx(stale), buildEntry(stale, original, options));
    }
    assert.equal((await call({ query: 'obsoleto', filter: 'commerce' })).body.result.results.length, 0);
  });
  await test('No full scan: actual limited queries and exact origin IDs', async () => {
    const counts = { index: 0, origin: 0, batches: [] };
    const measured = { ...store, candidates: async q => { assert.ok(q.count <= 20); const rows = await store.candidates(q);
      counts.index += rows.length; counts.batches.push(q.count); return rows; },
    sources: async ids => { counts.origin += ids.length; return store.sources(ids); } };
    const b = createSearchBackend({ store: measured, isTimestamp: options.isTimestamp });
    await rateRef().delete();
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
      const orphan = idx(missing);
      assert.equal((await orphan.get()).exists, false, 'UUID-scoped orphan fixture ID must be unused');
      batch.set(orphan, buildEntry(missing, data('Orfaocandidato'), options));
    }
    await batch.commit();
    for (let n = 0; n < 45; n++) createdPaths.add(idx(`missing-${run}-${String(n).padStart(2, '0')}`).path);
    let index = 0; let origin = 0;
    const measured = { ...store,
      candidates: async q => { const rows = await store.candidates(q); index += rows.length; return rows; },
      sources: async ids => { origin += ids.length; return store.sources(ids); } };
    await rateRef().delete();
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
    createdUsers.add(a.localId);
    await claimRateFixture(track(db.collection(RATE).doc(crypto.createHash('sha256').update(a.localId).digest('hex'))));
    const result = await call({ query: 'paginacao' }, { token: a.idToken });
    assert.equal(result.status, 200);
    assert.equal(result.body.result.results.length, 5);
  });
  await test('Rate limiter: interval and minute quota', async () => {
    const rate = rateRef();
    await setOwned(rate, { minute: Math.floor(Date.now()/60000), count: 1, lastAt: Date.now()+1000 });
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
async function cleanup() {
  const errors = [];
  for (const ref of sourceRefs.values()) {
    if (!createdPaths.has(ref.path)) continue;
    try { await ref.delete(); } catch (_) { errors.push('source cleanup failed'); }
  }
  const ownedIndexes = [...indexRefs.values()].filter(ref => createdPaths.has(ref.path));
  const deleteOwnedIndexes = async () => {
    const results = await Promise.all(ownedIndexes.map(ref => ref.delete().then(() => null, () => 'index cleanup failed')));
    errors.push(...results.filter(Boolean));
  };
  const waitForIndexesToSettle = async () => {
    const deadline = Date.now() + 45000;
    let absentSince = null;
    while (Date.now() < deadline) {
      const snapshots = await Promise.all(ownedIndexes.map(ref => ref.get()));
      if (snapshots.every(snapshot => !snapshot.exists)) {
        absentSince ??= Date.now();
        if (Date.now() - absentSince >= 500) return true;
      } else {
        absentSince = null;
      }
      await sleep(200);
    }
    return false;
  };
  // Delete only UUID-owned index refs, including intentionally orphaned test
  // candidates that have no source trigger capable of removing them.
  await deleteOwnedIndexes();
  if (ownedIndexes.length && !(await waitForIndexesToSettle())) {
    await deleteOwnedIndexes();
    if (!(await waitForIndexesToSettle())) errors.push('owned search index cleanup did not converge');
  }
  for (const ref of ownedRefs.values()) {
    if (!createdPaths.has(ref.path) || sourceRefs.has(ref.path) || indexRefs.has(ref.path)) continue;
    try { await ref.delete(); } catch (_) { errors.push('owned auxiliary cleanup failed'); }
  }
  const remainingRefs = [...createdPaths].map(path => ownedRefs.get(path)).filter(Boolean);
  let remaining = [];
  try {
    remaining = (await Promise.all(remainingRefs.map(async ref => (await ref.get()).exists ? ref : null))).filter(Boolean);
    if (remaining.length) {
      const categories = new Set(remaining.map(ref => indexRefs.has(ref.path) ? 'search-index' :
        sourceRefs.has(ref.path) ? 'source' : 'auxiliary'));
      for (const category of categories) errors.push(`owned ${category} fixture remained at first verification`);
      await Promise.all(remaining.map(ref => ref.delete()));
      if (remaining.some(ref => indexRefs.has(ref.path)) &&
          !(await waitForIndexesToSettle())) errors.push('owned search index cleanup did not converge');
      const verified = await Promise.all(remaining.map(ref => ref.get()));
      if (verified.some(snapshot => snapshot.exists)) errors.push('owned fixture remains');
    }
  } catch (_) { errors.push('fixture cleanup verification failed'); }
  if (remaining.length) {
    // Allow source-delete triggers a short settle window, then verify the exact
    // owned index references once more before reporting success.
    await sleep(500);
    const indexSnapshots = await Promise.all(ownedIndexes.map(ref => ref.get()));
    if (indexSnapshots.some(snapshot => snapshot.exists)) errors.push('owned search index fixture remains');
  }
  for (const uid of createdUsers) {
    try { await auth.deleteUser(uid); } catch (error) {
      if (error?.code !== 'auth/user-not-found') errors.push(`Auth fixture delete failed (${error?.code || error?.name || 'unknown'})`);
    }
    try { await auth.getUser(uid); errors.push('Auth fixture remains'); } catch (error) {
      if (error?.code !== 'auth/user-not-found') errors.push(`Auth fixture verification failed (${error?.code || error?.name || 'unknown'})`);
    }
  }
  await admin.app().delete();
  if (errors.length) {
    const error = new Error('Owned fixture cleanup incomplete.');
    error.cleanupCategories = [...new Set(errors)];
    throw error;
  }
  console.log(`Search Emulator cleanup verified: ${createdPaths.size} Firestore fixture paths and ${createdUsers.size} Auth users removed.`);
}
main().catch(error => {
  const frames = String(error?.stack || '').split('\n').slice(1, 5).map(line => line.trim());
  console.error(JSON.stringify({ failedStage: stage, errorType: error?.name || 'Error', stack: frames }));
  process.exitCode = 1;
}).finally(cleanup).catch(error => {
  console.error(JSON.stringify({ failedStage: 'fixture cleanup', errorType: error?.name || 'Error',
    categories: error?.cleanupCategories || [] }));
  process.exitCode = 1;
});
