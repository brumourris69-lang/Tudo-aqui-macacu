'use strict';

const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const { localOnly } = require('../business_search');
const { changeAdminClaim } = require('../admin_claim_management');

const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
assert.equal(localOnly(), true);

const adminSdk = require('firebase-admin');
adminSdk.initializeApp({ projectId: project });
const db = adminSdk.firestore();
const auth = adminSdk.auth();
const documents = `http://127.0.0.1:8087/v1/projects/${project}/databases/(default)/documents`;
const authApi = 'http://127.0.0.1:9097/identitytoolkit.googleapis.com/v1';
const run = `job-private-${randomUUID()}`;
const createdUsers = [];
const headers = token => ({ 'content-type': 'application/json',
  ...(token ? { authorization: `Bearer ${token}` } : {}) });

async function authRequest(endpoint, body) {
  const response = await fetch(`${authApi}/${endpoint}?key=demo-key`, {
    method: 'POST', headers: headers(), body: JSON.stringify(body),
  });
  assert.equal(response.status, 200, `local Auth ${endpoint}`);
  return response.json();
}

async function createAccount(label, anonymous = false) {
  const email = `${run}-${label}@example.invalid`;
  const password = `Test-${randomUUID()}-aA9!`;
  const user = await authRequest('accounts:signUp', anonymous
    ? { returnSecureToken: true }
    : { email, password, returnSecureToken: true });
  createdUsers.push(user.localId);
  return { ...user, email, password };
}

async function signIn(account) {
  return authRequest('accounts:signInWithPassword', {
    email: account.email, password: account.password, returnSecureToken: true,
  });
}

async function readPrivate(id, token) {
  return fetch(`${documents}/job_private/${id}`, { headers: headers(token) });
}

async function readJob(id, token) {
  return fetch(`${documents}/jobs/${id}`, { headers: headers(token) });
}

async function listJobs(token) {
  return fetch(`${documents}:runQuery`, {
    method: 'POST', headers: headers(token),
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'jobs' }], limit: 100 } }),
  });
}

async function writeJob(id, token, fields) {
  const typed = Object.fromEntries(Object.entries(fields).map(([key, value]) => [key,
    typeof value === 'boolean' ? { booleanValue: value } : { stringValue: value }]));
  return fetch(`${documents}/jobs/${id}`, {
    method: 'PATCH', headers: headers(token), body: JSON.stringify({ fields: typed }),
  });
}

async function deleteJob(id, token) {
  return fetch(`${documents}/jobs/${id}`, { method: 'DELETE', headers: headers(token) });
}

async function writePrivate(id, token, fields) {
  const typed = Object.fromEntries(Object.entries(fields).map(([key, value]) => [key,
    typeof value === 'boolean' ? { booleanValue: value } : { stringValue: value }]));
  return fetch(`${documents}/job_private/${id}`, {
    method: 'PATCH', headers: headers(token), body: JSON.stringify({ fields: typed }),
  });
}

async function test(name, body) {
  await body();
  console.log(`PASS ${name}`);
}

