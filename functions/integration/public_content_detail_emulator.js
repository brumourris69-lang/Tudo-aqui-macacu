'use strict';

// Integration coverage for the demo-only public content detail callable.
// Every write is scoped to UUID-owned fixtures and removed in finally.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');

const environment = readDemoEmulatorEnvironment();
const admin = require('firebase-admin');
admin.initializeApp({ projectId: environment.project });
const db = admin.firestore();
const auth = admin.auth();
const authRoot = `http://${environment.authHost}/identitytoolkit.googleapis.com/v1`;
const runId = crypto.randomUUID();
const ownedRefs = new Map();
const createdRefs = new Map();
const createdUsers = new Set();
const privateFields = ['contact', 'phone', 'whatsapp', 'instagram', 'ownerEmail', 'privateNotes',
  'salary', 'eventDate', 'date', 'unknownPrivate', 'publicContactApproved'];
let stage = 'environment preflight';
let passed = 0;
let user;
const headers = token => ({ 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) });
const encoded = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const appCheckToken = `${encoded({ alg: 'none' })}.${encoded({ sub: 'demo-local-app',
  exp: Math.floor(Date.now() / 1000) + 3600 })}.`;
const hash = value => crypto.createHash('sha256').update(value).digest('hex');

function doc(collection, id) {
  const ref = db.collection(collection).doc(id);
  ownedRefs.set(ref.path, ref);
  return ref;
}

async function test(name, body) {
  stage = name;
  await body();
  passed += 1;
  console.log('PASS', name);
}

