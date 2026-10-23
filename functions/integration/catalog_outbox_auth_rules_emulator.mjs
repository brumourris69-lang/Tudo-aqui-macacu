import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createAdminEstablishmentsHandler } from '../../supabase/functions/_shared/admin_establishments.mjs';
import { authorizeAdmin } from '../../supabase/functions/_shared/admin_authorization.mjs';
import { verifyFirebaseIdToken } from '../../supabase/functions/_shared/firebase_id_token.mjs';

const PROJECT_ID = 'demo-universal-search';
const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:18087';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:19097';
const PRODUCTION_PROJECT_ID = 'tudo-aqui-macacu';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const requireFromFunctions = createRequire(path.join(root, 'functions/package.json'));
const { initializeApp: initializeAdminApp, deleteApp: deleteAdminApp } = requireFromFunctions('firebase-admin/app');
const { getAuth } = requireFromFunctions('firebase-admin/auth');
const { getFirestore: getAdminFirestore, FieldValue: AdminFieldValue, Timestamp: AdminTimestamp } = requireFromFunctions('firebase-admin/firestore');
const { initializeApp: initializeClientApp, deleteApp: deleteClientApp } = requireFromFunctions('firebase/app');
const { initializeAuth, inMemoryPersistence, connectAuthEmulator, createUserWithEmailAndPassword,
  signInWithEmailAndPassword, signInAnonymously, signOut } = requireFromFunctions('firebase/auth');
const { getFirestore, connectFirestoreEmulator, doc, getDoc, deleteDoc, collection, getDocs, writeBatch,
  serverTimestamp } = requireFromFunctions('firebase/firestore');

assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, FIRESTORE_HOST);
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, AUTH_HOST);
for (const endpoint of [FIRESTORE_HOST, AUTH_HOST]) {
  const parsed = new URL(`http://${endpoint}`);
  assert.ok(['127.0.0.1', 'localhost'].includes(parsed.hostname), 'Firebase Emulators must bind to loopback.');
  assert.ok(parsed.port, 'Firebase Emulator ports must be explicit.');
  assert.equal(parsed.pathname, '/', 'Firebase Emulator endpoint must not include a path.');
}

const runId = `outbox-sdk-${randomUUID()}`;
const adminApp = initializeAdminApp({ projectId: PROJECT_ID }, `server-${runId}`);
const adminDb = getAdminFirestore(adminApp);
const adminAuth = getAuth(adminApp);
const clients = [];
const createdUsers = new Set();
const createdDocuments = new Set();
let rulesGroups = 0;
let endpointChecks = 0;
const rulesFailures = [];
let activeCandidate = 'unknown';

async function readRuleCoverage() {
  const response = await fetch(`http://${FIRESTORE_HOST}/emulator/v1/projects/${PROJECT_ID}:ruleCoverage`);
  assert.equal(response.status, 200, 'Firestore Emulator Rules coverage endpoint must be available.');
  return response.json();
}

function summarizeRuleCoverage(coverage) {
  const metrics = new Map();
  const knownCounts = new Set(['count', 'evaluations', 'evaluationCount', 'executionCount', 'numExecutions']);
  function visit(node) {
    if (!node || typeof node !== 'object') return;
    const line = node.sourcePosition?.line;
    const column = node.sourcePosition?.column;
    const counts = {};
    let valueSamples = 0;
    for (const [key, value] of Object.entries(node)) {
      if (key === 'sourcePosition' || key === 'children') continue;
      if (knownCounts.has(key) && typeof value === 'number') counts[key] = value;
      if (Array.isArray(value)) {
        valueSamples += value.length;
        for (const sample of value) {
          if (!sample || typeof sample !== 'object') continue;
          for (const [sampleKey, sampleValue] of Object.entries(sample)) {
            if (knownCounts.has(sampleKey) && typeof sampleValue === 'number') {
              counts[sampleKey] = (counts[sampleKey] ?? 0) + sampleValue;
            }
          }
        }
      }
    }
    if (line !== undefined) {
      const key = `${line}:${column}`;
      const aggregate = metrics.get(key) ?? { line, column, counts: {}, valueSamples: 0 };
      for (const [name, count] of Object.entries(counts)) {
        aggregate.counts[name] = (aggregate.counts[name] ?? 0) + count;
      }
      aggregate.valueSamples += valueSamples;
      metrics.set(key, aggregate);
    }
    for (const child of node.children ?? []) visit(child);
  }
  for (const node of coverage.report ?? []) visit(node);
  return [...metrics.values()];
}

