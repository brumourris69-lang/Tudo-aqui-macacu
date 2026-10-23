'use strict';

// UUID-scoped integration coverage for manageAdminJob. It can connect only to
// the explicit demo Auth, Firestore, and Functions Emulators; cleanup deletes
// only fixtures created by this process.
const crypto = require('node:crypto');
const net = require('node:net');
const admin = require('firebase-admin');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');
const { changeAdminClaim } = require('../admin_claim_management');

let stage = 'environment preflight';
let cleanupStage = 'not started';
let env;
let project;
let db;
let auth;
let temporaryUsers = [];
let adminStateUid;
let claimAuditIds = [];
const ownedJobs = new Set();
const ownedPrivateJobs = new Set();
const ownedIndexes = new Set();
const ownedRateLimits = new Set();
const privateMarker = `private-${crypto.randomUUID()}`;
const runId = `admin-job-it-${crypto.randomUUID()}`;
const ids = {
  first: `${runId}-first`,
  second: `${runId}-second`,
  legacy: `${runId}-legacy`,
  orphan: `${runId}-orphan`,
  denied: `${runId}-denied`,
};

function check(condition, label) {
  if (!condition) throw new Error(`Assertion failed: ${label}`);
}

async function assertListening(hostPort, label) {
  const match = /^127\.0\.0\.1:(\d{1,5})$/.exec(hostPort || '');
  check(Boolean(match), `${label} must use explicit IPv4 loopback`);
  await new Promise((resolve, reject) => {
    const socket = net.connect({ host: '127.0.0.1', port: Number(match[1]) });
    socket.setTimeout(1500);
    socket.once('connect', () => { socket.destroy(); resolve(); });
    socket.once('timeout', () => { socket.destroy(); reject(new Error(`${label} unavailable`)); });
    socket.once('error', () => reject(new Error(`${label} unavailable`)));
  });
}

function appCheckToken() {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none' })}.${encode({ sub: 'demo-local-app',
    exp: Math.floor(Date.now() / 1000) + 300 })}.`;
}

async function callFunction(name, token, data, { appCheck = true } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (token) headers.authorization = `Bearer ${token}`;
  if (appCheck) headers['X-Firebase-AppCheck'] = appCheckToken();
  const response = await fetch(
    `${env.functionsOrigin}/${project}/southamerica-east1/${name}`,
    { method: 'POST', headers, body: JSON.stringify({ data }) },
  );
  let body = null;
  try { body = await response.json(); } catch (_) { /* sanitized below */ }
  return { status: response.status, body };
}

function success(response, status, label) {
  if (response.status !== 200 || response.body?.result?.status !== status) {
    const rawCode = response.body?.error?.status;
    const code = typeof rawCode === 'string' && /^[A-Z_]{1,40}$/.test(rawCode)
      ? rawCode : 'NO_CALLABLE_STATUS';
    const error = new Error('Sanitized callable assertion failed.');
    error.safeDiagnostic = `${label} (HTTP ${response.status}; callable ${code})`;
    throw error;
  }
  return response.body.result;
}

function rejected(response, label) {
  check(response.status !== 200 && typeof response.body?.error?.status === 'string', label);
  return response.body.error.status;
}

async function authRequest(endpoint, body) {
  const response = await fetch(
    `http://${env.authHost}/identitytoolkit.googleapis.com/v1/${endpoint}?key=demo-key`,
    { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) },
  );
  check(response.ok, `Auth Emulator ${endpoint} must accept a temporary fixture request`);
  return response.json();
}

async function createUser(label) {
  const email = `${runId}-${label}@example.invalid`;
  const password = `T-${crypto.randomUUID()}-aA9!`;
  const result = await authRequest('accounts:signUp', {
    email, password, returnSecureToken: true,
  });
  check(typeof result.localId === 'string' && typeof result.idToken === 'string',
    'Auth fixture response must contain a temporary account');
  temporaryUsers.push(result.localId);
  return { ...result, email, password };
}

async function signIn(user) {
  return authRequest('accounts:signInWithPassword', {
    email: user.email, password: user.password, returnSecureToken: true,
  });
}

