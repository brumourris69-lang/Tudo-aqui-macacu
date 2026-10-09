'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search');
assert.equal(process.env.FUNCTIONS_EMULATOR, 'true');
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST'])
  assert.match(process.env[key] || '', /^127\.0\.0\.1:\d+$/);
const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { initializeApp, deleteApp } = require('firebase/app');
const { initializeAuth, inMemoryPersistence, connectAuthEmulator, signInAnonymously,
  createUserWithEmailAndPassword, signInWithEmailAndPassword, signInWithCredential,
  GoogleAuthProvider, signOut, onAuthStateChanged } = require('firebase/auth');
const client = initializeApp({ apiKey: 'demo-key', projectId: project, appId: 'demo-app' }, 'auth-integration');
const auth = initializeAuth(client, { persistence: inMemoryPersistence });
connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
const { createSearchBackend } = require('../business_search');
const { createFirestoreStore } = require('../business_search_firestore');
const { requireAdmin } = require('../home_image_upload');
const base = `http://127.0.0.1:5007/${project}/southamerica-east1/searchBusinesses`;
const requireAppCheck = process.env.LOCAL_SEARCH_REQUIRE_APP_CHECK !== 'false';
const rest = `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents`;
const run = Date.now().toString();
const id = `auth-${run}`;
const word = `authtest${run}`;
const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const appToken = `${encode({ alg: 'none' })}.${encode({ sub: 'demo-local-app', exp: Math.floor(Date.now()/1000)+3600 })}.`;
let passed = 0;
async function test(name, body) { await body(); console.log('PASS', name); passed++; }
async function call({ token, app = appToken } = {}) {
  // Reset only the fictional current test account's private local rate counter.
  if (auth.currentUser) await db.collection('business_search_rate_limits')
    .doc(crypto.createHash('sha256').update(auth.currentUser.uid).digest('hex')).delete();
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (app) headers['X-Firebase-AppCheck'] = app;
  const response = await fetch(base, { method: 'POST', headers, body: JSON.stringify({ data: { query: word } }) });
  return { status: response.status, body: await response.json() };
}
async function write(path, fields, token) {
  return fetch(`${rest}/${path}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ fields }) });
}
async function createProfile(uid, email, token) {
  // Security 1D requires the full public schema and server timestamps.
  return fetch(`${rest}:commit`, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ writes: [{
      update: { name: `projects/${project}/databases/(default)/documents/users/${uid}`,
        fields: { displayName: { stringValue: 'Local Auth Test' }, email: { stringValue: email },
          photoUrl: { stringValue: '' }, role: { stringValue: 'user' } } },
      updateTransforms: ['createdAt', 'updatedAt'].map(fieldPath => ({ fieldPath, setToServerValue: 'REQUEST_TIME' })),
    }] }),
  });
}
async function favorite(token) {
  const response = await fetch(`http://127.0.0.1:5007/${project}/southamerica-east1/submitUserOperation`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}`,
      'X-Firebase-AppCheck': appToken },
    body: JSON.stringify({ data: { operation: 'favorite', payload: { id, name: word } } }),
  });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).error, undefined);
}
async function main() {
  await db.collection('establishments').doc(id).set({ published: true, name: word, category: 'Tecnologia' });
  const backend = createSearchBackend({ store: createFirestoreStore(db, admin.firestore), isTimestamp: v => v instanceof admin.firestore.Timestamp });
  await backend.synchronize(id);
  await test('Auth SDK visitor signs in without profile/name/email/password', async () => {
    const result = await signInAnonymously(auth);
    assert.ok(result.user.isAnonymous); assert.equal(result.user.email, null);
    assert.equal((await db.collection('users').doc(result.user.uid).get()).exists, false);
  });
  const anonymousUid = auth.currentUser.uid;
  let anonymousToken = await auth.currentUser.getIdToken();
  await test('Reuse current anonymous session and refresh same UID', async () => {
    const ensure = async () => auth.currentUser || (await signInAnonymously(auth)).user;
    assert.equal((await ensure()).uid, anonymousUid);
    assert.equal((await admin.auth().verifyIdToken(await auth.currentUser.getIdToken(true))).uid, anonymousUid);
    anonymousToken = await auth.currentUser.getIdToken();
  });
  await test('Anonymous callable can search public result', async () => {
    const r = await call({ token: anonymousToken }); assert.equal(r.status, 200);
    assert.ok(r.body.result.results.some(v => v.id === id));
  });
  await test('Anonymous denied account/profile/favorites/device/review/vote/contact/proposal/Admin writes', async () => {
    const cases = [
      [`users/${anonymousUid}`, { role: { stringValue: 'user' } }],
      [`users/${anonymousUid}/favorites/a`, { id: { stringValue: 'a' }, name: { stringValue: 'a' } }],
      [`users/${anonymousUid}/devices/a`, { token: { stringValue: 'a' } }],
      ['reviews/a', { userId: { stringValue: anonymousUid }, status: { stringValue: 'pending' } }],
      [`polls/a/votes/${anonymousUid}`, { option: { stringValue: 'a' } }],
      ['contact_messages/a', { message: { stringValue: 'a' } }],
      ['business_proposals/a', { name: { stringValue: 'a' } }],
      ['metrics/a', { action: { stringValue: 'business_open' } }],
      ['establishments/forbidden', { name: { stringValue: 'a' }, published: { booleanValue: true } }],
      ['push_queue/a', { status: { stringValue: 'queued' } }],
    ];
    for (const [path, fields] of cases) assert.equal((await write(path, fields, anonymousToken)).status, 403, path);
  });
  await test('Anonymous retains public reads; private index and account reads denied', async () => {
    for (const [path, status] of [[`establishments/${id}`, 200], [`business_search_index/establishments__${id}`, 403], [`users/${anonymousUid}`, 403]]) {
      assert.equal((await fetch(`${rest}/${path}`, { headers: { Authorization: `Bearer ${anonymousToken}` } })).status, status);
    }
  });
  await test('Forged administrative claim on anonymous token cannot administer/upload', async () => {
    await admin.auth().setCustomUserClaims(anonymousUid, { admin: true, role: 'admin' });
    const token = await auth.currentUser.getIdToken(true);
    assert.equal((await write('establishments/forbidden', { published: { booleanValue: true } }, token)).status, 403);
    const decoded = await admin.auth().verifyIdToken(token);
    assert.throws(() => requireAdmin({ uid: decoded.uid, token: decoded }), error => error.code === 'permission-denied');
  });
  const email = `email-${run}@example.invalid`;
  const password = 'LocalOnly123!';
  let registeredUid;
  await test('Visitor to email account: SDK changes UID and anonymous state', async () => {
    const r = await createUserWithEmailAndPassword(auth, email, password);
    registeredUid = r.user.uid; assert.equal(r.user.isAnonymous, false); assert.notEqual(registeredUid, anonymousUid);
  });
  await test('Registered partial profile and direct favorite writes remain denied by Security 1D', async () => {
    const token = await auth.currentUser.getIdToken();
    assert.equal((await write(`users/${registeredUid}`, { role: { stringValue: 'user' }, email: { stringValue: email } }, token)).status, 403);
    assert.equal((await write(`users/${registeredUid}/favorites/${id}`, { id: { stringValue: id }, name: { stringValue: word } }, token)).status, 403);
  });
  await test('Registered full profile and gateway favorites remain allowed by Security 1D', async () => {
    const token = await auth.currentUser.getIdToken();
    assert.equal((await createProfile(registeredUid, email, token)).status, 200);
    await favorite(token);
    assert.equal((await fetch(`${rest}/users/${registeredUid}/favorites/${id}`, {
      headers: { Authorization: `Bearer ${token}` },
    })).status, 200);
    assert.equal((await write('establishments/forbidden', { published: { booleanValue: true } }, token)).status, 403);
    const r = await call({ token }); assert.equal(r.status, 200);
    assert.ok(r.body.result.results.some(v => v.id === id));
  });
  await test('Real SDK logout emits null and next visitor has separate UID', async () => {
    const states = []; const unsubscribe = onAuthStateChanged(auth, user => states.push(user?.uid ?? null));
    await signOut(auth); assert.equal(auth.currentUser, null);
    await signInAnonymously(auth); assert.ok(auth.currentUser.isAnonymous); assert.notEqual(auth.currentUser.uid, registeredUid);
    await new Promise(resolve => setTimeout(resolve, 20)); unsubscribe(); assert.ok(states.includes(null));
  });
  await test('Login to existing email account preserves UID and favorites', async () => {
    await signInWithEmailAndPassword(auth, email, password);
    assert.equal(auth.currentUser.uid, registeredUid);
    assert.equal((await db.collection('users').doc(registeredUid).collection('favorites').doc(id).get()).exists, true);
  });
  await test('Google credential exchange against Auth Emulator only', async () => {
    await signOut(auth); await signInAnonymously(auth);
    const syntheticGoogle = `${encode({ alg: 'none' })}.${encode({ sub: `google-${run}`, email: `google-${run}@example.invalid`,
      email_verified: true, name: 'Local Google', iss: 'https://accounts.google.com', aud: 'demo-client', exp: Math.floor(Date.now()/1000)+3600 })}.`;
    const result = await signInWithCredential(auth, GoogleAuthProvider.credential(syntheticGoogle));
    assert.equal(result.user.isAnonymous, false);
    assert.ok(result.user.providerData.some(p => p.providerId === 'google.com'));
    assert.equal((await call({ token: await result.user.getIdToken() })).status, 200);
  });
  await test('Auth mandatory; App Check follows explicit local environment policy', async () => {
    const token = await auth.currentUser.getIdToken();
    for (const args of [{}, { token: 'invalid-token' }, ...(requireAppCheck ? [{ token, app: null }, { token, app: 'invalid-app' }] : [])]) {
      const r = await call(args); assert.ok(r.status >= 400); assert.equal(r.body.result, undefined);
      assert.ok(!JSON.stringify(r.body).includes('stack'));
    }
    if (!requireAppCheck) {
      const r = await call({ token, app: null });
      assert.equal(r.status, 200); assert.ok(r.body.result.results.some(v => v.id === id));
    }
  });
  await test('Explicit local no-App-Check policy still requires Auth and public eligibility', async () => {
    const key = crypto.createHash('sha256').update(anonymousUid).digest('hex');
    await db.collection('business_search_rate_limits').doc(key).delete();
    const local = createSearchBackend({ store: createFirestoreStore(db, admin.firestore),
      isTimestamp: v => v instanceof admin.firestore.Timestamp, requireAppCheck: false });
    await assert.rejects(local.search({ data: { query: word } }), error => error.code === 'unauthenticated');
    const r = await local.search({ auth: { uid: anonymousUid }, data: { query: word } });
    assert.ok(r.results.some(v => v.id === id));
  });
  console.log(JSON.stringify({ project, requireAppCheck, realEmulatorGroupsPassed: passed,
    limits: ['in-memory client persistence; native disk persistence not tested', 'synthetic Google credential; no real OAuth',
      'emulator-only App Check fixture; no real attestation'] }, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(async () => {
  await signOut(auth); await deleteApp(client); await admin.app().delete();
});
