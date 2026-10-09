'use strict';
// Diagnostic regression driver for the current 1D contracts. Does not replace
// or hide the failing historical auth_emulator.js assertions.
const assert = require('node:assert/strict');
const { localOnly } = require('../business_search');
const { changeAdminClaim } = require('../admin_claim_management');
const { authorizeCurrentAdmin, currentAdminState } = require('../admin_authorization');
assert.equal(localOnly(), true);
assert.equal(process.env.GCLOUD_PROJECT, 'demo-universal-search');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'demo-universal-search' });
const db = admin.firestore();
const { initializeApp, deleteApp } = require('firebase/app');
const { initializeAuth, inMemoryPersistence, connectAuthEmulator, signInAnonymously,
  createUserWithEmailAndPassword, signInWithEmailAndPassword, signInWithCredential,
  GoogleAuthProvider, signOut, onAuthStateChanged } = require('firebase/auth');
const client = initializeApp({ apiKey: 'demo-key', projectId: 'demo-universal-search', appId: 'demo-app' }, 'security-2a');
const auth = initializeAuth(client, { persistence: inMemoryPersistence });
connectAuthEmulator(auth, 'http://127.0.0.1:9097', { disableWarnings: true });
const tag = `audit2a-${Date.now()}`, created = new Set();
const root = 'http://127.0.0.1:8087/v1/projects/demo-universal-search/databases/(default)/documents';
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const appToken = `${encode({ alg: 'none' })}.${encode({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
let passed = 0;
async function test(name, body) { await body(); passed++; console.log('PASS', name); }
async function call(name, data, token, app = appToken) {
  const response = await fetch(`http://127.0.0.1:5007/demo-universal-search/southamerica-east1/${name}`, {
    method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(app ? { 'X-Firebase-AppCheck': app } : {}) }, body: JSON.stringify({ data }) });
  return { status: response.status, body: await response.json() };
}
async function read(path, token) {
  return fetch(`${root}/${path}`, { headers: { authorization: `Bearer ${token}` } });
}
async function main() {
  await db.doc(`establishments/${tag}`).set({ name: tag, category: 'Tecnologia', published: true });
  const deadline = Date.now() + 15000;
  while (!(await db.doc(`business_search_index/establishments__${tag}`).get()).exists) {
    assert.ok(Date.now() < deadline, 'Local index trigger did not complete');
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  let visitor, registered;
  const email = `${tag}@example.invalid`, password = 'LocalOnly123!';
  await test('SDK visitor enters without profile and reuses the same Auth session', async () => {
    visitor = (await signInAnonymously(auth)).user; created.add(visitor.uid);
    assert.ok(visitor.isAnonymous); assert.equal(visitor.email, null);
    const ensure = async () => auth.currentUser || (await signInAnonymously(auth)).user;
    assert.equal((await ensure()).uid, visitor.uid);
    assert.equal((await db.doc(`users/${visitor.uid}`).get()).exists, false);
    const token = await visitor.getIdToken();
    assert.equal((await read(`establishments/${tag}`, token)).status, 200);
    const response = await call('searchBusinesses', { query: tag }, token);
    assert.equal(response.status, 200); assert.ok(response.body.result.results.some(v => v.id === tag));
    assert.notEqual((await call('submitUserOperation', { operation: 'favorite', payload: { id: tag, name: tag } }, token)).status, 200);
  });
  await test('Visitor switches to registered email account and creates profile with current schema', async () => {
    registered = (await createUserWithEmailAndPassword(auth, email, password)).user; created.add(registered.uid);
    assert.ok(!registered.isAnonymous); assert.notEqual(registered.uid, visitor.uid);
    const token = await registered.getIdToken();
    const response = await fetch(`${root}:commit`, { method: 'POST', headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ writes: [{ update: { name: `projects/demo-universal-search/databases/(default)/documents/users/${registered.uid}`,
        fields: { displayName: { stringValue: 'Fixture de auditoria' }, email: { stringValue: email }, photoUrl: { stringValue: '' }, role: { stringValue: 'user' } } },
        updateTransforms: ['createdAt', 'updatedAt'].map(fieldPath => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })) }] }) });
    assert.equal(response.status, 200);
    const favorite = await call('submitUserOperation', { operation: 'favorite', payload: { id: tag, name: tag } }, token);
    assert.equal(favorite.status, 200); assert.equal((await read(`users/${registered.uid}/favorites/${tag}`, token)).status, 200);
  });
  await test('SDK logout emits null; next guest has separate UID and cannot access registered favorites', async () => {
    const states = [], unsubscribe = onAuthStateChanged(auth, user => states.push(user?.uid ?? null));
    await signOut(auth); assert.equal(auth.currentUser, null);
    const next = (await signInAnonymously(auth)).user; created.add(next.uid);
    assert.notEqual(next.uid, registered.uid); assert.notEqual(next.uid, visitor.uid);
    await new Promise(resolve => setTimeout(resolve, 20)); unsubscribe(); assert.ok(states.includes(null));
    assert.equal((await read(`users/${registered.uid}/favorites/${tag}`, await next.getIdToken())).status, 403);
  });
  await test('Login to the existing email account restores original UID/profile and server favorites', async () => {
    const result = await signInWithEmailAndPassword(auth, email, password);
    assert.equal(result.user.uid, registered.uid);
    const token = await result.user.getIdToken();
    assert.equal((await read(`users/${registered.uid}`, token)).status, 200);
    assert.equal((await read(`users/${registered.uid}/favorites/${tag}`, token)).status, 200);
  });
  await test('Synthetic Google exchange is accepted only by Auth Emulator and yields registered provider', async () => {
    await signOut(auth);
    const synthetic = `${encode({ alg: 'none' })}.${encode({ sub: `google-${tag}`, email: `google-${tag}@example.invalid`, email_verified: true,
      name: 'Fixture Google', iss: 'https://accounts.google.com', aud: 'demo-client', exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
    const result = await signInWithCredential(auth, GoogleAuthProvider.credential(synthetic)); created.add(result.user.uid);
    assert.ok(!result.user.isAnonymous); assert.ok(result.user.providerData.some(p => p.providerId === 'google.com'));
    assert.equal((await call('searchBusinesses', { query: tag }, await result.user.getIdToken())).status, 200);
  });
  await test('Auth and App Check remain mandatory after account switching', async () => {
    const token = await auth.currentUser.getIdToken();
    for (const [idToken, app] of [[undefined, appToken], ['invalid-token', appToken], [token, null], [token, 'invalid-app']]) {
      const result = await call('searchBusinesses', { query: tag }, idToken, app);
      assert.notEqual(result.status, 200); assert.equal(result.body.result, undefined);
    }
  });
  await test('Known limitation: Auth-only revocation leaves Rules state enabled; managed revoke closes it', async () => {
    const operator = (await createUserWithEmailAndPassword(auth, `admin-${tag}@example.invalid`, password)).user;
    created.add(operator.uid);
    const mutate = action => changeAdminClaim({ auth: admin.auth(), db, uid: operator.uid, action,
      operator: 'security-2a-audit', reason: 'demo-only revocation diagnostic', apply: true,
      confirmation: `demo-universal-search:${operator.uid}:${action}` });
    await mutate('grant');
    const token = await operator.getIdToken(true), decoded = await admin.auth().verifyIdToken(token);
    await db.doc(`establishments/${tag}-restricted`).set({ published: false, name: 'Fixture restrita' });
    assert.equal((await read(`establishments/${tag}-restricted`, token)).status, 200);
    // Deliberately reproduce an out-of-band Auth action ONLY on this demo user.
    await new Promise(resolve => setTimeout(resolve, 1200));
    await admin.auth().revokeRefreshTokens(operator.uid);
    await assert.rejects(admin.auth().verifyIdToken(token, true), e => e.code === 'auth/id-token-revoked');
    await assert.rejects(authorizeCurrentAdmin({ uid: operator.uid, token: decoded }, {
      db, firebaseAuth: admin.auth(), rawToken: token,
    }), e => e.code === 'auth/id-token-revoked');
    const state = (await db.doc(`admin_authorizations/${operator.uid}`).get()).data();
    assert.equal(currentAdminState(decoded, state), true);
    assert.equal((await read(`establishments/${tag}-restricted`, token)).status, 200);
    await mutate('revoke');
    assert.equal((await read(`establishments/${tag}-restricted`, token)).status, 403);
  });
  console.log(`Integrated Auth audit: ${passed} scenarios passed; demo only; synthetic Google, memory persistence, no real attestation.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await signOut(auth); await deleteApp(client);
  for (const uid of created) await admin.auth().deleteUser(uid).catch(() => {});
  await db.terminate(); await admin.app().delete();
});