async function createUser() {
  const response = await fetch(`${authRoot}/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: headers(), body: JSON.stringify({ returnSecureToken: true }),
  });
  assert.equal(response.status, 200, 'temporary demo Auth user must be created');
  user = await response.json();
  assert.equal(typeof user.localId, 'string', 'Auth Emulator must return a temporary UID');
  assert.equal(typeof user.idToken, 'string', 'Auth Emulator must return an ID token');
  createdUsers.add(user.localId);
  const quotaRef = doc('public_content_detail_rate_limits', hash(user.localId));
  assert.equal((await quotaRef.get()).exists, false, 'temporary user quota fixture must be unused');
  createdRefs.set(quotaRef.path, quotaRef);
}

async function call(collection, id, { authenticated = true, appCheck = true,
  invalidAppCheck = false, resetRate = true, extra = {} } = {}) {
  const quotaRef = user?.localId ? doc('public_content_detail_rate_limits', hash(user.localId)) : null;
  if (resetRate && quotaRef) await quotaRef.delete();
  const token = authenticated ? user?.idToken : null;
  const headersForRequest = { ...headers(token),
    ...(appCheck ? { 'X-Firebase-AppCheck': invalidAppCheck ? 'invalid-demo-token' : appCheckToken } : {}) };
  const response = await fetch(
    `${environment.functionsOrigin}/${environment.project}/southamerica-east1/getPublicContentDetail`,
    { method: 'POST', headers: headersForRequest, body: JSON.stringify({ data: { collection, id, ...extra } }) });
  if (quotaRef && (await quotaRef.get()).exists) createdRefs.set(quotaRef.path, quotaRef);
  let body = null;
  try { body = await response.json(); } catch (_) { /* do not print response payloads */ }
  return { status: response.status, body };
}

function source(collection, type) {
  const now = Date.now();
  const common = {
    published: true,
    active: true,
    title: `Fictional ${collection} ${type} ${runId}`,
    name: `Fictional ${collection} ${type} ${runId}`,
    category: 'Fictional test content',
    description: 'Fictional content for local integration testing.',
    ownerEmail: `private-${runId}@example.invalid`,
    privateNotes: `private-note-${runId}`,
    unknownPrivate: `unknown-${runId}`,
    salary: `unapproved-salary-${runId}`,
    eventDate: `unapproved-event-date-${runId}`,
    date: `unapproved-date-${runId}`,
  };
  if (collection === 'establishments') Object.assign(common, {
    publicContactApproved: type === 'valid',
    phone: type === 'valid' ? '+5521999999999' : '+5521888888888',
    whatsapp: type === 'valid' ? 'https://wa.me/5521999999999' : 'https://wa.me/5521888888',
    instagram: type === 'valid' ? '@approved.fixture' : '@not.approved',
    maps: 'https://maps.example.invalid/place',
  });
  if (collection === 'routes') Object.assign(common, {
    maps: 'https://maps.example.invalid/route',
    link: 'https://routes.example.invalid/details',
  });
  if (collection === 'utilities') Object.assign(common, {
    destinationType: 'internal', destination: 'waterEnergy',
    link: 'https://legacy.example.invalid',
  });
  if (type === 'unpublished') common.published = false;
  if (type === 'inactive') common.active = false;
  if (type === 'expired') common.expiresAt = admin.firestore.Timestamp.fromMillis(now - 60000);
  if (type === 'invalidDestination') Object.assign(common, {
    destinationType: 'url', destination: 'javascript:alert(1)',
  });
  if (type === 'legacyDestination') {
    delete common.destinationType;
    delete common.destination;
  }
  return common;
}

async function cleanup() {
  await Promise.all([...createdRefs.values()].map(ref => ref.delete().catch(() => {})));
  const remaining = await Promise.all([...createdRefs.values()].map(ref => ref.get()));
  assert.ok(remaining.every(snapshot => !snapshot.exists), 'all UUID-owned Firestore fixtures must be removed');
  await Promise.all([...createdUsers].map(uid => auth.deleteUser(uid).catch(() => {})));
  for (const uid of createdUsers) await assert.rejects(auth.getUser(uid), 'temporary Auth user must be removed');
}

async function main() {
  stage = 'temporary Auth fixture';
  await createUser();

  const fixtures = new Map();
  for (const collection of ['establishments', 'routes', 'utilities']) {
    const kinds = collection === 'utilities'
      ? ['valid', 'unpublished', 'inactive', 'expired', 'invalidDestination', 'legacyDestination']
      : ['valid', 'unpublished', 'inactive', 'expired'];
    const rows = new Map();
    for (const kind of kinds) {
      const id = `detail-${runId}-${collection}-${kind}`;
      rows.set(kind, { id, ref: doc(collection, id), data: source(collection, kind) });
    }
    const snapshots = await Promise.all([...rows.values()].map(row => row.ref.get()));
    assert.ok(snapshots.every(snapshot => !snapshot.exists), 'UUID detail fixture IDs must be unused');
    const batch = db.batch();
    for (const row of rows.values()) batch.create(row.ref, row.data);
    await batch.commit();
    for (const row of rows.values()) createdRefs.set(row.ref.path, row.ref);
    fixtures.set(collection, rows);
  }

  await test('available detail responses preserve ID and exact collection-specific public fields', async () => {
    const expectedFields = {
      establishments: ['active', 'category', 'description', 'maps', 'name', 'phone', 'whatsapp', 'instagram', 'published', 'title'],
      routes: ['active', 'category', 'description', 'link', 'maps', 'name', 'published', 'title'],
      utilities: ['active', 'category', 'description', 'destination', 'destinationType', 'name', 'published', 'title'],
    };
    for (const [collection, rows] of fixtures) {
      const response = await call(collection, rows.get('valid').id);
      assert.equal(response.status, 200, 'valid detail callable must return successfully');
      assert.equal(response.body?.result?.status, 'available');
      assert.equal(response.body.result.id, rows.get('valid').id, 'original document ID must be preserved');
      const data = response.body.result.data || {};
      assert.deepEqual(Object.keys(data).sort(), expectedFields[collection].sort(),
        'response must match the approved public contract exactly');
      for (const field of privateFields) {
        if (collection === 'establishments' && ['phone', 'whatsapp', 'instagram'].includes(field)) continue;
        assert.equal(data[field], undefined, 'private, unapproved, and unknown fields must be omitted');
      }
      const serialized = JSON.stringify(response.body.result);
      assert.ok(!serialized.includes(`private-${runId}`), 'response must not contain private fixture values');
      assert.ok(!serialized.includes(`unapproved-`), 'response must omit unapproved values');
    }
  });

  await test('unapproved establishment contacts are omitted while explicitly approved contacts remain public', async () => {
    const row = fixtures.get('establishments').get('unpublished');
    const ref = row.ref;
    try {
      await ref.update({ published: true, publicContactApproved: false });
      const response = await call('establishments', row.id);
      assert.equal(response.body?.result?.status, 'available');
      for (const field of ['phone', 'whatsapp', 'instagram', 'publicContactApproved']) {
        assert.equal(response.body.result.data[field], undefined, 'unapproved contact and approval flag are omitted');
      }
    } finally {
      // Restore the fixture's original publication state before later visibility assertions.
      await ref.update({ published: false, publicContactApproved: false });
    }
  });

  await test('missing, unpublished, inactive, expired, and invalidly typed utility details are unavailable', async () => {
    for (const collection of ['establishments', 'routes', 'utilities']) {
      const rows = fixtures.get(collection);
      for (const kind of ['unpublished', 'inactive', 'expired']) {
        stage = `${collection}/${kind}`;
        const response = await call(collection, rows.get(kind).id);
        assert.deepEqual(response.body?.result, { status: 'unavailable' },
          `${collection}/${kind} must be unavailable (HTTP ${response.status}; result status ${response.body?.result?.status || 'missing'})`);
      }
    }
    const utilities = fixtures.get('utilities');
    for (const kind of ['invalidDestination', 'legacyDestination']) {
      stage = `utilities/${kind}`;
      const response = await call('utilities', utilities.get(kind).id);
      assert.deepEqual(response.body?.result, { status: 'unavailable' },
        `utilities/${kind} must be unavailable (HTTP ${response.status}; result status ${response.body?.result?.status || 'missing'})`);
    }
    stage = 'routes/missing';
    const missing = await call('routes', `missing-${runId}`);
    assert.deepEqual(missing.body?.result, { status: 'unavailable' },
      `missing route must be unavailable (HTTP ${missing.status}; result status ${missing.body?.result?.status || 'missing'})`);
  });

  await test('ID and collection parameters are strictly validated before data access', async () => {
    for (const request of [
      { collection: 'establishments', id: '../invalid' },
      { collection: 'establishments', id: '' },
      { collection: 'jobs', id: `detail-${runId}-jobs` },
      { collection: 'job_private', id: `detail-${runId}-private` },
      { collection: 'routes', id: `detail-${runId}-route`, extra: { unknown: true } },
    ]) {
      assert.notEqual((await call(request.collection, request.id, { extra: request.extra || {} })).status, 200,
        'invalid or disallowed parameters must be rejected');
    }
  });

  await test('Auth, App Check, and per-user quota are enforced', async () => {
    const validId = fixtures.get('routes').get('valid').id;
    assert.notEqual((await call('routes', validId, { authenticated: false })).status, 200,
      'unauthenticated caller must be rejected');
    assert.notEqual((await call('routes', validId, { appCheck: false })).status, 200,
      'caller without App Check must be rejected');
    assert.notEqual((await call('routes', validId, { invalidAppCheck: true })).status, 200,
      'caller with invalid App Check must be rejected');
    const quota = doc('public_content_detail_rate_limits', hash(user.localId));
    await quota.set({ minute: Math.floor(Date.now() / 60000), count: 120, lastAt: Date.now() });
    createdRefs.set(quota.path, quota);
    assert.notEqual((await call('routes', validId, { resetRate: false })).status, 200,
      'request above per-user quota must be rejected');
  });

  console.log(`Public content detail Emulator: ${passed} scenarios passed; three allowlisted collections; demo only.`);
}

(async () => {
  let failure;
  try { await main(); }
  catch (error) {
    failure = error;
    console.error(`Public content detail Emulator stopped at ${stage} (${error.name}).`);
    const frames = String(error.stack || '').split('\n').filter(line => /^\s+at /.test(line)).slice(0, 8);
    if (frames.length) console.error(frames.join('\n'));
  } finally {
    try { await cleanup(); }
    catch (error) {
      console.error(`Public content detail fixture cleanup failed (${error.name}).`);
      const frames = String(error.stack || '').split('\n').filter(line => /^\s+at /.test(line)).slice(0, 5);
      if (frames.length) console.error(frames.join('\n'));
      failure ||= error;
    }
    await admin.app().delete().catch(() => {});
  }
  if (failure) process.exitCode = 1;
})();