function coverageDelta(before, after) {
  const keyOf = (item) => `${item.line}:${item.column}`;
  const previous = new Map(before.map((item) => [keyOf(item), item]));
  return after.map((item) => {
    const old = previous.get(keyOf(item)) ?? { counts: {}, valueSamples: 0 };
    const deltaCounts = Object.fromEntries(Object.entries(item.counts)
      .map(([key, count]) => [key, count - (old.counts[key] ?? 0)])
      .filter(([, count]) => count !== 0));
    const valueSamples = Math.max(0, item.valueSamples - old.valueSamples);
    return { line: item.line, column: item.column, counts: deltaCounts, valueSamples };
  }).filter((item) => Object.values(item.counts).some((count) => count > 0) || item.valueSamples > 0);
}

function newClient(label, projectId = PROJECT_ID) {
  const app = initializeClientApp({ apiKey: 'demo-key', projectId, appId: `demo-${label}` }, `${runId}-${label}`);
  const auth = initializeAuth(app, { persistence: inMemoryPersistence });
  connectAuthEmulator(auth, `http://${AUTH_HOST}`, { disableWarnings: true });
  const db = getFirestore(app);
  const firestorePort = Number(new URL(`http://${FIRESTORE_HOST}`).port);
  connectFirestoreEmulator(db, new URL(`http://${FIRESTORE_HOST}`).hostname, firestorePort);
  const client = { app, auth, db };
  clients.push(client);
  return client;
}

const adminClient = newClient('admin');
const ordinaryClient = newClient('ordinary');
const anonymousClient = newClient('anonymous');

async function createAccount(client, label) {
  const suffix = randomUUID();
  const email = `${runId}-${label}-${suffix}@example.invalid`;
  const password = `Local-${suffix}-Aa1!`;
  const credential = await createUserWithEmailAndPassword(client.auth, email, password);
  createdUsers.add(credential.user.uid);
  return { uid: credential.user.uid, email, password, user: credential.user, token: await credential.user.getIdToken(true) };
}

async function setAdminAuthorization(uid, version, { enabled = true, pending = false } = {}) {
  const reference = adminDb.doc(`admin_authorizations/${uid}`);
  createdDocuments.add(reference.path);
  await reference.set({ enabled, pending, version, operationId: randomUUID(), updatedAt: AdminFieldValue.serverTimestamp() });
}

async function installRules(filename) {
  const file = path.join(root, filename);
  const rules = await import('node:fs/promises').then((fs) => fs.readFile(file, 'utf8'));
  const response = await fetch(`http://${FIRESTORE_HOST}/emulator/v1/projects/${PROJECT_ID}:securityRules`, {
    method: 'PUT', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ rules: { files: [{ name: filename, content: rules }] } }),
  });
  assert.equal(response.status, 200, `Candidate Rules ${filename} must load in the local Emulator.`);
}

function sourceData(id, operationId, version, patch = {}) {
  return {
    name: `Fixture ${id}`, title: `Fixture ${id}`, category: 'Comércio', description: '',
    published: true, active: true, featured: false, catalogVersion: version,
    outboxOperationId: operationId, createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...patch,
  };
}

function eventData(schemaVersion, entityId, operationId, version, authorUid, patch = {}) {
  return {
    schemaVersion, operationId, entityType: 'establishment', entityId, authorUid,
    version, operation: 'reconcile', state: 'pending', attemptCount: 0,
    ...(schemaVersion === 2 ? {
      workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null,
      lastErrorCode: null, syncedAt: null,
    } : {}),
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(), ...patch,
  };
}

function batchCreate(client, schemaVersion, id, operationId, uid, sourcePatch = {}, eventPatch = {}) {
  const batch = writeBatch(client.db);
  batch.set(doc(client.db, 'establishments', id), sourceData(id, operationId, 1, sourcePatch));
  batch.set(doc(client.db, 'catalog_outbox', operationId), eventData(schemaVersion, id, operationId, 1, uid, eventPatch));
  return batch.commit();
}

