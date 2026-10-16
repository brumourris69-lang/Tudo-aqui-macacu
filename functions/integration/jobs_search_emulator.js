'use strict';

// Additive integration test against only the persistent demo emulator. It
// writes unique fixtures and removes only those fixtures when it finishes.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const net = require('node:net');
const project = process.env.GCLOUD_PROJECT;
assert.equal(project, 'demo-universal-search', 'Refusing any Firebase project other than the local demo.');
assert.equal(process.env.FUNCTIONS_EMULATOR, 'true');
for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
  assert.match(process.env[key] || '', /^127\.0\.0\.1:\d+$/, `${key} must be loopback-only.`);
}
const functionsPort = Number(process.env.FUNCTIONS_EMULATOR_PORT || 5007);
assert.equal(functionsPort, 5007, 'Unexpected Functions Emulator port.');

const admin = require('firebase-admin');
admin.initializeApp({ projectId: project });
const db = admin.firestore();
const { INDEX, RATE } = require('../business_search');
const token = crypto.randomBytes(6).toString('hex');
const jobIds = ['published', 'draft', 'inactive', 'expired'].map((part) => `job-${token}-${part}`);
const businessId = `business-job-${token}`;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const searchUrl = `http://127.0.0.1:${functionsPort}/${project}/southamerica-east1/searchBusinesses`;
const detailUrl = `http://127.0.0.1:${functionsPort}/${project}/southamerica-east1/getSearchJob`;
const firestoreRest = `http://${firestoreHost}/v1/projects/${project}/databases/(default)/documents`;
const authUrl = `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`;
let user;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function assertOpen(value, label) {
  const [host, rawPort] = value.split(':');
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host, port: Number(rawPort) });
    socket.setTimeout(1500);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('timeout', () => { socket.destroy(); reject(new Error(`${label} did not respond.`)); });
    socket.once('error', () => reject(new Error(`${label} is unavailable.`)));
  });
}
async function waitForIndex(id, predicate, label) {
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) {
    const snapshot = await db.collection(INDEX).doc(`jobs__${id}`).get();
    if (predicate(snapshot.exists ? snapshot.data() : null)) return;
    await pause(250);
  }
  throw new Error(`Timed out waiting for jobs index: ${label}`);
}
async function call(query, filter = 'jobs', limit = 20, cursor = null) {
  const rateKey = crypto.createHash('sha256').update(user.localId).digest('hex');
  await db.collection(RATE).doc(rateKey).delete();
  const appCheck = `${Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url')}.` +
    `${Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 300 })).toString('base64url')}.`;
  const response = await fetch(searchUrl, { method: 'POST', headers: {
    'Content-Type': 'application/json', Authorization: `Bearer ${user.idToken}`,
    'X-Firebase-AppCheck': appCheck,
  }, body: JSON.stringify({ data: { query, filter, limit, ...(cursor ? { cursor } : {}) } }) });
  return { status: response.status, body: await response.json() };
}
async function callDetail(id, { authenticated = true, appCheckEnabled = true, invalidAppCheck = false,
  resetRate = true } = {}) {
  const rateKey = crypto.createHash('sha256').update(`jobs-detail:${user.localId}`).digest('hex');
  if (resetRate) await db.collection(RATE).doc(rateKey).delete();
  const appCheck = `${Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url')}.` +
    `${Buffer.from(JSON.stringify({ sub: 'demo-local-app', exp: Math.floor(Date.now() / 1000) + 300 })).toString('base64url')}.`;
  const headers = { 'Content-Type': 'application/json' };
  if (authenticated) headers.Authorization = `Bearer ${user.idToken}`;
  if (appCheckEnabled) headers['X-Firebase-AppCheck'] = invalidAppCheck ? 'invalid-app-check-token' : appCheck;
  const response = await fetch(detailUrl, { method: 'POST', headers,
    body: JSON.stringify({ data: { id } }) });
  return { status: response.status, body: await response.json() };
}
async function until(predicate, label) {
  const deadline = Date.now() + 45000;
  while (Date.now() < deadline) { if (await predicate()) return; await pause(250); }
  throw new Error(`Timed out waiting for ${label}`);
}
async function main() {
  await Promise.all([assertOpen(authHost, 'Auth Emulator'), assertOpen(firestoreHost, 'Firestore Emulator'),
    assertOpen(`127.0.0.1:${functionsPort}`, 'Functions Emulator')]);
  const signup = await fetch(authUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ returnSecureToken: true }) });
  assert.equal(signup.status, 200, 'Auth Emulator should create a temporary visitor.');
  user = await signup.json();

  const jobBase = { published: true, title: `Vaga Técnica Fictícia ${token}`,
    description: `Oportunidade de manutenção para teste ${token}`,
    company: 'Empresa Exemplo', location: 'Centro', employmentType: 'CLT',
    contact: 'private@example.invalid', applicationDeadline: admin.firestore.Timestamp.fromMillis(Date.now() - 86400000),
    privateNotes: 'MUST_NOT_BE_RETURNED' };
  const jobRefs = jobIds.map((id) => db.collection('jobs').doc(id));
  const indexRefs = jobIds.map((id) => db.collection(INDEX).doc(`jobs__${id}`));
  const businessRef = db.collection('establishments').doc(businessId);
  const businessIndexRef = db.collection(INDEX).doc(`establishments__${businessId}`);
  try {
    await Promise.all([
      jobRefs[0].set(jobBase),
      jobRefs[1].set({ ...jobBase, published: false, title: `Vaga Rascunho ${token}` }),
      jobRefs[2].set({ ...jobBase, active: false, title: `Vaga Inativa ${token}` }),
      jobRefs[3].set({ ...jobBase, expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
        title: `Vaga Expirada ${token}` }),
      businessRef.set({ published: true, name: `Vaga Fictícia ${token}`, category: 'Serviços' }),
    ]);
    await Promise.all(jobIds.slice(1).map((id) => waitForIndex(id, (value) => value === null, id)));
    await waitForIndex(jobIds[0], (value) => value?.title === jobBase.title, 'published job');
    await until(async () => (await businessIndexRef.get()).exists, 'business fixture index');

    let result = await call('tecnica', 'jobs');
    assert.equal(result.status, 200, JSON.stringify(result.body));
    let jobs = result.body.result.results;
    assert.deepEqual(jobs.map((item) => item.id), [jobIds[0]]);
    assert.equal(jobs[0].sourceCollection, 'jobs');
    assert.equal(jobs[0].company, 'Empresa Exemplo');
    assert.equal(jobs[0].employmentType, 'CLT');
    assert.equal(JSON.stringify(jobs[0]).includes('private@example.invalid'), false);
    assert.equal(JSON.stringify(jobs[0]).includes('MUST_NOT_BE_RETURNED'), false);
    assert.equal(JSON.stringify(jobs[0]).includes('applicationDeadline'), false);
    const detail = await callDetail(jobIds[0]);
    assert.equal(detail.status, 200, JSON.stringify(detail.body));
    assert.equal(detail.body.result.status, 'available');
    assert.equal(detail.body.result.id, jobIds[0]);
    assert.equal(detail.body.result.data.title, jobBase.title);
    assert.equal(detail.body.result.data.description, jobBase.description);
    assert.equal(detail.body.result.data.company, jobBase.company);
    assert.equal(detail.body.result.data.location, jobBase.location);
    assert.equal(detail.body.result.data.employmentType, jobBase.employmentType);
    assert.equal(JSON.stringify(detail.body.result).includes('contact'), false);
    assert.equal(JSON.stringify(detail.body.result).includes('private@example.invalid'), false);
    assert.equal(JSON.stringify(detail.body.result).includes('MUST_NOT_BE_RETURNED'), false);
    assert.equal(JSON.stringify(detail.body.result).includes('applicationDeadline'), false);
    for (const id of jobIds.slice(1)) {
      const unavailable = await callDetail(id);
      assert.equal(unavailable.status, 200, JSON.stringify(unavailable.body));
      assert.deepEqual(unavailable.body.result, { status: 'unavailable' });
    }
    const missing = await callDetail(`job-missing-${token}`);
    assert.deepEqual(missing.body.result, { status: 'unavailable' });
    assert.notEqual((await callDetail('../invalid')).status, 200);
    assert.notEqual((await callDetail(jobIds[0], { authenticated: false })).status, 200);
    assert.notEqual((await callDetail(jobIds[0], { appCheckEnabled: false })).status, 200);
    assert.notEqual((await callDetail(jobIds[0], { invalidAppCheck: true })).status, 200);
    const detailRateKey = crypto.createHash('sha256').update(`jobs-detail:${user.localId}`).digest('hex');
    await db.collection(RATE).doc(detailRateKey).set({ minute: Math.floor(Date.now() / 60000),
      count: 60, lastAt: Date.now() - 1000 });
    assert.notEqual((await callDetail(jobIds[0], { resetRate: false })).status, 200,
      'The detail callable must enforce the per-UID quota.');
    await db.collection(RATE).doc(detailRateKey).delete();
    const directIndex = await fetch(`${firestoreRest}/${INDEX}/jobs__${jobIds[0]}`, {
      headers: { Authorization: `Bearer ${user.idToken}` },
    });
    assert.equal(directIndex.status, 403, 'A visitor cannot read the private search index directly.');
    const allFirst = await call(`vaga ficticia ${token}`, 'all', 1);
    assert.equal(allFirst.status, 200, JSON.stringify(allFirst.body));
    assert.equal(allFirst.body.result.results[0].sourceCollection, 'establishments');
    const allSecond = await call(`vaga ficticia ${token}`, 'all', 1, allFirst.body.result.nextCursor);
    assert.equal(allSecond.status, 200, JSON.stringify(allSecond.body));
    assert.equal(allSecond.body.result.results[0].sourceCollection, 'jobs');
    assert.equal(allSecond.body.result.results[0].id, jobIds[0]);

    const badCursor = await call('tecnica', 'jobs', 10,
      { queryKey: `jobs:tecnica`, lastIndexId: `events__${token}` });
    assert.equal(badCursor.status, 400);

    await jobRefs[0].update({ title: `Vaga Atualizada ${token}`, employmentType: 'Temporário' });
    await waitForIndex(jobIds[0], (value) => value?.title === `Vaga Atualizada ${token}`,
      'updated job projection');
    jobs = (await call('atualizada', 'jobs')).body.result.results;
    assert.equal(jobs.length, 1);
    assert.equal(jobs[0].employmentType, 'Temporário');
    await jobRefs[0].delete();
    await waitForIndex(jobIds[0], (value) => value === null, 'deleted job projection');
    assert.equal((await call('atualizada', 'jobs')).body.result.results.length, 0);
    console.log('Jobs Emulator integration passed: indexing, secure detail, eligibility, contact privacy, accents/prefix, filters, pagination, update/delete and cursor validation.');
  } finally {
    await Promise.all([...jobRefs.map((ref) => ref.delete().catch(() => {})), businessRef.delete().catch(() => {}),
      ...indexRefs.map((ref) => ref.delete().catch(() => {})), businessIndexRef.delete().catch(() => {})]);
    if (user?.localId) await admin.auth().deleteUser(user.localId).catch(() => {});
    const rateKey = user?.localId && crypto.createHash('sha256').update(user.localId).digest('hex');
    if (rateKey) await db.collection(RATE).doc(rateKey).delete().catch(() => {});
    const detailRateKey = user?.localId && crypto.createHash('sha256').update(`jobs-detail:${user.localId}`).digest('hex');
    if (detailRateKey) await db.collection(RATE).doc(detailRateKey).delete().catch(() => {});
  }
}
main().catch((error) => { console.error(error.message); process.exitCode = 1; }).finally(() => admin.app().delete());