async function main() {
  const ordinary = await createAccount('ordinary');
  const anonymous = await createAccount('anonymous', true);
  const adminAccount = await createAccount('admin');
  const adminUid = adminAccount.localId;

  await db.collection('jobs').doc(run).set({ title: 'Vaga fictícia publicada', published: true });
  await db.collection('events').doc(run).set({ title: 'Evento público fictício', published: true });
  await db.collection('job_private').doc(run).set({
    contact: 'private-contact@example.invalid', administrativeNotes: 'Fictício', published: true,
  });

  await test('Unauthenticated, ordinary and anonymous users cannot read private job data', async () => {
    for (const token of [undefined, ordinary.idToken, anonymous.idToken]) {
      const response = await readPrivate(run, token);
      assert.equal(response.status, 403);
    }
  });

  await test('Publishing a public job does not grant access to its private document', async () => {
    assert.equal((await db.collection('jobs').doc(run).get()).get('published'), true);
    assert.equal((await readPrivate(run, ordinary.idToken)).status, 403);
    assert.equal((await readPrivate(run, anonymous.idToken)).status, 403);
  });

  await test('Visitors, ordinary users and anonymous users cannot directly get public jobs', async () => {
    for (const token of [undefined, ordinary.idToken, anonymous.idToken]) {
      assert.equal((await readJob(run, token)).status, 403);
    }
    // A separate public collection still works; the jobs denial is not a
    // broad denial of public content and cannot be bypassed by the wildcard.
    assert.equal((await fetch(`${documents}/events/${run}`, {
      headers: headers(ordinary.idToken),
    })).status, 200);
  });

  await test('Ordinary users cannot list jobs or write a vacancy directly', async () => {
    assert.equal((await listJobs(ordinary.idToken)).status, 403);
    assert.equal((await writeJob(`${run}-ordinary-write`, ordinary.idToken, {
      title: 'Vaga não autorizada', published: true,
    })).status, 403);
  });

  await test('Admin claim with centrally revoked authorization cannot read private job data', async () => {
    await changeAdminClaim({ auth, db, uid: adminUid, action: 'grant', operator: 'local-test',
      reason: 'Fictional Emulator test', apply: true,
      confirmation: `${project}:${adminUid}:grant` });
    const signedInAdmin = await signIn(adminAccount);
    const state = db.collection('admin_authorizations').doc(adminUid);
    const current = (await state.get()).data();
    await state.update({ enabled: false });
    assert.equal((await readPrivate(run, signedInAdmin.idToken)).status, 403);
    assert.equal((await readJob(run, signedInAdmin.idToken)).status, 403);
    assert.equal((await listJobs(signedInAdmin.idToken)).status, 403);
    assert.equal((await writeJob(`${run}-revoked-write`, signedInAdmin.idToken, {
      title: 'Vaga após revogação', published: true,
    })).status, 403);
    await state.set(current);
  });

  let authorizedAdminToken;
  await test('Currently authorized Admin can read and write private job data', async () => {
    const signedInAdmin = await signIn(adminAccount);
    authorizedAdminToken = signedInAdmin.idToken;
    const readResponse = await readPrivate(run, authorizedAdminToken);
    assert.equal(readResponse.status, 200);
    assert.match(await readResponse.text(), /private-contact@example\.invalid/);

    const writeResponse = await writePrivate(`${run}-admin-write`, authorizedAdminToken, {
      contact: 'admin-only@example.invalid', administrativeNotes: 'Local fictional record',
    });
    assert.equal(writeResponse.status, 200);
  });

  await test('Currently authorized Admin can get, list, create, update and delete jobs', async () => {
    const signedInAdmin = await signIn(adminAccount);
    authorizedAdminToken = signedInAdmin.idToken;
    assert.equal((await readJob(run, authorizedAdminToken)).status, 200);
    const listed = await listJobs(authorizedAdminToken);
    assert.equal(listed.status, 200);
    assert.match(await listed.text(), new RegExp(run));

    const createdId = `${run}-admin-crud`;
    assert.equal((await writeJob(createdId, authorizedAdminToken, {
      title: 'Vaga Admin fictícia', published: true,
    })).status, 200);
    assert.equal((await writeJob(createdId, authorizedAdminToken, {
      title: 'Vaga Admin atualizada', published: true,
    })).status, 200);
    assert.equal((await deleteJob(createdId, authorizedAdminToken)).status, 200);
    assert.equal((await readJob(createdId, authorizedAdminToken)).status, 404);
  });

  await test('Ordinary and anonymous users cannot write private job data', async () => {
    for (const token of [ordinary.idToken, anonymous.idToken]) {
      const response = await writePrivate(`${run}-denied-${randomUUID()}`, token, {
        contact: 'not-authorized@example.invalid',
      });
      assert.equal(response.status, 403);
    }
  });

  await test('No broad public match grants access to job_private documents', async () => {
    const privateResponse = await readPrivate(run, ordinary.idToken);
    const missingResponse = await readPrivate(`${run}-not-created`, ordinary.idToken);
    assert.equal(privateResponse.status, 403);
    assert.equal(missingResponse.status, 403);
  });

  const written = await db.collection('job_private').doc(`${run}-admin-write`).get();
  assert.equal(written.get('contact'), 'admin-only@example.invalid');
  console.log('Jobs and job_private Rules Emulator groups passed; demo-only fixtures.');
}

main().catch(error => {
  console.error(error.message);
  process.exitCode = 1;
}).finally(async () => {
  await Promise.all([
    db.collection('jobs').doc(run).delete(),
    db.collection('jobs').doc(`${run}-admin-write`).delete(),
    db.collection('jobs').doc(`${run}-ordinary-write`).delete(),
    db.collection('jobs').doc(`${run}-revoked-write`).delete(),
    db.collection('events').doc(run).delete(),
    db.collection('job_private').doc(run).delete(),
    db.collection('job_private').doc(`${run}-admin-write`).delete(),
  ].map(operation => operation.catch(() => {})));
  for (const uid of createdUsers) await auth.deleteUser(uid).catch(() => {});
  await adminSdk.app().delete().catch(() => {});
});