function batchUpdate(client, schemaVersion, id, operationId, uid, version, patch) {
  const batch = writeBatch(client.db);
  batch.update(doc(client.db, 'establishments', id), {
    ...patch, catalogVersion: version, outboxOperationId: operationId, updatedAt: serverTimestamp(),
  });
  batch.set(doc(client.db, 'catalog_outbox', operationId), eventData(schemaVersion, id, operationId, version, uid));
  return batch.commit();
}

async function denied(operation, label) {
  let failure;
  try { await operation; } catch (error) { failure = error; }
  assert.ok(failure, label);
  if (/maximum of 1000 expressions/u.test(failure.message ?? '')) {
    throw Object.assign(new Error('Firestore Rules expression budget exceeded during a denied client operation.'),
      { code: 'rules-expression-budget-exceeded' });
  }
  assert.ok(['permission-denied', 'unauthenticated', 'failed-precondition'].includes(failure.code),
    `${label}: unexpected SDK error code ${failure.code ?? 'missing'}.`);
}

async function ruleCheck(label, callback) {
  const captureCoverage = process.env.FIRESTORE_RULE_COVERAGE === '1' &&
    /replay|without outbox|mismatched|version skip|synced event|private source fields|tombstone cannot|revoked Admin/iu.test(label);
  const coverageBefore = captureCoverage ? summarizeRuleCoverage(await readRuleCoverage()) : null;
  try {
    await callback();
    rulesGroups++;
    console.log(`PASS Rules ${label}`);
  } catch (error) {
    const failure = { candidate: activeCandidate, group: label,
      code: error.code ?? error.name ?? 'error' };
    rulesFailures.push(failure);
    console.error(`FAIL Rules ${activeCandidate} ${label}: ${failure.code}`);
  } finally {
    if (captureCoverage) {
      const coverageAfter = summarizeRuleCoverage(await readRuleCoverage());
      const delta = coverageDelta(coverageBefore, coverageAfter);
      const positive = delta.map((item) => ({ ...item,
        counts: Object.fromEntries(Object.entries(item.counts).filter(([, count]) => count > 0)) }))
        .filter((item) => Object.keys(item.counts).length || item.valueSamples > 0);
      console.log(`COVERAGE ${activeCandidate} ${label}: ${JSON.stringify({ nodes: delta.length,
        metricKeys: [...new Set(positive.flatMap((item) => Object.keys(item.counts)))],
        evaluationCount: positive.reduce((sum, item) => sum + Object.values(item.counts).reduce((n, value) => n + value, 0), 0),
        hottestLines: positive.sort((a, b) =>
          Object.values(b.counts).reduce((n, value) => n + value, 0) -
          Object.values(a.counts).reduce((n, value) => n + value, 0)).slice(0, 8)
          .map(({ line, valueSamples, counts }) => ({ line, valueSamples, counts })) })}`);
    }
  }
}