async function waitForIndex(id, exists) {
  const ref = db.collection('business_search_index').doc(`jobs__${id}`);
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    if ((await ref.get()).exists === exists) return;
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error('Timed out waiting for UUID-scoped search index state');
}

async function grantAdmin(user) {
  adminStateUid = user.localId;
  const state = db.collection('admin_authorizations').doc(adminStateUid);
  check(!(await state.get()).exists, 'new Admin fixture must not collide with existing authorization');
  const result = await changeAdminClaim({
    auth, db, uid: adminStateUid, action: 'grant', operator: 'local-test',
    reason: 'Fictional integration fixture', apply: true,
    confirmation: `${project}:${adminStateUid}:grant`,
  });
  claimAuditIds.push(result.auditId);
  return signIn(user);
}

async function markIfCreated(id, expectedTitle, expectedContact) {
  const [publicSnapshot, privateSnapshot] = await Promise.all([
    db.collection('jobs').doc(id).get(),
    db.collection('job_private').doc(id).get(),
  ]);
  if (publicSnapshot.get('title') === expectedTitle &&
      privateSnapshot.get('contact') === expectedContact) {
    ownedJobs.add(id);
    ownedPrivateJobs.add(id);
    ownedIndexes.add(id);
    return true;
  }
  return false;
}

async function cleanup() {
  if (db) {
    cleanupStage = 'delete owned Firestore fixtures';
    const operations = [];
    for (const id of ownedJobs) operations.push(db.collection('jobs').doc(id).delete());
    for (const id of ownedPrivateJobs) operations.push(db.collection('job_private').doc(id).delete());
    for (const id of ownedRateLimits) operations.push(db.collection('public_content_rate_limits').doc(id).delete());
    for (const id of claimAuditIds) operations.push(db.collection('admin_claim_changes').doc(id).delete());
    if (adminStateUid) operations.push(db.collection('admin_authorizations').doc(adminStateUid).delete());
    const results = await Promise.allSettled(operations);
    if (results.some((result) => result.status === 'rejected')) {
      console.error('Fixture cleanup encountered an error.');
      process.exitCode = 1;
    }
    cleanupStage = 'verify derived search indexes';
    for (const id of ownedIndexes) {
      try { await waitForIndex(id, false); }
      catch (_) {
        // Indexes are derived fixtures. Delete only IDs whose source document
        // this run owned, then verify the exact generated index reference.
        await db.collection('business_search_index').doc(`jobs__${id}`).delete();
        const snapshot = await db.collection('business_search_index').doc(`jobs__${id}`).get();
        if (snapshot.exists) process.exitCode = 1;
      }
    }
    cleanupStage = 'verify owned Firestore documents';
    const remaining = await Promise.all([
      ...[...ownedJobs].map((id) => db.collection('jobs').doc(id).get()),
      ...[...ownedPrivateJobs].map((id) => db.collection('job_private').doc(id).get()),
      ...[...ownedRateLimits].map((id) => db.collection('public_content_rate_limits').doc(id).get()),
      ...claimAuditIds.map((id) => db.collection('admin_claim_changes').doc(id).get()),
      ...(adminStateUid ? [db.collection('admin_authorizations').doc(adminStateUid).get()] : []),
    ]);
    if (remaining.some((snapshot) => snapshot.exists)) {
      process.exitCode = 1;
      console.error('Fixture cleanup verification found a remaining UUID-scoped document.');
    }
  }
  if (auth) {
    cleanupStage = 'delete temporary Auth accounts';
    for (const uid of temporaryUsers) {
      try {
        await auth.deleteUser(uid);
        try { await auth.getUser(uid); process.exitCode = 1; console.error('Temporary Auth cleanup verification failed.'); }
        catch (error) { if (error.code !== 'auth/user-not-found') throw error; }
      }
      catch (error) { if (error.code !== 'auth/user-not-found') process.exitCode = 1; }
    }
  }
}

