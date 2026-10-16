'use strict';

// Disposable integration harness for the demo Firebase Emulator only.
// It writes and removes only UUID-scoped fixtures created by this run.
const crypto = require('node:crypto');
const net = require('node:net');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');

let stage = 'environment preflight';
let user;
let admin;
let fixturesOwned = false;
let emulatorEnvironment;
let project;
let authHost;
let firestoreHost;
let functionsPort;
let fixtureUserId;

function check(condition, label) {
  if (!condition) throw new Error(`Assertion failed: ${label}`);
}

async function assertOpen(hostPort, label) {
  const [host, rawPort] = hostPort.split(':');
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host, port: Number(rawPort) });
    socket.setTimeout(1500);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('timeout', () => { socket.destroy(); reject(new Error(`${label} unavailable`)); });
    socket.once('error', () => reject(new Error(`${label} unavailable`)));
  });
}

const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForIndex(db, indexId, expectedExists) {
  const deadline = Date.now() + 30000;
  const ref = db.collection('business_search_index').doc(indexId);
  while (Date.now() < deadline) {
    if ((await ref.get()).exists === expectedExists) return;
    await pause(200);
  }
  throw new Error(`Timed out waiting for the expected fixture index state`);
}

async function deleteTemporaryUserAndVerify(uid) {
  try {
    await admin.auth().deleteUser(uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
  try {
    await admin.auth().getUser(uid);
    throw new Error('Temporary Auth fixture still exists');
  } catch (error) {
    if (error.code !== 'auth/user-not-found') throw error;
  }
}

function appCheckFixture() {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none' })}.${encode({ sub: 'demo-local-app',
    exp: Math.floor(Date.now() / 1000) + 300 })}.`;
}

async function callDetail(url, id, { authenticated = true, appCheck = true,
  invalidAppCheck = false, resetRate = true } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (authenticated) headers.Authorization = `Bearer ${user.idToken}`;
  if (appCheck) headers['X-Firebase-AppCheck'] = invalidAppCheck ? 'invalid-test-token' : appCheckFixture();
  if (resetRate) {
    const key = crypto.createHash('sha256').update(`jobs-detail:${user.localId}`).digest('hex');
    await admin.firestore().collection('business_search_rate_limits').doc(key).delete();
  }
  const response = await fetch(url, { method: 'POST', headers,
    body: JSON.stringify({ data: { id } }) });
  let body;
  try { body = await response.json(); } catch (_) { body = null; }
  return { status: response.status, body };
}

async function main() {
  emulatorEnvironment = readDemoEmulatorEnvironment();
  project = emulatorEnvironment.project;
  authHost = emulatorEnvironment.authHost;
  firestoreHost = emulatorEnvironment.firestoreHost;
  functionsPort = emulatorEnvironment.functionsPort;

  await Promise.all([
    assertOpen(authHost, 'Auth Emulator'),
    assertOpen(firestoreHost, 'Firestore Emulator'),
    assertOpen(`127.0.0.1:${functionsPort}`, 'Functions Emulator'),
  ]);

  const token = crypto.randomUUID();
  const ids = {
    published: `public-job-${token}`,
    unpublished: `unpublished-job-${token}`,
    inactive: `inactive-job-${token}`,
    expired: `expired-job-${token}`,
  };
  const dbRefs = Object.values(ids).map((id) => admin.firestore().collection('jobs').doc(id));
  const privateRef = admin.firestore().collection('job_private').doc(ids.published);
  const rateRef = () => admin.firestore().collection('business_search_rate_limits').doc(
    crypto.createHash('sha256').update(`jobs-detail:${fixtureUserId}`).digest('hex'));
  const indexIds = Object.values(ids).map((id) => `jobs__${id}`);
  const detailUrl = `${emulatorEnvironment.functionsOrigin}/${project}/southamerica-east1/getPublicJob`;

  try {
    stage = 'temporary Auth fixture';
    const signup = await fetch(`http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo-key`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    });
    check(signup.ok, 'Auth Emulator must create a temporary user');
    user = await signup.json();
    check(typeof user.localId === 'string' && typeof user.idToken === 'string',
      'Auth Emulator response must contain a temporary identity');
    fixtureUserId = user.localId;

    stage = 'UUID-scoped Firestore fixtures';
    const existing = await Promise.all([
      ...dbRefs.map((ref) => ref.get()),
      privateRef.get(),
      ...indexIds.map((id) => admin.firestore().collection('business_search_index').doc(id).get()),
      rateRef().get(),
    ]);
    check(existing.every((snapshot) => !snapshot.exists),
      'generated fixture IDs must not already exist');
    const now = Date.now();
    const publicJob = {
      published: true,
      active: true,
      expiresAt: admin.firestore.Timestamp.fromMillis(now + 86400000),
      title: `Vaga pública fictícia ${token}`,
      description: `Descrição pública de teste ${token}`,
      category: 'Serviços',
      location: 'Centro',
      company: 'Empresa Fictícia',
      employmentType: 'CLT',
      contact: `private-contact-${token}`,
      phone: `private-phone-${token}`,
      whatsapp: `private-whatsapp-${token}`,
      link: `private-link-${token}`,
      instagram: `private-instagram-${token}`,
      maps: `private-maps-${token}`,
      mapsUrl: `private-maps-url-${token}`,
      additionalInfo: `private-additional-${token}`,
      salary: `private-salary-${token}`,
      eventDate: `private-event-date-${token}`,
      date: `private-date-${token}`,
      unknownPrivateField: `private-unknown-${token}`,
    };
    // `create` makes fixture ownership atomic and collision-safe: if a UUID was
    // claimed after preflight, the batch fails instead of overwriting it.
    const fixtureBatch = admin.firestore().batch();
    fixtureBatch.create(dbRefs[0], publicJob);
    fixtureBatch.create(dbRefs[1], { ...publicJob, published: false });
    fixtureBatch.create(dbRefs[2], { ...publicJob, active: false });
    fixtureBatch.create(dbRefs[3], {
      ...publicJob,
      expiresAt: admin.firestore.Timestamp.fromMillis(now - 1000),
    });
    fixtureBatch.create(privateRef, { ...Object.fromEntries([
        'contact', 'phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo',
    ].map((field) => [field, `private-document-${field}-${token}`])) });
    fixtureBatch.create(rateRef(), { owner: token });
    await fixtureBatch.commit();
    // The cleanup guard becomes true only after this run's atomic create commits.
    fixturesOwned = true;
    await waitForIndex(admin.firestore(), `jobs__${ids.published}`, true);

    stage = 'valid public contract';
    const valid = await callDetail(detailUrl, ids.published);
    check(valid.status === 200 && valid.body?.result?.status === 'available',
      'published job must resolve');
    check(valid.body.result.id === ids.published, 'response must preserve original document ID');
    const expectedFields = ['title', 'description', 'category', 'location', 'company', 'employmentType'].sort();
    const actualFields = Object.keys(valid.body.result.data || {}).sort();
    check(JSON.stringify(actualFields) === JSON.stringify(expectedFields),
      'response must contain only the PublicJob allowlist');
    check(valid.body.result.data.title === publicJob.title &&
      valid.body.result.data.description === publicJob.description &&
      valid.body.result.data.company === publicJob.company,
    'response must preserve public contract values');
    const serialized = JSON.stringify(valid.body.result);
    for (const secret of Object.values(publicJob).filter((value) =>
      typeof value === 'string' && value.startsWith('private-'))) {
      check(!serialized.includes(secret), 'response must omit private and unapproved fixture values');
    }

    stage = 'hidden and missing documents';
    for (const id of [ids.unpublished, ids.inactive, ids.expired, `missing-job-${token}`]) {
      const response = await callDetail(detailUrl, id);
      check(response.status === 200 && response.body?.result?.status === 'unavailable',
        'missing or non-public job must be unavailable');
    }

    stage = 'invalid ID';
    check((await callDetail(detailUrl, '../invalid')).status !== 200,
      'invalid ID must be rejected');

    stage = 'missing Auth';
    check((await callDetail(detailUrl, ids.published, { authenticated: false })).status !== 200,
      'missing Auth must be rejected');

    stage = 'missing App Check';
    check((await callDetail(detailUrl, ids.published, { appCheck: false })).status !== 200,
      'missing App Check must be rejected');

    stage = 'invalid App Check';
    check((await callDetail(detailUrl, ids.published, { invalidAppCheck: true })).status !== 200,
      'invalid App Check must be rejected');

    stage = 'per-user detail quota';
    await rateRef().delete();
    let quotaRejected = false;
    // Exercise the callable with the same Auth identity so the test validates
    // the real per-UID rate key rather than assuming its storage key.
    for (let attempt = 0; attempt < 130; attempt++) {
      const response = await callDetail(detailUrl, ids.published, { resetRate: false });
      if (response.status !== 200) {
        check(response.body?.error?.status === 'RESOURCE_EXHAUSTED',
          'per-user quota must return RESOURCE_EXHAUSTED');
        quotaRejected = true;
        break;
      }
      await pause(250);
    }
    check(quotaRejected, 'per-user detail quota must reject repeated requests');

    stage = 'cleanup of UUID-scoped fixtures';
    await Promise.all([...dbRefs.map((ref) => ref.delete()), privateRef.delete(), rateRef().delete()]);
    await Promise.all(indexIds.map((id) => waitForIndex(admin.firestore(), id, false)));
    const remaining = await Promise.all([...dbRefs.map((ref) => ref.get()), privateRef.get(), rateRef().get(),
      ...indexIds.map((id) => admin.firestore().collection('business_search_index').doc(id).get())]);
    check(remaining.every((snapshot) => !snapshot.exists), 'all UUID-scoped source fixtures must be removed');
    if (user?.localId) await deleteTemporaryUserAndVerify(user.localId);
    user = null;
  } finally {
    // Cleanup is limited to this run's random IDs and temporary Auth identity.
    if (fixturesOwned) {
      const cleanup = await Promise.allSettled([
        ...dbRefs.map((ref) => ref.delete()),
        privateRef.delete(),
        rateRef().delete(),
      ]);
      if (cleanup.some((result) => result.status === 'rejected')) {
        console.error('Cleanup of UUID-scoped Firestore fixtures encountered an error.');
        process.exitCode = 1;
      } else {
        await Promise.all(indexIds.map((id) => waitForIndex(admin.firestore(), id, false)));
        const remaining = await Promise.all([
          ...dbRefs.map((ref) => ref.get()),
          privateRef.get(),
          rateRef().get(),
          ...indexIds.map((id) => admin.firestore().collection('business_search_index').doc(id).get()),
        ]);
        if (remaining.some((snapshot) => snapshot.exists)) {
          console.error('Cleanup verification found a remaining UUID-scoped Firestore fixture.');
          process.exitCode = 1;
        }
      }
    }
    if (fixtureUserId) {
      try {
        await deleteTemporaryUserAndVerify(fixtureUserId);
      } catch (_) {
        console.error('Cleanup of the temporary Auth fixture could not be verified.');
        process.exitCode = 1;
      }
    }
  }
  if (!process.exitCode) {
    console.log('getPublicJob Emulator integration passed: public contract, visibility, ID validation, Auth, App Check, quota, and fixture cleanup.');
  }
}

try {
  // Validate all mandatory boundaries before initializing Admin or writing fixtures.
  emulatorEnvironment = readDemoEmulatorEnvironment();
  project = emulatorEnvironment.project;
  authHost = emulatorEnvironment.authHost;
  firestoreHost = emulatorEnvironment.firestoreHost;
  functionsPort = emulatorEnvironment.functionsPort;
} catch (error) {
  console.error(`getPublicJob Emulator integration stopped at ${stage} (${error.name}).`);
  const frames = String(error.stack || '').split('\n').filter((line) => /^\s+at /.test(line)).slice(0, 6);
  if (frames.length) console.error(frames.join('\n'));
  process.exitCode = 1;
}

if (!process.exitCode) {
  // `main` rechecks all boundaries and emulator availability before any write.
  admin = require('firebase-admin');
  admin.initializeApp({ projectId: project });
  main().catch((error) => {
    console.error(`getPublicJob Emulator integration failed at ${stage} (${error.name}).`);
    const frames = String(error.stack || '').split('\n').filter((line) => /^\s+at /.test(line)).slice(0, 8);
    if (frames.length) console.error(frames.join('\n'));
    process.exitCode = 1;
  }).finally(() => admin.app().delete());
}