async function exerciseRules(filename, schemaVersion) {
  activeCandidate = filename;
  await installRules(filename);
  const admin = await createAccount(adminClient, `rules-admin-v${schemaVersion}`);
  const ordinary = await createAccount(ordinaryClient, `rules-user-v${schemaVersion}`);
  const anonymous = await signInAnonymously(anonymousClient.auth);
  createdUsers.add(anonymous.user.uid);
  const adminVersion = `rules-${schemaVersion}-${randomUUID()}`;
  await adminAuth.setCustomUserClaims(admin.uid, { admin: true, adminVersion });
  await setAdminAuthorization(admin.uid, adminVersion);
  const adminToken = await admin.user.getIdToken(true);
  const schema = schemaVersion;
  const id = `${runId}-v${schemaVersion}-entry`;
  const operationId = randomUUID();
  createdDocuments.add(`establishments/${id}`);
  createdDocuments.add(`catalog_outbox/${operationId}`);

  await ruleCheck(`V${schemaVersion}: Auth Emulator tokens are real SDK tokens accepted by Admin SDK`, async () => {
    const verified = await adminAuth.verifyIdToken(adminToken);
    assert.equal(verified.uid, admin.uid);
    assert.equal(verified.aud, PROJECT_ID);
    assert.equal(verified.firebase.sign_in_provider, 'password');
    assert.equal((await admin.user.getIdTokenResult()).claims.admin, true);
  });

  await ruleCheck(`V${schemaVersion}: owner may get minimal authorization; common, anonymous and unauthenticated reads are denied`, async () => {
    assert.equal((await getDoc(doc(adminClient.db, 'admin_authorizations', admin.uid))).exists(), true);
    await denied(getDoc(doc(ordinaryClient.db, 'admin_authorizations', admin.uid)), 'Other users cannot read Admin authorization.');
    await denied(getDoc(doc(anonymousClient.db, 'establishments', id)), 'Anonymous source read must be denied.');
    await denied(getDoc(doc(ordinaryClient.db, 'establishments', id)), 'Common source read must be denied.');
    await denied(getDoc(doc(ordinaryClient.db, 'admin_authorizations', ordinary.uid)), 'Common user cannot read authorization.');
  });

  await ruleCheck(`V${schemaVersion}: Admin creates canonical document and outbox atomically via client SDK`, async () => {
    await batchCreate(adminClient, schema, id, operationId, admin.uid);
    const source = await adminDb.doc(`establishments/${id}`).get();
    const event = await adminDb.doc(`catalog_outbox/${operationId}`).get();
    assert.equal(source.get('catalogVersion'), 1);
    assert.equal(source.get('outboxOperationId'), operationId);
    assert.equal(event.get('schemaVersion'), schema);
    assert.equal(event.get('state'), 'pending');
    assert.equal(event.get('authorUid'), admin.uid);
    assert.ok(event.get('createdAt') instanceof AdminTimestamp);
  });

  await ruleCheck(`V${schemaVersion}: ordinary authenticated user cannot create an establishment/outbox pair`, async () => {
    const deniedId = `${runId}-v${schemaVersion}-ordinary`;
    const deniedOperation = randomUUID();
    createdDocuments.add(`establishments/${deniedId}`);
    createdDocuments.add(`catalog_outbox/${deniedOperation}`);
    await denied(batchCreate(ordinaryClient, schema, deniedId, deniedOperation, ordinary.uid),
      'Ordinary authenticated users cannot create catalog pairs.');
    assert.equal((await adminDb.doc(`establishments/${deniedId}`).get()).exists, false);
    assert.equal((await adminDb.doc(`catalog_outbox/${deniedOperation}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: source can be read by Admin; outbox stays private even to Admin clients`, async () => {
    assert.equal((await getDoc(doc(adminClient.db, 'establishments', id))).exists(), true);
    await denied(getDoc(doc(adminClient.db, 'catalog_outbox', operationId)), 'Outbox read must be denied by Rules.');
    await denied(getDocs(collection(adminClient.db, 'catalog_outbox')), 'Outbox list must be denied by Rules.');
  });

  await ruleCheck(`V${schemaVersion}: physical deletion cannot replace a tombstone`, async () => {
    await denied(deleteDoc(doc(adminClient.db, 'establishments', id)), 'Physical source deletion must be denied.');
    assert.equal((await adminDb.doc(`establishments/${id}`).get()).exists, true);
  });

  await ruleCheck(`V${schemaVersion}: replay of a committed pair is rejected`, async () => {
    await denied(batchCreate(adminClient, schema, id, operationId, admin.uid), 'Replay must be denied.');
    assert.equal((await adminDb.doc(`establishments/${id}`).get()).get('catalogVersion'), 1);
    assert.equal((await adminDb.doc(`catalog_outbox/${operationId}`).get()).get('state'), 'pending');
  });

  await ruleCheck(`V${schemaVersion}: source write without outbox is denied atomically`, async () => {
    const sourceOnly = `${runId}-v${schemaVersion}-source-only`;
    const sourceOnlyOp = randomUUID();
    createdDocuments.add(`establishments/${sourceOnly}`);
    const sourceBatch = writeBatch(adminClient.db);
    sourceBatch.set(doc(adminClient.db, 'establishments', sourceOnly), sourceData(sourceOnly, sourceOnlyOp, 1));
    await denied(sourceBatch.commit(), 'Unpaired source write must be denied.');
    assert.equal((await adminDb.doc(`establishments/${sourceOnly}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: outbox write without source is denied atomically`, async () => {
    const eventOnlyId = `${runId}-v${schemaVersion}-event-only`;
    const eventOnlyOp = randomUUID();
    createdDocuments.add(`catalog_outbox/${eventOnlyOp}`);
    const eventBatch = writeBatch(adminClient.db);
    eventBatch.set(doc(adminClient.db, 'catalog_outbox', eventOnlyOp),
      eventData(schema, eventOnlyId, eventOnlyOp, 1, admin.uid));
    await denied(eventBatch.commit(), 'Unpaired outbox write must be denied.');
    assert.equal((await adminDb.doc(`catalog_outbox/${eventOnlyOp}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: mismatched source/outbox pair is denied atomically`, async () => {
    const mismatchId = `${runId}-v${schemaVersion}-mismatch`;
    const mismatchOp = randomUUID();
    createdDocuments.add(`establishments/${mismatchId}`);
    createdDocuments.add(`catalog_outbox/${mismatchOp}`);
    await denied(batchCreate(adminClient, schema, mismatchId, mismatchOp, admin.uid, {}, { entityId: `${mismatchId}-wrong` }),
      'Mismatched source/outbox pair must be denied.');
    assert.equal((await adminDb.doc(`establishments/${mismatchId}`).get()).exists, false);
    assert.equal((await adminDb.doc(`catalog_outbox/${mismatchOp}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: versioned update and reversible unpublish work`, async () => {
    const updateOp = randomUUID();
    createdDocuments.add(`catalog_outbox/${updateOp}`);
    await batchUpdate(adminClient, schema, id, updateOp, admin.uid, 2, { description: 'Atualizado pela SDK.' });
    const unpublishOp = randomUUID();
    createdDocuments.add(`catalog_outbox/${unpublishOp}`);
    await batchUpdate(adminClient, schema, id, unpublishOp, admin.uid, 3, { published: false, active: false });
    const source = await adminDb.doc(`establishments/${id}`).get();
    assert.equal(source.get('catalogVersion'), 3);
    assert.equal(source.get('published'), false);
    assert.equal(source.get('deletedAt'), undefined);
  });

  await ruleCheck(`V${schemaVersion}: version skip is denied`, async () => {
    const currentVersion = (await adminDb.doc(`establishments/${id}`).get()).get('catalogVersion');
    await denied(batchUpdate(adminClient, schema, id, randomUUID(), admin.uid, currentVersion + 2,
      { description: 'skip-version' }), 'Version skip must be denied.');
    assert.equal((await adminDb.doc(`establishments/${id}`).get()).get('catalogVersion'), currentVersion);
  });

  await ruleCheck(`V${schemaVersion}: versioned republish of a non-tombstoned record works`, async () => {
    const currentVersion = (await adminDb.doc(`establishments/${id}`).get()).get('catalogVersion');
    const republishOp = randomUUID();
    createdDocuments.add(`catalog_outbox/${republishOp}`);
    await batchUpdate(adminClient, schema, id, republishOp, admin.uid, currentVersion + 1,
      { published: true, active: true });
    const source = await adminDb.doc(`establishments/${id}`).get();
    assert.equal(source.get('catalogVersion'), currentVersion + 1);
    assert.equal(source.get('published'), true);
    assert.equal(source.get('deletedAt'), undefined);
  });

  await ruleCheck(`V${schemaVersion}: client cannot forge a synced event`, async () => {
    const badId = `${runId}-v${schemaVersion}-bad`;
    const badOp = randomUUID();
    createdDocuments.add(`establishments/${badId}`);
    createdDocuments.add(`catalog_outbox/${badOp}`);
    await denied(batchCreate(adminClient, schema, badId, badOp, admin.uid, {}, { state: 'synced' }),
      'Client cannot create a synced event.');
    assert.equal((await adminDb.doc(`establishments/${badId}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: private source fields are denied`, async () => {
    const extraId = `${runId}-v${schemaVersion}-extra`;
    const extraOp = randomUUID();
    createdDocuments.add(`establishments/${extraId}`);
    createdDocuments.add(`catalog_outbox/${extraOp}`);
    await denied(batchCreate(adminClient, schema, extraId, extraOp, admin.uid, { adminNote: 'private' }),
      'Private source field must be denied.');
    assert.equal((await adminDb.doc(`establishments/${extraId}`).get()).exists, false);
  });

  await ruleCheck(`V${schemaVersion}: tombstone cannot be republished`, async () => {
    const tombstoneId = `${runId}-v${schemaVersion}-tombstone`;
    const tombstoneOp = randomUUID();
    createdDocuments.add(`establishments/${tombstoneId}`);
    const tombstoneSource = sourceData(tombstoneId, tombstoneOp, 4, {
      published: false, active: false, deletedAt: AdminFieldValue.serverTimestamp(),
    });
    tombstoneSource.createdAt = AdminFieldValue.serverTimestamp();
    tombstoneSource.updatedAt = AdminFieldValue.serverTimestamp();
    await adminDb.doc(`establishments/${tombstoneId}`).set(tombstoneSource);
    const republishOp = randomUUID();
    createdDocuments.add(`catalog_outbox/${republishOp}`);
    await denied(batchUpdate(adminClient, schema, tombstoneId, republishOp, admin.uid, 5,
      { published: true, active: true }), 'Permanent tombstone cannot be republished.');
    assert.equal((await adminDb.doc(`establishments/${tombstoneId}`).get()).get('catalogVersion'), 4);
  });

  await ruleCheck(`V${schemaVersion}: revoked Admin authorization version is rejected`, async () => {
    await setAdminAuthorization(admin.uid, `revoked-${randomUUID()}`);
    const deniedId = `${runId}-v${schemaVersion}-revoked`;
    const deniedOp = randomUUID();
    createdDocuments.add(`establishments/${deniedId}`);
    createdDocuments.add(`catalog_outbox/${deniedOp}`);
    await denied(batchCreate(adminClient, schema, deniedId, deniedOp, admin.uid), 'Revoked authorization must deny writes.');
  });

  await ruleCheck(`V${schemaVersion}: disabled Auth user cannot sign in again`, async () => {
    await adminAuth.updateUser(ordinary.uid, { disabled: true });
    await signOut(ordinaryClient.auth);
    await assert.rejects(signInWithEmailAndPassword(ordinaryClient.auth, ordinary.email, ordinary.password),
      (error) => error.code === 'auth/user-disabled');
  });
}

function formatUpdateTime(timestamp) {
  const date = timestamp.toDate().toISOString();
  const nanos = String(timestamp.nanoseconds).padStart(9, '0');
  return date.replace(/\.\d{3}Z$/u, `.${nanos}Z`);
}

function createAdminStore() {
  return {
    runTransaction(callback) {
      return adminDb.runTransaction(async (native) => {
        const snapshots = new Map();
        const transaction = {
          async get(collectionName, id) {
            const ref = adminDb.collection(collectionName).doc(id);
            const snapshot = await native.get(ref);
            snapshots.set(`${collectionName}/${id}`, snapshot);
            return snapshot.exists ? { data: snapshot.data(), updateTime: formatUpdateTime(snapshot.updateTime) } : null;
          },
          create(collectionName, id, data, options = {}) {
            const value = { ...data };
            for (const field of options.serverTimestampFields ?? []) value[field] = AdminFieldValue.serverTimestamp();
            native.create(adminDb.collection(collectionName).doc(id), value);
            createdDocuments.add(`${collectionName}/${id}`);
          },
          update(collectionName, id, data, options = {}) {
            const key = `${collectionName}/${id}`;
            const snapshot = snapshots.get(key);
            if (!snapshot?.exists || formatUpdateTime(snapshot.updateTime) !== options.updateTime) {
              throw Object.assign(new Error('Transaction precondition failed.'), { code: 'conflict' });
            }
            const value = { ...data };
            for (const field of options.serverTimestampFields ?? []) value[field] = AdminFieldValue.serverTimestamp();
            for (const field of options.deleteFields ?? []) value[field] = AdminFieldValue.delete();
            native.update(adminDb.collection(collectionName).doc(id), value);
          },
        };
        return callback(transaction);
      }, { maxAttempts: 5 });
    },
  };
}

function startHttpEndpoint(handler) {
  const server = createServer(async (request, response) => {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    const method = request.method ?? 'GET';
    const body = chunks.length ? Buffer.concat(chunks) : undefined;
    const webRequest = new Request(`http://127.0.0.1:${server.address()?.port ?? 0}${request.url ?? '/'}`, {
      method, headers: request.headers, ...(body && method !== 'GET' && method !== 'HEAD' ? { body } : {}),
    });
    const result = await handler(webRequest);
    response.writeHead(result.status, Object.fromEntries(result.headers.entries()));
    response.end(Buffer.from(await result.arrayBuffer()));
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve({ server, origin: `http://127.0.0.1:${server.address().port}` }));
  });
}

async function endpointCheck(label, callback) {
  await callback();
  endpointChecks++;
  console.log(`PASS endpoint ${label}`);
}

async function exerciseEndpoint() {
  const admin = await createAccount(newClient('endpoint-admin'), 'endpoint-admin');
  const common = await createAccount(newClient('endpoint-common'), 'endpoint-common');
  const version = `endpoint-${randomUUID()}`;
  await adminAuth.setCustomUserClaims(admin.uid, { admin: true, adminVersion: version });
  const token = await admin.user.getIdToken(true);
  await setAdminAuthorization(admin.uid, version);

  const handler = createAdminEstablishmentsHandler({
    projectId: PRODUCTION_PROJECT_ID,
    verifyIdentity: async (idToken, expectedProject) => {
      assert.equal(expectedProject, PRODUCTION_PROJECT_ID);
      const decoded = await adminAuth.verifyIdToken(idToken, true);
      if (decoded.aud !== PROJECT_ID || decoded.firebase?.sign_in_provider === 'anonymous') {
        throw new Error('Emulator identity project/provider mismatch.');
      }
      return Object.freeze({ uid: decoded.uid, authTime: decoded.auth_time, isAnonymous: false,
        provider: decoded.firebase.sign_in_provider });
    },
    authorizeAdmin,
    store: createAdminStore(),
  });
  const { server, origin } = await startHttpEndpoint(handler);
  const entityId = `${runId}-endpoint-${randomUUID()}`;
  const requestId = randomUUID();
  const body = { operation: 'create', requestId, entityId, data: {
    title: 'HTTP Emulator Fixture', category: 'Comércio', description: 'Fictício',
    published: true, active: true, publicContactApproved: false,
  } };
  try {
    await endpointCheck('Auth Emulator token is accepted by Firebase Admin SDK and the real handler', async () => {
      const decoded = await adminAuth.verifyIdToken(token);
      assert.equal(decoded.uid, admin.uid);
      assert.equal(decoded.aud, PROJECT_ID);
      const response = await fetch(`${origin}/manage-establishments`, { method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
      assert.equal(response.status, 201);
      const event = await adminDb.doc(`catalog_outbox/${requestId}`).get();
      const source = await adminDb.doc(`establishments/${entityId}`).get();
      assert.equal(source.get('catalogVersion'), 1);
      assert.equal(event.get('operationId'), requestId);
      assert.equal(event.get('state'), 'pending');
    });

    await endpointCheck('missing, malformed, expired, wrong-project and common-user tokens are denied without writes', async () => {
      const send = (authHeader) => fetch(`${origin}/manage-establishments`, {
        method: 'POST', headers: { 'content-type': 'application/json', ...(authHeader ? { authorization: authHeader } : {}) },
        body: JSON.stringify({ ...body, requestId: randomUUID(), entityId: `${entityId}-denied` }),
      });
      assert.equal((await send(undefined)).status, 401);
      assert.equal((await send('Bearer invalid-token')).status, 401);
      const expired = mutatePayload(token, { exp: Math.floor(Date.now() / 1000) - 3600 });
      assert.equal((await send(`Bearer ${expired}`)).status, 401);
      const wrongProject = mutatePayload(token, { aud: 'other-demo-project' });
      assert.equal((await send(`Bearer ${wrongProject}`)).status, 401);
      const commonResponse = await fetch(`${origin}/manage-establishments`, { method: 'POST',
        headers: { authorization: `Bearer ${common.token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ ...body, requestId: randomUUID(), entityId: `${entityId}-common` }) });
      assert.equal(commonResponse.status, 403);
      assert.equal((await adminDb.doc(`establishments/${entityId}-denied`).get()).exists, false);
      assert.equal((await adminDb.doc(`establishments/${entityId}-common`).get()).exists, false);
    });

    await endpointCheck('replay is idempotent and central Admin revocation blocks later writes', async () => {
      const replay = await fetch(`${origin}/manage-establishments`, { method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: JSON.stringify(body) });
      assert.equal(replay.status, 200);
      assert.equal((await replay.json()).replayed, true);
      const before = (await adminDb.doc(`establishments/${entityId}`).get()).get('catalogVersion');
      await adminDb.doc(`admin_authorizations/${admin.uid}`).update({ enabled: false,
        operationId: randomUUID(), updatedAt: AdminFieldValue.serverTimestamp() });
      const revokedRequestId = randomUUID();
      const revoked = await fetch(`${origin}/manage-establishments`, { method: 'POST',
        headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
        body: JSON.stringify({ operation: 'update', requestId: revokedRequestId, entityId,
          expectedVersion: before, data: { description: 'Must not persist.' } }) });
      assert.equal(revoked.status, 403);
      assert.equal((await adminDb.doc(`establishments/${entityId}`).get()).get('catalogVersion'), before);
      assert.equal((await adminDb.doc(`catalog_outbox/${revokedRequestId}`).get()).exists, false);
    });

    await endpointCheck('disabled Auth account is rejected after token refresh, and RS256 production verifier rejects unsigned emulator token', async () => {
      await adminAuth.updateUser(admin.uid, { disabled: true });
      await signOut(adminClient.auth);
      await assert.rejects(signInWithEmailAndPassword(adminClient.auth, admin.email, admin.password),
        (error) => error.code === 'auth/user-disabled');
      await assert.rejects(verifyFirebaseIdToken(token, { projectId: PROJECT_ID, getSigningKey: async () => null }),
        (error) => ['invalid-token', 'invalid-signature', 'unknown-signing-key'].includes(error.code));
    });
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

function mutatePayload(token, patch) {
  const parts = token.split('.');
  assert.equal(parts.length, 3);
  const payload = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
  parts[1] = Buffer.from(JSON.stringify({ ...payload, ...patch })).toString('base64url');
  return parts.join('.');
}

async function cleanup() {
  await Promise.all([...createdDocuments].map((name) => adminDb.doc(name).delete().catch(() => {})));
  await Promise.all([...createdUsers].map((uid) => adminAuth.deleteUser(uid).catch(() => {})));
  await Promise.all(clients.map(async ({ auth, app }) => {
    await signOut(auth).catch(() => {});
    await deleteClientApp(app).catch(() => {});
  }));
  await deleteAdminApp(adminApp).catch(() => {});
}

async function main() {
  const firestoreProbe = await fetch(`http://${FIRESTORE_HOST}/`);
  assert.ok(firestoreProbe.status < 500, 'Firestore Emulator must be reachable on the configured loopback port.');
  const authProbe = await fetch(`http://${AUTH_HOST}/`);
  assert.ok(authProbe.status < 500, 'Auth Emulator must be reachable on the configured loopback port.');
  for (const [filename, version] of [
    ['firestore.hybrid-outbox-candidate.rules', 1],
    ['firestore.hybrid-outbox-v2-candidate.rules', 2],
  ]) {
    try {
      await exerciseRules(filename, version);
    } catch (error) {
      const expressionLimit = /maximum of 1000 expressions/u.test(error.message ?? '');
      const failure = { candidate: filename, code: expressionLimit ? 'rules-expression-budget-exceeded' : error.code ?? error.name ?? 'error' };
      rulesFailures.push(failure);
      console.error(`FAIL Rules ${filename}: ${failure.code}`);
    }
  }
  await exerciseEndpoint();
  console.log(JSON.stringify({
    project: PROJECT_ID, firestore: FIRESTORE_HOST, auth: AUTH_HOST,
    rulesGroupsPassed: rulesGroups, endpointChecksPassed: endpointChecks,
    rulesFailures,
    note: 'Rules writes/reads use Firebase client SDK; privileged setup and endpoint persistence use Admin SDK against demo Emulators only.',
  }, null, 2));
  if (rulesFailures.length) process.exitCode = 1;
}

main().catch((error) => {
  console.error(`Authenticated Emulator validation failed: ${error.code ?? error.name ?? 'error'}`);
  console.error(error.message);
  process.exitCode = 1;
}).finally(cleanup);
