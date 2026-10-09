'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { localOnly } = require('../business_search');
assert.equal(localOnly(), true);
assert.equal(process.env.GCLOUD_PROJECT, 'demo-universal-search');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
const admin = require('firebase-admin');
const { changeAdminClaim } = require('../admin_claim_management');
const { requireAdmin, uploadHomeImage } = require('../home_image_upload');
const { authorizeCurrentAdmin } = require('../admin_authorization');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore(), auth = admin.auth();
const project = process.env.GCLOUD_PROJECT, run = `claims-${Date.now()}`;
const root = `http://127.0.0.1:8087/v1/projects/${project}/databases/(default)/documents`;
const authRoot = 'http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1';
const created = [];
let passed = 0;
async function test(name, body) { await body(); console.log('PASS', name); passed++; }
async function authCall(endpoint, body) {
  const response = await fetch(`${authRoot}/${endpoint}?key=demo-key`, { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  assert.equal(response.status, 200, `local Auth ${endpoint}`); return response.json();
}
async function account(name, email = `${run}-${name}@example.invalid`) {
  const user = await authCall('accounts:signUp', { email, password: 'LocalOnly123!', returnSecureToken: true });
  created.push(user.localId); return { ...user, email };
}
function headers(token) { return { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }; }
async function write(token, collection = 'notifications', fields = { title: { stringValue: 'Fictício' }, published: { booleanValue: true }, targetEmail: { stringValue: '' } }) {
  return (await fetch(`${root}/${collection}/${run}`, { method: 'PATCH', headers: headers(token), body: JSON.stringify({ fields }) })).status;
}
async function callable(token) {
  const response = await fetch('http://127.0.0.1:5007/demo-universal-search/us-central1/uploadHomeImage', {
    method: 'POST', headers: headers(token), body: JSON.stringify({ data: { purpose: 'not-upload' } }),
  });
  return { status: response.status, body: await response.json() };
}
async function main() {
  const loaded = await fetch(`http://127.0.0.1:8087/emulator/v1/projects/${project}:securityRules`, { method: 'PUT',
    headers: headers(), body: JSON.stringify({ rules: { files: [{ name: 'firestore.rules',
      content: fs.readFileSync(path.join(__dirname, '../../firestore.rules'), 'utf8') }] } }) });
  assert.equal(loaded.status, 200);
  const user = await account('operator'), ordinary = await account('ordinary');
  // This is an emulator fixture, not an operation on the real administrative account.
  const legacy = await account('legacy', 'legacy-admin@example.com');
  await auth.updateUser(legacy.localId, { emailVerified: true });
  legacy.idToken = (await authCall('accounts:signInWithPassword', { email: legacy.email, password: 'LocalOnly123!', returnSecureToken: true })).idToken;
  const visitor = await authCall('accounts:signUp', { returnSecureToken: true }); created.push(visitor.localId);
  await test('Common user, unauthenticated visitor, anonymous visitor and legacy admin email without claim denied', async () => {
    for (const token of [user.idToken, ordinary.idToken, legacy.idToken, visitor.idToken, undefined]) assert.equal(await write(token), 403);
  });
  await test('Profile fields and private administrative audit cannot grant privileges', async () => {
    const r = await fetch(`${root}/users/${ordinary.localId}`, { method: 'PATCH', headers: headers(ordinary.idToken),
      body: JSON.stringify({ fields: { role: { stringValue: 'admin' }, admin: { booleanValue: true } } }) });
    assert.equal(r.status, 403);
    // A profile value is never an authorization source, even if it already
    // exists from legacy data or another workflow.
    await db.collection('users').doc(ordinary.localId).set({ role: 'admin', admin: true });
    assert.equal(await write(ordinary.idToken), 403);
    const attempt = await fetch(`${authRoot}/accounts:update?key=demo-key`, { method: 'POST', headers: headers(),
      body: JSON.stringify({ idToken: ordinary.idToken, customAttributes: JSON.stringify({ admin: true }), returnSecureToken: true }) });
    // Some emulator versions ignore unknown fields; either way the claim must
    // not be granted by a client's ID token.
    assert.ok([200, 400, 403].includes(attempt.status));
    assert.notEqual((await auth.getUser(ordinary.localId)).customClaims?.admin, true);
    assert.equal(await write(ordinary.idToken, 'admin_claim_changes'), 403);
    assert.equal((await fetch('http://127.0.0.1:5007/demo-universal-search/us-central1/grantAdmin', { method: 'POST', headers: headers(ordinary.idToken), body: '{}' })).status, 404);
  });
  const change = action => changeAdminClaim({ auth, db, uid: user.localId, action,
    operator: 'trusted-local-test', reason: 'Emulator-only verification', apply: true,
    confirmation: `${project}:${user.localId}:${action}` });
  await test('Trusted grant records audit and does not change already-issued token', async () => {
    await change('grant'); assert.equal((await auth.getUser(user.localId)).customClaims.admin, true);
    assert.equal(await write(user.idToken), 403);
  });
  let adminToken, adminDecoded;
  await test('Token refresh obtains boolean claim and allows administrative operations without email authority', async () => {
    const response = await fetch('http://127.0.0.1:9097/securetoken.googleapis.com/v1/token?key=demo-key', { method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: user.refreshToken }) });
    assert.equal(response.status, 200); adminToken = (await response.json()).id_token;
    const decoded = await auth.verifyIdToken(adminToken);
    adminDecoded = decoded;
    assert.equal(decoded.admin, true); requireAdmin({ uid: decoded.uid, token: decoded });
    assert.equal(await write(adminToken), 200);
    const accepted = await callable(adminToken);
    assert.equal(accepted.body.error.status, 'INVALID_ARGUMENT'); // passed authorization, stopped before image/provider
    assert.equal(await authorizeCurrentAdmin({ uid: user.localId, token: decoded }, { db }), true);
    assert.equal(await write(adminToken, 'private_notifications', { title: { stringValue: 'Privada fictícia' }, published: { booleanValue: true }, targetUid: { stringValue: ordinary.localId } }), 200);
  });
  await test('All sensitive Rules operations share the current authorization state', async () => {
    for (const collection of ['establishments', 'news', 'events', 'home_pages']) {
      assert.equal(await write(adminToken, collection), 200, collection);
    }
    const target = db.collection('admin_authorizations').doc(user.localId);
    const saved = (await target.get()).data();
    await target.update({ enabled: false });
    for (const collection of ['establishments', 'news', 'events', 'home_pages', 'notifications', 'notification_queue']) {
      assert.equal(await write(adminToken, collection), 403, collection);
    }
    await target.set(saved);
    const own = await fetch(`${root}/admin_authorizations/${user.localId}`, { headers: headers(adminToken) });
    assert.equal(own.status, 200);
    assert.equal((await fetch(`${root}/admin_authorizations/${user.localId}`, { headers: headers(ordinary.idToken) })).status, 403);
    // Worker transport adapter routes the otherwise fixed URL exclusively to demo localhost.
    const { verifyAdminState } = await import('../../workers/image-upload/src/admin-state.js');
    const decoded = await auth.verifyIdToken(adminToken);
    const transport = (_url, options) => fetch(`${root}/admin_authorizations/${user.localId}`, options);
    assert.equal(await verifyAdminState({ uid: user.localId, token: decoded }, adminToken, 'tudo-aqui-macacu', transport), true);
    await target.update({ enabled: false });
    assert.equal(await verifyAdminState({ uid: user.localId, token: decoded }, adminToken, 'tudo-aqui-macacu', transport), false);
    await target.set(saved);
  });
  await test('Private notification remains recipient-only plus claim Admin', async () => {
    const uri = `${root}/private_notifications/${run}`;
    assert.equal((await fetch(uri, { headers: headers(ordinary.idToken) })).status, 200);
    assert.equal((await fetch(uri, { headers: headers(adminToken) })).status, 200);
    assert.equal((await fetch(uri, { headers: headers(legacy.idToken) })).status, 403);
  });
  await test('Anonymous account cannot be granted Admin by trusted procedure', async () => {
    await assert.rejects(changeAdminClaim({ auth, db, uid: visitor.localId, action: 'grant', operator: 'trusted-local-test', reason: 'test', apply: true,
      confirmation: `${project}:${visitor.localId}:grant` }));
    // Defense in depth even if another trusted tool accidentally sets the claim.
    await auth.setCustomUserClaims(visitor.localId, { admin: true });
    const response = await fetch('http://127.0.0.1:9097/securetoken.googleapis.com/v1/token?key=demo-key', { method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: visitor.refreshToken }) });
    assert.equal(response.status, 200);
    const token = (await response.json()).id_token;
    assert.equal(await write(token), 403);
    const decoded = await auth.verifyIdToken(token);
    assert.throws(() => requireAdmin({ uid: decoded.uid, token: decoded }));
  });
  await test('Revocation immediately denies old token in Rules and server, and denies renewed tokens', async () => {
    await new Promise(resolve => setTimeout(resolve, 1100));
    await change('revoke');
    assert.equal((await auth.getUser(user.localId)).customClaims?.admin, undefined);
    await assert.rejects(auth.verifyIdToken(adminToken, true), error => error.code === 'auth/id-token-revoked');
    // The centralized state now blocks the original token, before expiry.
    assert.equal(await write(adminToken), 403);
    const rejected = await callable(adminToken);
    assert.ok(['UNAUTHENTICATED', 'PERMISSION_DENIED', 'UNAVAILABLE'].includes(rejected.body.error.status));
    const decoded = adminDecoded;
    const { verifyAdminState } = await import('../../workers/image-upload/src/admin-state.js');
    assert.equal(await verifyAdminState({ uid: user.localId, token: decoded }, adminToken, 'tudo-aqui-macacu',
      (_url, options) => fetch(`${root}/admin_authorizations/${user.localId}`, options)), false);
    assert.equal(await authorizeCurrentAdmin({ uid: user.localId, token: decoded }, { db }), false);
    await assert.rejects(uploadHomeImage({ auth: { uid: user.localId, token: decoded } }, { authorize: a => authorizeCurrentAdmin(a, { db }) }), { code: 'permission-denied' });
    assert.equal((await fetch(`${root}/private_notifications/${run}`, { headers: headers(adminToken) })).status, 403);
    const fresh = await authCall('accounts:signInWithPassword', { email: user.email, password: 'LocalOnly123!', returnSecureToken: true });
    assert.equal((await auth.verifyIdToken(fresh.idToken)).admin, undefined);
    assert.equal(await write(fresh.idToken), 403);
    assert.throws(() => requireAdmin({ uid: user.localId, token: {} }));
    const audit = await db.collection('admin_claim_changes').where('uid', '==', user.localId).get();
    assert.equal(audit.docs.filter(d => d.get('status') === 'applied').length, 2);
  });
  await test('Regrant cannot resurrect old token; missing state and client state mutation fail closed', async () => {
    await change('grant');
    assert.equal(await write(adminToken), 403);
    const fresh = await authCall('accounts:signInWithPassword', { email: user.email, password: 'LocalOnly123!', returnSecureToken: true });
    assert.equal(await write(fresh.idToken), 200);
    assert.equal(await write(fresh.idToken, 'admin_authorizations', { enabled: { booleanValue: true } }), 403);
    const state = db.collection('admin_authorizations').doc(user.localId);
    await state.delete();
    assert.equal(await write(fresh.idToken), 403);
  });
  console.log(`Admin claims emulator: ${passed} passed. Production untouched; stale administrative token denied by current state.`);
}
main().catch(error => { console.error(error.message); process.exitCode = 1; })
  .finally(async () => { for (const uid of created) await auth.deleteUser(uid); await admin.app().delete(); });
