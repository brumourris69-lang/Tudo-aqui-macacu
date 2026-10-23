'use strict';

// Run only against a fresh, disposable demo Emulator pair on the dedicated
// alternate ports. This harness never contacts a hosted Firebase endpoint.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const PROJECT_ID = 'demo-universal-search';
const EXPECTED_FIRESTORE = '127.0.0.1:18087';
const EXPECTED_AUTH = '127.0.0.1:19097';
const OUTBOX_SCHEMA_VERSION = process.env.CATALOG_OUTBOX_SCHEMA_VERSION || '1';
const rulesPath = path.resolve(process.env.FIRESTORE_RULES_CANDIDATE_PATH ||
  path.join(__dirname, '../../firestore.hybrid-outbox-candidate.rules'));
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST;
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
if (process.env.GCLOUD_PROJECT !== PROJECT_ID || firestoreHost !== EXPECTED_FIRESTORE ||
    authHost !== EXPECTED_AUTH || !path.isAbsolute(rulesPath) || !fs.existsSync(rulesPath)) {
  throw new Error('Refusing to run: require the demo project, exact loopback alternate Emulator ports, and candidate Rules.');
}
if (!['1', '2'].includes(OUTBOX_SCHEMA_VERSION)) {
  throw new Error('Refusing to run: CATALOG_OUTBOX_SCHEMA_VERSION must be 1 or 2.');
}

const firestoreRoot = `http://${firestoreHost}/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const rulesUrl = `http://${firestoreHost}/emulator/v1/projects/${PROJECT_ID}:securityRules`;
const authRoot = `http://${authHost}/identitytoolkit.googleapis.com/v1`;
const createdDocs = new Set();
const createdUsers = new Set();
const runId = `outbox-${crypto.randomUUID()}`;
const admin = require('firebase-admin');
admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const auth = admin.auth();

function wire(value) {
  if (value === null) return { nullValue: 'NULL_VALUE' };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === 'number') return { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(wire) } };
  if (value && typeof value === 'object') {
    return { mapValue: { fields: Object.fromEntries(Object.entries(value).map(([key, item]) => [key, wire(item)])) } };
  }
  throw new Error('Unsupported local fixture value.');
}

function unWire(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('nullValue' in value) return null;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(unWire);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([k, v]) => [k, unWire(v)]));
  return undefined;
}

function decodeFields(fields = {}) {
  return Object.fromEntries(Object.entries(fields).map(([key, value]) => [key, unWire(value)]));
}

function headers(token) {
  return { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) };
}

async function localRequest(url, options = {}) {
  const response = await fetch(url, { ...options, redirect: 'error' });
  return { status: response.status, body: await response.json().catch(() => ({})) };
}

async function authPost(endpoint, body) {
  const response = await localRequest(`${authRoot}/${endpoint}?key=demo-only`, {
    method: 'POST', headers: headers(), body: JSON.stringify(body),
  });
  assert.equal(response.status, 200, `Local Auth Emulator ${endpoint} must succeed.`);
  return response.body;
}

async function createUser(label, anonymous = false) {
  const suffix = crypto.randomUUID();
  const body = anonymous
    ? { returnSecureToken: true }
    : { email: `${runId}-${label}-${suffix}@example.invalid`, password: `Local-${suffix}-Aa1!`, returnSecureToken: true };
  const result = await authPost('accounts:signUp', body);
  assert.ok(result.localId && result.idToken && result.refreshToken);
  createdUsers.add(result.localId);
  return { uid: result.localId, idToken: result.idToken, refreshToken: result.refreshToken,
    email: body.email, password: body.password };
}

async function refresh(user) {
  const response = await localRequest(`http://${authHost}/securetoken.googleapis.com/v1/token?key=demo-only`, {
    method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'refresh_token', refresh_token: user.refreshToken }),
  });
  assert.equal(response.status, 200, 'Local Auth Emulator refresh must succeed.');
  return response.body.id_token;
}