async function main() {
  env = readDemoEmulatorEnvironment();
  project = env.project;
  check(env.project === 'demo-universal-search', 'only demo-universal-search is permitted');
  check(/^127\.0\.0\.1:\d{1,5}$/.test(env.authHost), 'Auth Emulator must use an explicit loopback endpoint');
  await Promise.all([
    assertListening(env.authHost, 'Auth Emulator'),
    assertListening(env.firestoreHost, 'Firestore Emulator'),
    assertListening(env.functionsHost, 'Functions Emulator'),
  ]);
  const hubHost = process.env.DEMO_EMULATOR_HUB_HOST;
  check(/^127\.0\.0\.1:\d{1,5}$/.test(hubHost || ''), 'an explicit loopback Emulator Hub endpoint is required');
  const hubResponse = await fetch(`http://${hubHost}/emulators`);
  check(hubResponse.ok, 'the selected local Emulator Hub must respond');
  const hub = await hubResponse.json();
  for (const name of ['firestore', 'functions']) {
    check(hub[name]?.host === '127.0.0.1', `${name} must be loopback-bound`);
  }
  check(Number(hub.firestore.port) === Number(env.firestoreHost.split(':').at(-1)) &&
    Number(hub.functions.port) === env.functionsPort,
    'Emulator Hub ports must match the explicit demo endpoints');

  admin.initializeApp({ projectId: project });
  db = admin.firestore();
  auth = admin.auth();
  const allJobIds = [...new Set(Object.values(ids))];
  const preflight = await Promise.all([
    ...allJobIds.map((id) => db.collection('jobs').doc(id).get()),
    ...allJobIds.map((id) => db.collection('job_private').doc(id).get()),
    ...allJobIds.map((id) => db.collection('business_search_index').doc(`jobs__${id}`).get()),
  ]);
  check(preflight.every((snapshot) => !snapshot.exists), 'all generated fixture IDs must be unused');

  stage = 'temporary Auth fixtures';
  const ordinary = await createUser('ordinary');
  const adminUser = await createUser('admin');
  const anonymous = await authRequest('accounts:signUp', { returnSecureToken: true });
  check(typeof anonymous.localId === 'string' && typeof anonymous.idToken === 'string',
    'anonymous Auth fixture must be created');
  temporaryUsers.push(anonymous.localId);
  const ordinaryRateId = crypto.createHash('sha256').update(ordinary.localId).digest('hex');
  check(!(await db.collection('public_content_rate_limits').doc(ordinaryRateId).get()).exists,
    'temporary public-list rate fixture must not collide');
  ownedRateLimits.add(ordinaryRateId);

  stage = 'unauthenticated and missing App Check';
  const noAuth = await callFunction('manageAdminJob', null, { operation: 'list', pageSize: 1 });
  check(noAuth.status !== 200, 'manageAdminJob must reject unauthenticated callers');
  const noAppCheck = await callFunction('manageAdminJob', ordinary.idToken,
    { operation: 'list', pageSize: 1 }, { appCheck: false });
  check(noAppCheck.status !== 200, 'manageAdminJob must reject missing App Check');
  console.log('PASS Auth and App Check are required');

  stage = 'unprivileged operations';
  const deniedCalls = [
    ['list', { operation: 'list', pageSize: 1 }],
    ['get', { operation: 'get', jobId: ids.first }],
    ['create', { operation: 'create', jobId: ids.denied, publicData: { title: 'Denied' }, privateData: {} }],
    ['update', { operation: 'update', jobId: ids.first, publicData: { title: 'Denied' }, privateData: {} }],
    ['delete', { operation: 'delete', jobId: ids.first }],
  ];
  for (const [label, request] of deniedCalls) {
    const result = await callFunction('manageAdminJob', ordinary.idToken, request);
    check(result.status !== 200, `ordinary user must be denied ${label}`);
  }
  check(!(await db.collection('jobs').doc(ids.denied).get()).exists,
    'denied create must not create a public document');
  for (const token of [ordinary.idToken, anonymous.idToken]) {
    const get = await callFunction('manageAdminJob', token, { operation: 'get', jobId: ids.first });
    check(get.status !== 200, 'ordinary and anonymous users must not get administrative data');
  }
  console.log('PASS ordinary and anonymous callers cannot use any Admin operation');

  stage = 'authorized versioned Admin fixture';
  const adminToken = await grantAdmin(adminUser);
  const currentState = (await db.collection('admin_authorizations').doc(adminUser.localId).get()).data();
  check(currentState?.enabled === true && currentState.pending === false &&
    typeof currentState.version === 'string', 'Admin authorization state must be versioned and active');
  console.log('PASS versioned Admin authorization is established only for a temporary demo identity');

  stage = 'create and pair atomicity';
  const createPayload = {
    operation: 'create', jobId: ids.first,
    publicData: { title: `${runId} public`, description: 'Fictional integration fixture',
      category: 'Serviços', published: true, active: true },
    privateData: { contact: privateMarker, phone: `${privateMarker}-phone`,
      whatsapp: `${privateMarker}-whatsapp`, link: `${privateMarker}-link`,
      instagram: `${privateMarker}-instagram`, maps: `${privateMarker}-maps`,
      mapsUrl: `${privateMarker}-maps-url`, additionalInfo: `${privateMarker}-notes` },
  };
  let created;
  try {
    created = success(await callFunction('manageAdminJob', adminToken.idToken, createPayload), 'created',
      'Admin create must return positive acknowledgement');
  } catch (error) {
    await markIfCreated(ids.first, createPayload.publicData.title, privateMarker);
    throw error;
  }
  check(created.jobId === ids.first, 'created response must retain the supplied ID');
  check(await markIfCreated(ids.first, createPayload.publicData.title, privateMarker),
    'created fixture ownership must be confirmed by its unique payload');
  const pair = await Promise.all([
    db.collection('jobs').doc(ids.first).get(),
    db.collection('job_private').doc(ids.first).get(),
  ]);
  check(pair.every((snapshot) => snapshot.exists), 'create must persist both document halves');
  console.log('PASS create writes the paired public and private documents');

  stage = 'admin get and private projection';
  const got = success(await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'get', jobId: ids.first }), 'available', 'Admin get must return the existing pair');
  check(got.jobId === ids.first && got.privateData.contact === privateMarker &&
    Object.keys(got.privateData).length === 8, 'Admin get returns only the eight private fields');
  check(!Object.keys(got.publicData).some((key) => Object.hasOwn(got.privateData, key)),
    'public and private response fields must remain separated');
  console.log('PASS Admin get returns the authorized private projection');

  stage = 'pagination';
  const secondTitle = `${runId} second`;
  const secondContact = `${privateMarker}-second`;
  try {
    success(await callFunction('manageAdminJob', adminToken.idToken, {
      operation: 'create', jobId: ids.second,
      publicData: { title: secondTitle, published: false, active: true },
      privateData: { contact: secondContact },
    }), 'created', 'second Admin fixture must be created');
  } catch (error) {
    await markIfCreated(ids.second, secondTitle, secondContact);
    throw error;
  }
  check(await markIfCreated(ids.second, secondTitle, secondContact),
    'second fixture ownership must be confirmed by its unique payload');
  let cursor = null;
  const seen = new Set();
  let pages = 0;
  while (pages < 100) {
    const data = { operation: 'list', pageSize: 1, ...(cursor ? { cursor } : {}) };
    const page = success(await callFunction('manageAdminJob', adminToken.idToken, data), 'available',
      'Admin list must return a valid page');
    check(page.items.length <= 1, 'Admin page must respect its requested size');
    for (const item of page.items) {
      check(!seen.has(item.id), 'pagination must not repeat a document');
      seen.add(item.id);
      check(Object.keys(item).sort().join(',') === 'id,summary' &&
        Object.keys(item.summary).sort().join(',') === 'active,published,title',
      'Admin list must return summary fields only');
    }
    pages++;
    if (seen.has(ids.first) && seen.has(ids.second)) break;
    cursor = page.nextCursor;
    if (!cursor) break;
  }
  check(seen.has(ids.first) && seen.has(ids.second) && pages > 1,
    'both new records must be reachable on separate bounded pages');
  check(!JSON.stringify([...seen]).includes(privateMarker), 'Admin list must not expose private values');
  console.log('PASS bounded pagination is stable and list responses contain summaries only');

  stage = 'update preserves omitted private fields and explicit clearing';
  success(await callFunction('manageAdminJob', adminToken.idToken, {
    operation: 'update', jobId: ids.first,
    publicData: { title: `${runId} updated` }, privateData: { phone: '' },
  }), 'updated', 'Admin update must return positive acknowledgement');
  const updated = success(await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'get', jobId: ids.first }), 'available', 'updated record must remain readable');
  check(updated.publicData.title === `${runId} updated` &&
    updated.privateData.contact === privateMarker && updated.privateData.phone === '',
  'update must preserve omitted private fields and clear explicit blanks');
  console.log('PASS update preserves omitted private fields and clears explicit blanks');

  stage = 'public projection and direct Rules checks';
  const publicList = success(await callFunction('listPublicContent', ordinary.idToken, {
    collection: 'jobs', limit: 40,
  }), undefined, 'public listing callable must be available');
  check(Array.isArray(publicList.items), 'public listing must return items');
  const publicItem = publicList.items.find((item) => item.id === ids.first);
  check(Boolean(publicItem), 'published fixture must appear in public listing');
  check(!JSON.stringify(publicItem).includes(privateMarker),
    'public listing must not include administrative values');
  const firestoreRoot = `http://${env.firestoreHost}/v1/projects/${project}/databases/(default)/documents`;
  for (const token of [null, ordinary.idToken, anonymous.idToken]) {
    const headers = token ? { authorization: `Bearer ${token}` } : {};
    const publicRead = await fetch(`${firestoreRoot}/jobs/${ids.first}`, { headers });
    const privateRead = await fetch(`${firestoreRoot}/job_private/${ids.first}`, { headers });
    check(publicRead.status === 403 && privateRead.status === 403,
      'current local Rules must deny direct reads for visitors, ordinary and anonymous users');
  }
  console.log('PASS public job projection omits private data; current Rules deny direct reads to public identities');

  stage = 'paired deletion';
  success(await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'delete', jobId: ids.second }), 'deleted', 'Admin delete must acknowledge the paired record');
  const deletedPair = await Promise.all([
    db.collection('jobs').doc(ids.second).get(),
    db.collection('job_private').doc(ids.second).get(),
  ]);
  check(deletedPair.every((snapshot) => !snapshot.exists),
    'delete must remove both halves of the paired job');
  console.log('PASS delete removes both halves of the paired job');

  stage = 'legacy and collision behavior';
  try {
    await db.collection('jobs').doc(ids.legacy).create({
      title: `${runId} legacy`, published: true, active: true, unknownLegacyField: privateMarker,
    });
  } catch (error) {
    const existing = await db.collection('jobs').doc(ids.legacy).get();
    if (existing.get('title') === `${runId} legacy` && existing.get('unknownLegacyField') === privateMarker) {
      ownedJobs.add(ids.legacy);
      ownedIndexes.add(ids.legacy);
    }
    throw error;
  }
  ownedJobs.add(ids.legacy);
  ownedIndexes.add(ids.legacy);
  const legacyGet = await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'get', jobId: ids.legacy });
  check(rejected(legacyGet, 'legacy get must fail closed') === 'FAILED_PRECONDITION',
    'legacy record without private half must be identified');
  const legacyUpdate = await callFunction('manageAdminJob', adminToken.idToken, {
    operation: 'update', jobId: ids.legacy, publicData: { title: 'Must not change' }, privateData: {},
  });
  check(rejected(legacyUpdate, 'legacy update must fail closed') === 'FAILED_PRECONDITION',
    'legacy update must not create partial private state');
  check((await db.collection('jobs').doc(ids.legacy).get()).get('title') === `${runId} legacy` &&
    !(await db.collection('job_private').doc(ids.legacy).get()).exists,
  'legacy update failure must preserve the public document and absent private document');
  const collision = await callFunction('manageAdminJob', adminToken.idToken, {
    ...createPayload, jobId: ids.legacy,
  });
  check(rejected(collision, 'create collision must fail') === 'FAILED_PRECONDITION' &&
    !(await db.collection('job_private').doc(ids.legacy).get()).exists,
  'collision must not overwrite or create the private half');
  success(await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'delete', jobId: ids.legacy }), 'deleted', 'explicit legacy delete must remove the owned public record');
  ownedJobs.delete(ids.legacy);
  try { await db.collection('job_private').doc(ids.orphan).create({ contact: privateMarker }); }
  catch (error) {
    const existing = await db.collection('job_private').doc(ids.orphan).get();
    if (existing.get('contact') === privateMarker) ownedPrivateJobs.add(ids.orphan);
    throw error;
  }
  ownedPrivateJobs.add(ids.orphan);
  const orphanDelete = await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'delete', jobId: ids.orphan });
  check(rejected(orphanDelete, 'orphan private record must not be deleted through missing public job') === 'NOT_FOUND' &&
    (await db.collection('job_private').doc(ids.orphan).get()).exists,
  'delete of a missing public record must preserve an orphan private document');
  console.log('PASS legacy records, collisions and orphan private documents fail safely');

  stage = 'invalid parameters';
  const invalid = await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'get', jobId: '../bad' });
  check(rejected(invalid, 'invalid job IDs must be rejected') === 'INVALID_ARGUMENT',
    'invalid IDs must fail before storage access');
  const invalidField = await callFunction('manageAdminJob', adminToken.idToken, {
    operation: 'create', jobId: ids.denied,
    publicData: { title: `${runId} invalid`, unknownField: privateMarker }, privateData: {},
  });
  check(rejected(invalidField, 'unclassified fields must be rejected') === 'INVALID_ARGUMENT' &&
    !(await db.collection('jobs').doc(ids.denied).get()).exists,
  'unclassified input must fail before writing either document');
  console.log('PASS malformed IDs are rejected');

  stage = 'versioned authorization revocation';
  const revoke = await changeAdminClaim({
    auth, db, uid: adminUser.localId, action: 'revoke', operator: 'local-test',
    reason: 'Fictional integration fixture cleanup', apply: true,
    confirmation: `${project}:${adminUser.localId}:revoke`,
  });
  claimAuditIds.push(revoke.auditId);
  const revokedCall = await callFunction('manageAdminJob', adminToken.idToken,
    { operation: 'list', pageSize: 1 });
  check(revokedCall.status !== 200, 'revoked Admin authorization must deny the old token');
  console.log('PASS central Admin revocation denies further operations');

  stage = 'fixture cleanup';
  console.log('PASS all requested callable and authorization scenarios executed');
}

