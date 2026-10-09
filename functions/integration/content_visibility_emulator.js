'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { localOnly } = require('../business_search');
const { PUBLIC_COLLECTIONS } = require('../content_visibility');
const { changeAdminClaim } = require('../admin_claim_management');
assert.equal(localOnly(), true);
assert.equal(process.env.GCLOUD_PROJECT, 'demo-universal-search');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
admin.initializeApp({ projectId: 'demo-universal-search' });
const db = admin.firestore(), auth = admin.auth();
const root = 'http://127.0.0.1:8087/v1/projects/demo-universal-search/databases/(default)/documents';
const authRoot = 'http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1';
const tag = `c${Date.now().toString(36)}`;
const prefix = `000-visibility-${tag}`;
const created = [];
let passed = 0;
const headers = token => ({ 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) });
const enc = data => Buffer.from(JSON.stringify(data)).toString('base64url');
const app = `${enc({ alg: 'none' })}.${enc({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
async function test(name, body) { await body(); passed++; console.log('PASS', name); }
async function account(name, anonymous = false) {
  const email = `${tag}-${name}@example.invalid`;
  const r = await fetch(`${authRoot}/accounts:signUp?key=demo-key`, { method: 'POST', headers: headers(),
    body: JSON.stringify(anonymous ? { returnSecureToken: true } : { email, password: 'LocalOnly123!', returnSecureToken: true }) });
  assert.equal(r.status, 200); const user = await r.json(); created.push(user.localId);
  return { ...user, email };
}
async function login(user) {
  const r = await fetch(`${authRoot}/accounts:signInWithPassword?key=demo-key`, { method: 'POST', headers: headers(),
    body: JSON.stringify({ email: user.email, password: 'LocalOnly123!', returnSecureToken: true }) });
  assert.equal(r.status, 200); return (await r.json()).idToken;
}
async function call(name, data, token, appToken = app) {
  const r = await fetch(`http://127.0.0.1:5007/demo-universal-search/southamerica-east1/${name}`, {
    method: 'POST', headers: { ...headers(token), ...(appToken ? { 'X-Firebase-AppCheck': appToken } : {}) },
    body: JSON.stringify({ data }) });
  return { status: r.status, body: await r.json() };
}
async function read(collection, id, token) { return (await fetch(`${root}/${collection}/${id}`, { headers: headers(token) })).status; }
async function list(collection, token) {
  return (await fetch(`${root}:runQuery`, { method: 'POST', headers: headers(token), body: JSON.stringify({ structuredQuery: {
    from: [{ collectionId: collection }], limit: 40,
    where: { fieldFilter: { field: { fieldPath: collection === 'utilities' ? 'active' : 'published' }, op: 'EQUAL', value: { booleanValue: true } } },
  } }) })).status;
}
async function main() {
  const rules = await fetch('http://127.0.0.1:8087/emulator/v1/projects/demo-universal-search:securityRules', {
    method: 'PUT', headers: headers(), body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') }] } }) });
  assert.equal(rules.status, 200);
  const visitor = await account('visitor', true), user = await account('user'), operator = await account('admin');
  const mutate = action => changeAdminClaim({ auth, db, uid: operator.localId, action, operator: 'visibility-test',
    reason: 'demo-only', apply: true, confirmation: `demo-universal-search:${operator.localId}:${action}` });
  await mutate('grant'); const adminToken = await login(operator);
  for (const collection of PUBLIC_COLLECTIONS) {
    const base = { title: `${tag} Eletrica Vieira`, name: `${tag} Eletrica Vieira`, category: 'Tecnologia',
      published: true, active: true, open: false, targetEmail: '', ownerEmail: 'private@example.invalid', privateNotes: 'not-public' };
    const legacy = { published: true, title: `${tag} Legado`, targetEmail: '' };
    if (collection === 'utilities') { delete legacy.published; legacy.active = true; }
    const fixtures = { good: base, unpublished: { ...base, published: false }, inactive: { ...base, active: false },
      expired: { ...base, expiresAt: Timestamp.fromMillis(Date.now() - 60000) },
      future: { ...base, expiresAt: Timestamp.fromMillis(Date.now() + 3600000) },
      malformed: { ...base, expiresAt: null }, legacy };
    const batch = db.batch();
    for (const [kind, data] of Object.entries(fixtures)) batch.set(db.collection(collection).doc(`${prefix}-${kind}`), data);
    await batch.commit();
    await test(`${collection}: direct gets, optional legacy, admin management and protected lists`, async () => {
      for (const token of [undefined, visitor.idToken, user.idToken]) {
        for (const kind of Object.keys(fixtures)) {
          const expected = ['good', 'future', 'legacy'].includes(kind) ? 200 : 403;
          assert.equal(await read(collection, `${prefix}-${kind}`, token), expected, `${collection}/${kind}`);
        }
        assert.equal(await list(collection, token), 403);
      }
      for (const kind of Object.keys(fixtures)) assert.equal(await read(collection, `${prefix}-${kind}`, adminToken), 200);
      assert.equal(await list(collection, adminToken), 200);
    });
    await test(`${collection}: authenticated backend excludes every ineligible source and private fields`, async () => {
      const response = await call('listPublicContent', { collection, limit: 40 }, visitor.idToken);
      assert.equal(response.status, 200, JSON.stringify(response.body));
      const items = response.body.result.items.filter(item => item.id.startsWith(prefix));
      assert.deepEqual(items.map(item => item.id).sort(), ['future', 'good', 'legacy'].map(kind => `${prefix}-${kind}`).sort());
      for (const item of items) { assert.equal(item.data.ownerEmail, undefined); assert.equal(item.data.privateNotes, undefined); assert.equal(item.data.targetEmail, undefined); }
    });
  }
  await test('Actual event date in the future is public, not a publication schedule', async () => {
    await db.collection('events').doc(`${prefix}-scheduled-event`).set({ published: true, startsAt: Timestamp.fromMillis(Date.now() + 86400000) });
    assert.equal(await read('events', `${prefix}-scheduled-event`), 200);
  });
  await test('Admin edits inactive record, fixes expiry and republishes without weakening claims', async () => {
    const r = await fetch(`${root}/news/${prefix}-inactive`, { method: 'PATCH', headers: headers(adminToken),
      body: JSON.stringify({ fields: { title: { stringValue: 'Reativado fictício' }, published: { booleanValue: true }, active: { booleanValue: true },
        expiresAt: { timestampValue: new Date(Date.now() + 3600000).toISOString() } } }) });
    assert.equal(r.status, 200); assert.equal(await read('news', `${prefix}-inactive`), 200);
  });
  await test('Backend rejects no Auth, invalid Auth/App Check, missing App Check, unknown collections and arbitrary limits', async () => {
    for (const token of [undefined, 'invalid-local-token']) assert.notEqual((await call('listPublicContent', { collection: 'news', limit: 10 }, token)).status, 200);
    for (const token of [null, 'invalid-app']) assert.notEqual((await call('listPublicContent', { collection: 'news', limit: 10 }, user.idToken, token)).status, 200);
    for (const data of [{ collection: 'users', limit: 10 }, { collection: 'news', limit: 999 }, { collection: 'news', limit: 1, cursor: '../bad' }]) {
      assert.notEqual((await call('listPublicContent', data, user.idToken)).status, 200);
    }
  });
  await test('Pagination uses stable original IDs and changed sources cannot leak through later pages', async () => {
    const first = await call('listPublicContent', { collection: 'ads', limit: 1 }, user.idToken);
    assert.equal(first.status, 200); assert.equal(first.body.result.items.length, 1);
    const cursor = first.body.result.nextCursor; assert.equal(typeof cursor, 'string');
    const second = await call('listPublicContent', { collection: 'ads', limit: 1, cursor }, user.idToken);
    assert.equal(second.status, 200); assert.notEqual(first.body.result.items[0].id, second.body.result.items[0].id);
  });
  await test('Universal search keeps private index, accents, visibility revalidation and original profile IDs', async () => {
    const index = db.collection('business_search_index').doc(`establishments__${prefix}-good`);
    const deadline = Date.now() + 30000;
    while (!(await index.get()).exists && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 250));
    assert.equal((await index.get()).exists, true);
    assert.equal(await read('business_search_index', index.id, user.idToken), 403);
    const found = await call('searchBusinesses', { query: `${tag} elétrica`, limit: 20 }, user.idToken);
    assert.equal(found.status, 200, JSON.stringify(found.body));
    assert.ok(found.body.result.results.some(item => item.id === `${prefix}-good`));
    assert.ok(!found.body.result.results.some(item => /-(inactive|expired|unpublished|malformed)$/.test(item.id)));
    assert.equal(await read('establishments', `${prefix}-good`, user.idToken), 200);
    const rate = db.collection('business_search_rate_limits').doc(require('node:crypto').createHash('sha256').update(user.localId).digest('hex'));
    for (const filter of ['commerce', 'services']) {
      await rate.delete();
      const filtered = await call('searchBusinesses', { query: `${tag} elétrica`, filter, limit: 20 }, user.idToken);
      assert.equal(filtered.status, 200);
      if (filter === 'commerce') assert.ok(filtered.body.result.results.some(item => item.id === `${prefix}-good`));
      else assert.equal(filtered.body.result.results.length, 0);
    }
    await rate.delete();
    const paged = await call('searchBusinesses', { query: `${tag} elétrica`, limit: 1 }, user.idToken);
    assert.equal(paged.status, 200); assert.equal(paged.body.result.results.length, 1);
    assert.ok(paged.body.result.nextCursor);
    const previousEntry = (await index.get()).data();
    await db.collection('establishments').doc(`${prefix}-good`).update({ published: false });
    // Force a stale projection: publication is revalidated from the source.
    await index.set(previousEntry);
    await db.collection('business_search_rate_limits').doc(require('node:crypto').createHash('sha256').update(user.localId).digest('hex')).delete();
    const changed = await call('searchBusinesses', { query: `${tag} elétrica`, limit: 20 }, user.idToken);
    assert.equal(changed.status, 200); assert.ok(!changed.body.result.results.some(item => item.id === `${prefix}-good`));
    assert.equal(await read('establishments', `${prefix}-good`, user.idToken), 403);
  });
  await test('Revoked Admin with original token cannot read restricted content or run administrative lists', async () => {
    await mutate('revoke');
    for (const collection of PUBLIC_COLLECTIONS) {
      assert.equal(await read(collection, `${prefix}-inactive`, adminToken), collection === 'news' ? 200 : 403);
      assert.equal(await list(collection, adminToken), 403);
    }
  });
  console.log(`Visibility emulator: ${passed} scenarios passed; ${PUBLIC_COLLECTIONS.length} collections; demo only.`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; })
  .finally(async () => { for (const uid of created) await auth.deleteUser(uid); await admin.app().delete(); });