async function createAdminFixture(label, { authorization = 'active', claimVersion, recordVersion } = {}) {
  const user = await createUser(label);
  const version = claimVersion || crypto.randomUUID();
  await auth.setCustomUserClaims(user.uid, { admin: true, adminVersion: version });
  const authorizationPath = `admin_authorizations/${user.uid}`;
  if (authorization !== 'missing') {
    createdDocs.add(authorizationPath);
    await db.doc(authorizationPath).set({
      enabled: true,
      pending: false,
      version: recordVersion || version,
      operationId: crypto.randomUUID(),
      updatedAt: new Date(),
      ...(authorization && typeof authorization === 'object' ? authorization : {}),
    });
  }
  return { user, token: await refresh(user), authorizationPath, version };
}

async function assertAdminWriteDenied(label, adminFixture) {
  const establishmentId = `${runId}-admin-denied-${label}-${crypto.randomUUID()}`;
  const operationId = crypto.randomUUID();
  const result = await pairedCreate(establishmentId, operationId, adminFixture.token,
    adminFixture.user.uid);
  assert.equal(result.status, 403, `${label}: invalid Admin state must deny a paired write.`);
  assert.equal((await db.doc(`establishments/${establishmentId}`).get()).exists, false,
    `${label}: denied Admin state must not create the source document.`);
  assert.equal((await db.doc(`catalog_outbox/${operationId}`).get()).exists, false,
    `${label}: denied Admin state must not create an outbox event.`);
}

function docUrl(collection, id) { return `${firestoreRoot}/${collection}/${encodeURIComponent(id)}`; }
function docName(collection, id) { return `projects/${PROJECT_ID}/databases/(default)/documents/${collection}/${id}`; }

function sourceData(id, operationId, version, overrides = {}) {
  return {
    name: `Fictício ${id}`, title: `Fictício ${id}`, category: 'Comércio', description: '',
    published: true, active: true, featured: false, catalogVersion: version,
    outboxOperationId: operationId, ...overrides,
  };
}

function eventData(id, operationId, version, authorUid, overrides = {}) {
  return {
    schemaVersion: Number(OUTBOX_SCHEMA_VERSION), operationId, entityType: 'establishment', entityId: id,
    authorUid, version, operation: 'reconcile', state: 'pending', attemptCount: 0,
    ...(OUTBOX_SCHEMA_VERSION === '2' ? {
      workerId: null, leaseToken: null, leaseExpiresAt: null, nextAttemptAt: null,
      lastErrorCode: null, syncedAt: null,
    } : {}),
    ...overrides,
  };
}