async function run() {
  let error = null;
  try { await main(); }
  catch (caught) { error = caught; }
  try { await cleanup(); }
  catch (cleanupError) {
    process.exitCode = 1;
    const name = /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(cleanupError?.name || '') ? cleanupError.name : 'Error';
    const rawCode = cleanupError?.code;
    const code = (typeof rawCode === 'string' && /^[A-Za-z0-9_/-]{1,40}$/.test(rawCode)) ||
      (Number.isInteger(rawCode) && rawCode >= 0 && rawCode <= 99) ? rawCode : 'unknown';
    console.error(`Fixture cleanup could not be verified during ${cleanupStage} (${name}; ${code}).`);
  }
  if (error) {
    const name = /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(error.name || '') ? error.name : 'IntegrationError';
    console.error(`manageAdminJob Emulator integration failed at ${stage} (${name}).`);
    if (typeof error.safeDiagnostic === 'string' && /^[A-Za-z0-9 (),;:_-]{1,180}$/.test(error.safeDiagnostic)) {
      console.error(error.safeDiagnostic);
    }
    const frames = String(error.stack || '').split('\n').filter((line) => /^\s+at /.test(line)).slice(0, 6);
    if (frames.length) console.error(frames.join('\n'));
    process.exitCode = 1;
  } else if (!process.exitCode) {
    console.log('manageAdminJob Emulator integration passed. Only UUID-scoped demo fixtures were used.');
  }
  if (admin.apps.length) await admin.app().delete().catch(() => { process.exitCode = 1; });
}

run();