function writeDocument(collection, id, fields, { exists, transforms = [], updateMask } = {}) {
  const transformed = new Set(transforms);
  const write = { update: { name: docName(collection, id), fields: Object.fromEntries(
    Object.entries(fields).filter(([key]) => !transformed.has(key)).map(([key, value]) => [key, wire(value)]),
  ) } };
  if (transforms.length) write.updateTransforms = transforms.map((fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' }));
  if (exists !== undefined) write.currentDocument = { exists };
  if (updateMask) write.updateMask = { fieldPaths: updateMask.filter((fieldPath) => !transformed.has(fieldPath)) };
  return write;
}

async function commit(writes, token) {
  return localRequest(`${firestoreRoot}:commit`, {
    method: 'POST', headers: headers(token), body: JSON.stringify({ writes }),
  });
}

async function pairedCreate(id, operationId, token, uid, sourceOverrides = {}, eventOverrides = {}) {
  // IDs are unique to this invocation; tracking before the request also makes
  // cleanup safe if a negative assertion unexpectedly succeeds.
  createdDocs.add(`establishments/${id}`);
  createdDocs.add(`catalog_outbox/${operationId}`);
  const source = sourceData(id, operationId, 1, sourceOverrides);
  const event = eventData(id, operationId, 1, uid, eventOverrides);
  const result = await commit([
    writeDocument('establishments', id, source, { exists: false, transforms: ['updatedAt'] }),
    writeDocument('catalog_outbox', operationId, event, { exists: false, transforms: ['createdAt', 'updatedAt'] }),
  ], token);
  return result;
}

async function pairedUpdate(id, operationId, version, token, uid, patch = {}, eventOverrides = {}) {
  createdDocs.add(`catalog_outbox/${operationId}`);
  const source = { ...patch, catalogVersion: version, outboxOperationId: operationId };
  const transforms = ['updatedAt'];
  if (Object.hasOwn(patch, 'deletedAt')) transforms.push('deletedAt');
  const event = eventData(id, operationId, version, uid, eventOverrides);
  const result = await commit([
    writeDocument('establishments', id, source, {
      exists: true, transforms, updateMask: Object.keys(source),
    }),
    writeDocument('catalog_outbox', operationId, event, {
      exists: false, transforms: ['createdAt', 'updatedAt'],
    }),
  ], token);
  if (result.status === 200) createdDocs.add(`catalog_outbox/${operationId}`);
  return result;
}

async function readStatus(pathname, token) {
  return (await localRequest(`${firestoreRoot}/${pathname}`, { headers: headers(token) })).status;
}

async function assertDocumentAbsent(collection, id) {
  const snapshot = await db.doc(`${collection}/${id}`).get();
  assert.equal(snapshot.exists, false, `Denied commit must not create ${collection}/${id}.`);
}

async function run() {
  const loaded = await localRequest(rulesUrl, {
    method: 'PUT', headers: headers(),
    body: JSON.stringify({ rules: { files: [{ name: 'firestore.hybrid-outbox-candidate.rules', content: fs.readFileSync(rulesPath, 'utf8') }] } }),
  });
  assert.equal(loaded.status, 200, 'Candidate Rules must load into the disposable local Emulator.');

  const anonymous = await createUser('anonymous', true);
  const ordinary = await createUser('ordinary');
  const administrator = await createUser('admin');
  const adminVersion = crypto.randomUUID();
  await auth.setCustomUserClaims(administrator.uid, { admin: true, adminVersion });
  await db.doc(`admin_authorizations/${administrator.uid}`).set({
    enabled: true, pending: false, version: adminVersion,
    operationId: crypto.randomUUID(), updatedAt: new Date(),
  });
  createdDocs.add(`admin_authorizations/${administrator.uid}`);
  const adminToken = await refresh(administrator);

  let passed = 0;
  async function check(label, body) { await body(); passed++; console.log(`PASS ${label}`); }

  await check('unauthenticated, anonymous and common users cannot read authorization or write source/outbox', async () => {
    const sourceId = `${runId}-deny`; const operationId = crypto.randomUUID();
    for (const token of [undefined, anonymous.idToken, ordinary.idToken]) {
      assert.ok([401, 403].includes(await readStatus(`admin_authorizations/${administrator.uid}`, token)));
      assert.equal((await pairedCreate(sourceId, operationId, token, ordinary.uid)).status, 403);
    }
  });

  await check('Admin can read only own minimal authorization record; list and mutation remain denied', async () => {
    assert.equal(await readStatus(`admin_authorizations/${administrator.uid}`, adminToken), 200);
    assert.equal(await readStatus(`admin_authorizations/${ordinary.uid}`, adminToken), 403);
    assert.equal((await localRequest(`${firestoreRoot}/admin_authorizations`, { headers: headers(adminToken) })).status, 403);
    const target = `admin_authorizations/${administrator.uid}`;
    const update = await localRequest(`${firestoreRoot}/${target}?updateMask.fieldPaths=enabled`, {
      method: 'PATCH', headers: headers(adminToken), body: JSON.stringify({ fields: { enabled: { booleanValue: false } } }),
    });
    assert.equal(update.status, 403);
  });

  await check('Admin claims with a divergent version are rejected', async () => {
    const fixture = await createAdminFixture('admin-version-divergent', {
      claimVersion: crypto.randomUUID(),
      recordVersion: crypto.randomUUID(),
    });
    await assertAdminWriteDenied('version-divergent', fixture);
  });

  await check('missing, pending and disabled Admin authorization states are rejected', async () => {
    const missing = await createAdminFixture('admin-authorization-missing', { authorization: 'missing' });
    await assertAdminWriteDenied('authorization-missing', missing);

    const pending = await createAdminFixture('admin-authorization-pending', {
      authorization: { pending: true },
    });
    await assertAdminWriteDenied('authorization-pending', pending);

    const disabled = await createAdminFixture('admin-authorization-disabled', {
      authorization: { enabled: false },
    });
    await assertAdminWriteDenied('authorization-disabled', disabled);
  });

  await check('an Admin authorization revoked after token issuance rejects the stale token', async () => {
    const fixture = await createAdminFixture('admin-authorization-revoked');
    await db.doc(fixture.authorizationPath).update({ version: crypto.randomUUID() });
    await assertAdminWriteDenied('authorization-revoked', fixture);
  });

  const id = `${runId}-valid`;
  const op = crypto.randomUUID();
  await check('valid Admin create commits source and pending outbox atomically', async () => {
    assert.equal((await pairedCreate(id, op, adminToken, administrator.uid)).status, 200);
  });

  await check('a committed operation cannot be replayed to duplicate a source or outbox event', async () => {
    const replay = await pairedCreate(id, op, adminToken, administrator.uid);
    const expectedReplayStatus = OUTBOX_SCHEMA_VERSION === '2' ? 403 : 409;
    assert.equal(replay.status, expectedReplayStatus,
      'The candidate Rules or Firestore create precondition must reject an exact replay.');
    const source = await db.doc(`establishments/${id}`).get();
    const event = await db.doc(`catalog_outbox/${op}`).get();
    assert.equal(source.exists, true);
    assert.equal(source.get('catalogVersion'), 1);
    assert.equal(source.get('outboxOperationId'), op);
    assert.equal(event.exists, true);
    assert.equal(event.get('operationId'), op);
    assert.equal(event.get('version'), 1);
    assert.equal(event.get('state'), 'pending');
  });

  await check('Firestore source is admin-only; public catalog reads cannot bypass the Supabase projection', async () => {
    assert.equal(await readStatus(`establishments/${id}`), 403);
    assert.equal(await readStatus(`establishments/${id}`, adminToken), 200);
    assert.equal(await readStatus(`catalog_outbox/${op}`, adminToken), 403);
    assert.equal((await localRequest(`${firestoreRoot}/catalog_outbox`, { headers: headers(adminToken) })).status, 403);
  });

  await check('source-only, outbox-only, and mismatched pairs fail atomically', async () => {
    const sourceId = `${runId}-source-only`; const operationId = crypto.randomUUID();
    createdDocs.add(`establishments/${sourceId}`);
    const sourceOnly = await commit([writeDocument('establishments', sourceId,
      sourceData(sourceId, operationId, 1), { exists: false, transforms: ['updatedAt'] })], adminToken);
    assert.equal(sourceOnly.status, 403);
    const eventOnly = await commit([writeDocument('catalog_outbox', operationId,
      eventData(sourceId, operationId, 1, administrator.uid), { exists: false, transforms: ['createdAt', 'updatedAt'] })], adminToken);
    assert.equal(eventOnly.status, 403);
    createdDocs.add(`catalog_outbox/${operationId}`);
    const mismatchId = `${runId}-mismatch`; const mismatchOp = crypto.randomUUID();
    const mismatch = await pairedCreate(mismatchId, mismatchOp, adminToken, administrator.uid, {}, { entityId: `${mismatchId}-other` });
    assert.equal(mismatch.status, 403);
    await assertDocumentAbsent('establishments', sourceId);
    await assertDocumentAbsent('catalog_outbox', operationId);
    await assertDocumentAbsent('establishments', mismatchId);
    await assertDocumentAbsent('catalog_outbox', mismatchOp);
  });

  await check('outbox cannot be forged as synced, attributed to another author, or expanded with unknown fields', async () => {
    for (const overrides of [
      { state: 'synced' }, { authorUid: ordinary.uid }, { internalSecret: 'not-allowed' },
      { operation: 'delete' }, { attemptCount: 1 },
    ]) {
      const badId = `${runId}-bad-${crypto.randomUUID().slice(0, 8)}`;
      const badOp = crypto.randomUUID();
      assert.equal((await pairedCreate(badId, badOp, adminToken, administrator.uid, {}, overrides)).status, 403);
      await assertDocumentAbsent('establishments', badId);
      await assertDocumentAbsent('catalog_outbox', badOp);
    }
    const sourceId = `${runId}-unknown-source`;
    const sourceOp = crypto.randomUUID();
    assert.equal((await pairedCreate(sourceId, sourceOp, adminToken, administrator.uid,
      { ownerEmail: 'private@example.invalid' })).status, 403);
    await assertDocumentAbsent('establishments', sourceId);
    await assertDocumentAbsent('catalog_outbox', sourceOp);
  });

  await check('unpaired version skips and physical source deletion are rejected', async () => {
    const nextOp = crypto.randomUUID();
    const invalidSource = sourceData(id, nextOp, 3, { name: 'Version pulada' });
    const invalidEvent = eventData(id, nextOp, 3, administrator.uid);
    const result = await commit([
      writeDocument('establishments', id, invalidSource, { exists: true, transforms: ['updatedAt'], updateMask: Object.keys(invalidSource).filter((key) => key !== 'updatedAt') }),
      writeDocument('catalog_outbox', nextOp, invalidEvent, { exists: false, transforms: ['createdAt', 'updatedAt'] }),
    ], adminToken);
    assert.equal(result.status, 403);
    assert.equal(await readStatus(`establishments/${id}`, adminToken), 200);
  });

  await check('soft unpublish is paired with a new monotonic event and hides the source immediately', async () => {
    const nextOp = crypto.randomUUID();
    const result = await pairedUpdate(id, nextOp, 2, adminToken, administrator.uid, {
      published: false, active: false,
    });
    assert.equal(result.status, 200);
    createdDocs.add(`establishments/${id}`);
    const source = await db.doc(`establishments/${id}`).get();
    assert.equal(source.get('published'), false);
    assert.equal(source.get('active'), false);
    assert.equal(source.get('deletedAt'), undefined,
      'Reversible unpublish must not create a logical-deletion tombstone.');
    assert.equal(source.get('catalogVersion'), 2);
    assert.equal(source.get('outboxOperationId'), nextOp);
    assert.equal(await readStatus(`establishments/${id}`), 403);
    assert.equal(await readStatus(`catalog_outbox/${nextOp}`, adminToken), 403);
  });

  await check('updates reject malformed changed fields and cannot republish a logical tombstone', async () => {
    const invalidOp = crypto.randomUUID();
    const invalid = await pairedUpdate(id, invalidOp, 3, adminToken, administrator.uid, { imageUrl: 7 });
    assert.equal(invalid.status, 403);
    const unchanged = await db.doc(`establishments/${id}`).get();
    assert.equal(unchanged.get('catalogVersion'), 2);
    assert.equal(unchanged.get('published'), false);
    await assertDocumentAbsent('catalog_outbox', invalidOp);

    const tombstoneId = `${runId}-logical-tombstone`;
    const priorOperationId = crypto.randomUUID();
    const deletedAt = new Date();
    createdDocs.add(`establishments/${tombstoneId}`);
    await db.doc(`establishments/${tombstoneId}`).set(sourceData(tombstoneId, priorOperationId, 4, {
      published: false, active: false, deletedAt,
    }));
    const republishOp = crypto.randomUUID();
    const republish = await pairedUpdate(tombstoneId, republishOp, 5, adminToken, administrator.uid, {
      published: true, active: true,
    });
    assert.equal(republish.status, 403);
    const tombstone = await db.doc(`establishments/${tombstoneId}`).get();
    assert.equal(tombstone.get('published'), false);
    assert.equal(tombstone.get('active'), false);
    assert.equal(tombstone.get('deletedAt').toMillis(), deletedAt.getTime());
    await assertDocumentAbsent('catalog_outbox', republishOp);
  });

  await check('physical source deletion is denied; unpublish is the supported removal path', async () => {
    const deletion = await localRequest(`${firestoreRoot}/establishments/${id}`, { method: 'DELETE', headers: headers(adminToken) });
    assert.equal(deletion.status, 403);
    assert.equal(await readStatus(`establishments/${id}`, adminToken), 200);
  });

  await check('outbox updates and deletion are denied even for Admin clients', async () => {
    const update = await localRequest(`${firestoreRoot}/catalog_outbox/${op}?updateMask.fieldPaths=state`, {
      method: 'PATCH', headers: headers(adminToken), body: JSON.stringify({ fields: { state: { stringValue: 'synced' } } }),
    });
    assert.equal(update.status, 403);
    const deletion = await localRequest(`${firestoreRoot}/catalog_outbox/${op}`, { method: 'DELETE', headers: headers(adminToken) });
    assert.equal(deletion.status, 403);
  });

  await check('unrelated public-content Admin writes retain the existing generic Rule', async () => {
    createdDocs.add(`news/${runId}-news`);
    createdDocs.add(`news/${runId}-common`);
    const response = await localRequest(`${firestoreRoot}/news/${runId}-news`, {
      method: 'PATCH', headers: headers(adminToken), body: JSON.stringify({ fields: { title: { stringValue: 'Fictício' }, published: { booleanValue: true } } }),
    });
    assert.equal(response.status, 200);
    createdDocs.add(`news/${runId}-news`);
    const denied = await localRequest(`${firestoreRoot}/news/${runId}-common`, {
      method: 'PATCH', headers: headers(ordinary.idToken), body: JSON.stringify({ fields: { title: { stringValue: 'Fictício' }, published: { booleanValue: true } } }),
    });
    assert.equal(denied.status, 403);
  });

  await check('legacy private/unclassified fields may remain unchanged but cannot be edited or added by this client contract', async () => {
    const legacyId = `${runId}-legacy`;
    createdDocs.add(`establishments/${legacyId}`);
    await db.doc(`establishments/${legacyId}`).set({
      name: 'Legado fictício', title: 'Legado fictício', category: 'Comércio',
      published: true, active: true, ownerEmail: 'private@example.invalid', privateLegacyField: 'preserve',
    });
    assert.equal(await readStatus(`establishments/${legacyId}`), 403);
    const legacyOp = crypto.randomUUID();
    createdDocs.add(`catalog_outbox/${legacyOp}`);
    const event = eventData(legacyId, legacyOp, 1, administrator.uid);
    const fields = { name: wire('Legado atualizado'), catalogVersion: wire(1), outboxOperationId: wire(legacyOp) };
    const valid = await commit([
      { update: { name: docName('establishments', legacyId), fields }, updateMask: { fieldPaths: Object.keys(fields) },
        updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }], currentDocument: { exists: true } },
      writeDocument('catalog_outbox', legacyOp, event, { exists: false, transforms: ['createdAt', 'updatedAt'] }),
    ], adminToken);
    assert.equal(valid.status, 200);
    createdDocs.add(`catalog_outbox/${legacyOp}`);
    const stored = await localRequest(`${firestoreRoot}/establishments/${legacyId}`, { headers: headers(adminToken) });
    assert.equal(decodeFields(stored.body.fields).ownerEmail, 'private@example.invalid');
    const badOp = crypto.randomUUID();
    createdDocs.add(`catalog_outbox/${badOp}`);
    const badFields = { privateLegacyField: wire('changed'), catalogVersion: wire(2), outboxOperationId: wire(badOp) };
    const bad = await commit([
      { update: { name: docName('establishments', legacyId), fields: badFields }, updateMask: { fieldPaths: Object.keys(badFields) },
        updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: 'REQUEST_TIME' }], currentDocument: { exists: true } },
      writeDocument('catalog_outbox', badOp, eventData(legacyId, badOp, 2, administrator.uid), { exists: false, transforms: ['createdAt', 'updatedAt'] }),
    ], adminToken);
    assert.equal(bad.status, 403);
  });

  console.log(`Catalog outbox Emulator tests: ${passed} scenarios passed.`);
}

run().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
}).finally(async () => {
  for (const pathname of createdDocs) await db.doc(pathname).delete().catch(() => {});
  for (const uid of createdUsers) await auth.deleteUser(uid).catch(() => {});
  await admin.app().delete().catch(() => {});
});
