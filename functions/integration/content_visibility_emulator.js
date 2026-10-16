'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { readDemoEmulatorEnvironment } = require('./demo_emulator_environment');
const { localOnly } = require('../business_search');
const { PUBLIC_COLLECTIONS } = require('../content_visibility');
const { changeAdminClaim } = require('../admin_claim_management');

const environment = readDemoEmulatorEnvironment();
assert.equal(localOnly(), true, 'demo backend gate must be enabled');
const admin = require('firebase-admin');
const { Timestamp } = require('firebase-admin/firestore');
admin.initializeApp({ projectId: environment.project });
const db = admin.firestore();
const auth = admin.auth();
const root = `http://${environment.firestoreHost}/v1/projects/${environment.project}/databases/(default)/documents`;
const authRoot = `http://${environment.authHost}/identitytoolkit.googleapis.com/v1`;
const runId = crypto.randomUUID();
const prefix = `visibility-${runId}`;
const ownedRefs = new Map();
const createdRefs = new Map();
const sourceRefs = new Map();
const indexRefs = new Map();
const createdUsers = new Set();
let stage = 'environment preflight';
let passed = 0;
let visitor;
let user;
let operator;
let adminToken;
const headers = token => ({ 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) });
const encoded = value => Buffer.from(JSON.stringify(value)).toString('base64url');
const appCheckToken = `${encoded({ alg: 'none' })}.${encoded({ sub: 'demo-local-app',
  exp: Math.floor(Date.now() / 1000) + 3600 })}.`;

function doc(collection, id, { source = false, indexed = false } = {}) {
  const ref = db.collection(collection).doc(id);
  ownedRefs.set(ref.path, ref);
  if (source) sourceRefs.set(ref.path, ref);
  if (indexed) {
    const index = db.collection('business_search_index').doc(`${collection}__${id}`);
    ownedRefs.set(index.path, index);
    indexRefs.set(index.path, index);
  }
  return ref;
}

function hash(value) { return crypto.createHash('sha256').update(value).digest('hex'); }

async function test(name, body) {
  stage = name;
  await body();
  passed += 1;
  console.log('PASS', name);
}

async function account(name, anonymous = false) {
  const email = `${runId}-${name}@example.invalid`;
  const response = await fetch(`${authRoot}/accounts:signUp?key=demo-key`, {
    method: 'POST', headers: headers(),
    body: JSON.stringify(anonymous ? { returnSecureToken: true } : {
      email, password: 'LocalOnly123!', returnSecureToken: true,
    }),
  });
  assert.equal(response.status, 200, 'temporary Auth fixture must be created');
  const result = await response.json();
  assert.equal(typeof result.localId, 'string', 'Auth fixture must have a UID');
  assert.equal(typeof result.idToken, 'string', 'Auth fixture must have an ID token');
  createdUsers.add(result.localId);
  return { ...result, email };
}

async function login(accountToLogin) {
  const response = await fetch(`${authRoot}/accounts:signInWithPassword?key=demo-key`, {
    method: 'POST', headers: headers(),
    body: JSON.stringify({ email: accountToLogin.email, password: 'LocalOnly123!', returnSecureToken: true }),
  });
  assert.equal(response.status, 200, 'Admin fixture must be able to sign in');
  return (await response.json()).idToken;
}

async function call(name, data, token, appToken = appCheckToken, uid = null) {
  if (uid) await doc('public_content_rate_limits', hash(uid)).delete();
  const response = await fetch(`${environment.functionsOrigin}/${environment.project}/southamerica-east1/${name}`, {
    method: 'POST', headers: { ...headers(token), ...(appToken ? { 'X-Firebase-AppCheck': appToken } : {}) },
    body: JSON.stringify({ data }),
  });
  let body = null;
  try { body = await response.json(); } catch (_) { /* keep diagnostics value-free */ }
  return { status: response.status, body };
}

async function read(collection, id, token) {
  return (await fetch(`${root}/${collection}/${encodeURIComponent(id)}`, { headers: headers(token) })).status;
}

async function list(collection, token) {
  const response = await fetch(`${root}:runQuery`, { method: 'POST', headers: headers(token), body: JSON.stringify({
    structuredQuery: {
      from: [{ collectionId: collection }], limit: 40,
      where: { fieldFilter: { field: { fieldPath: collection === 'utilities' ? 'active' : 'published' },
        op: 'EQUAL', value: { booleanValue: true } } },
    },
  }) });
  return response.status;
}

function commonFields(collection, suffix) {
  const data = { title: `${runId} Elétrica Fictícia ${suffix}`, name: `${runId} Elétrica Fictícia ${suffix}`,
    category: 'Tecnologia', description: 'Conteúdo fictício para validação', published: true, active: true,
    open: false, targetEmail: '', ownerEmail: `private-${runId}@example.invalid`,
    privateNotes: `private-note-${runId}`, unknownPrivate: `unknown-${runId}` };
  if (collection === 'utilities') Object.assign(data, { destinationType: 'internal', destination: 'waterEnergy' });
  if (collection === 'establishments') Object.assign(data, {
    publicContactApproved: false, contact: `contact-${runId}`, phone: '+5521999999999',
    whatsapp: 'https://wa.me/5521999999999', instagram: '@fixture.macacu',
  });
  if (collection === 'routes') Object.assign(data, { maps: 'https://maps.example.invalid/fixture',
    link: 'https://routes.example.invalid/fixture', additionalInfo: 'Informação fictícia de rota' });
  if (collection === 'jobs') Object.assign(data, { contact: `contact-${runId}`, phone: '+5521999999999',
    whatsapp: 'https://wa.me/5521999999999', link: 'https://private.example.invalid',
    instagram: '@private.fixture', maps: 'https://maps.example.invalid/private',
    mapsUrl: 'https://maps.example.invalid/private-url', additionalInfo: 'private additional info fixture',
    salary: 'unapproved-salary', eventDate: 'unapproved-event-date', date: 'unapproved-date' });
  return data;
}

async function waitForIndexesToDisappear() {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const snapshots = await Promise.all([...indexRefs.values()].map(ref => ref.get()));
    if (snapshots.every(snapshot => !snapshot.exists)) return;
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  throw new Error('Owned search index cleanup did not settle.');
}

async function cleanup() {
  if (operator?.localId) {
    const auditRows = await db.collection('admin_claim_changes').where('uid', '==', operator.localId).get();
    for (const snapshot of auditRows.docs) ownedRefs.set(snapshot.ref.path, snapshot.ref);
  }
  await Promise.all([...sourceRefs.values()].filter(ref => createdRefs.has(ref.path))
    .map(ref => ref.delete().catch(() => {})));
  const ownedIndexes = [...indexRefs.values()].filter(ref => createdRefs.has(ref.path));
  if (ownedIndexes.length) {
    const deadline = Date.now() + 15000;
    while (Date.now() < deadline) {
      const snapshots = await Promise.all(ownedIndexes.map(ref => ref.get()));
      if (snapshots.every(snapshot => !snapshot.exists)) break;
      await new Promise(resolve => setTimeout(resolve, 200));
    }
  }
  await Promise.all([...createdRefs.values()].map(ref => ref.delete().catch(() => {})));
  const remaining = await Promise.all([...createdRefs.values()].map(ref => ref.get()));
  assert.ok(remaining.every(snapshot => !snapshot.exists), 'all UUID-owned Firestore fixtures must be removed');
  await Promise.all([...createdUsers].map(uid => auth.deleteUser(uid).catch(() => {})));
  for (const uid of createdUsers) {
    await assert.rejects(auth.getUser(uid), 'temporary Auth user must be removed');
  }
}

async function restCreate(collection, id, token, fields) {
  return fetch(`${root}/${collection}?documentId=${encodeURIComponent(id)}`, {
    method: 'POST', headers: { ...headers(token), 'content-type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
}

async function restUpdate(collection, id, token, fields) {
  return fetch(`${root}/${collection}/${encodeURIComponent(id)}?updateMask.fieldPaths=title`, {
    method: 'PATCH', headers: { ...headers(token), 'content-type': 'application/json' },
    body: JSON.stringify({ fields }),
  });
}

async function restDelete(collection, id, token) {
  return fetch(`${root}/${collection}/${encodeURIComponent(id)}`, { method: 'DELETE', headers: headers(token) });
}

async function main() {
  stage = 'Auth fixtures';
  visitor = await account('visitor', true);
  user = await account('user');
  operator = await account('admin');
  const authorizationRef = doc('admin_authorizations', operator.localId);
  assert.equal((await authorizationRef.get()).exists, false, 'UUID Admin authorization fixture must be unused');
  const adminMutation = await changeAdminClaim({ auth, db, uid: operator.localId, action: 'grant',
    operator: 'visibility-test', reason: 'demo-only', apply: true,
    confirmation: `${environment.project}:${operator.localId}:grant` });
  createdRefs.set(authorizationRef.path, authorizationRef);
  if (adminMutation.auditId) {
    const auditRef = doc('admin_claim_changes', adminMutation.auditId);
    createdRefs.set(auditRef.path, auditRef);
  }
  adminToken = await login(operator);
  for (const collection of ['public_content_rate_limits', 'business_search_rate_limits']) {
    const rateRef = doc(collection, hash(user.localId));
    assert.equal((await rateRef.get()).exists, false, 'temporary user rate fixture must be unused');
    createdRefs.set(rateRef.path, rateRef);
  }

  const fixturesByCollection = new Map();
  for (const collection of PUBLIC_COLLECTIONS) {
    const base = commonFields(collection, 'public');
    const legacy = { published: true, title: `${runId} Legacy fixture`, targetEmail: '' };
    if (collection === 'utilities') {
      delete legacy.published;
      legacy.active = true;
      legacy.link = 'https://legacy.example.invalid';
    }
    const fixtures = {
      good: base,
      unpublished: { ...base, published: false },
      inactive: { ...base, active: false },
      expired: { ...base, expiresAt: Timestamp.fromMillis(Date.now() - 60000) },
      future: { ...base, expiresAt: Timestamp.fromMillis(Date.now() + 3600000) },
      malformed: { ...base, expiresAt: null },
      legacy,
    };
    if (collection === 'utilities') fixtures.invalidDestination = { ...base,
      destinationType: 'url', destination: 'javascript:alert(1)' };
    if (collection === 'establishments') {
      fixtures.contactUnapproved = { ...base, name: `${runId} Contact unapproved`,
        publicContactApproved: false, phone: '+5521888888888', whatsapp: 'https://wa.me/5521888888888',
        instagram: '@not-approved' };
      fixtures.contactApproved = { ...base, name: `${runId} Contact approved`,
        publicContactApproved: true, phone: '+5521777777777', whatsapp: 'https://wa.me/5521777777777',
        instagram: '@approved.fixture' };
    }
    fixturesByCollection.set(collection, fixtures);
    const refs = Object.entries(fixtures).map(([kind]) => doc(collection, `${prefix}-${kind}`, {
      source: true, indexed: ['establishments', 'routes', 'news', 'events', 'jobs'].includes(collection),
    }));
    const existing = await Promise.all(refs.map(ref => ref.get()));
    assert.ok(existing.every(snapshot => !snapshot.exists), 'UUID Firestore fixture IDs must be unused');
    const generatedIndexes = ['establishments', 'routes', 'news', 'events', 'jobs'].includes(collection)
      ? refs.map(ref => db.collection('business_search_index').doc(`${collection}__${ref.id}`)) : [];
    const existingIndexes = await Promise.all(generatedIndexes.map(ref => ref.get()));
    assert.ok(existingIndexes.every(snapshot => !snapshot.exists), 'UUID search-index fixture IDs must be unused');
    const batch = db.batch();
    for (const [kind, data] of Object.entries(fixtures)) batch.create(doc(collection, `${prefix}-${kind}`), data);
    await batch.commit();
    for (const ref of refs) createdRefs.set(ref.path, ref);
    for (const ref of generatedIndexes) {
      ownedRefs.set(ref.path, ref);
      indexRefs.set(ref.path, ref);
      createdRefs.set(ref.path, ref); // Own the trigger result only after its path was proven unused.
    }
  }

  const privateJobId = `${prefix}-private-job`;
  const privateJob = doc('jobs', privateJobId, { source: true });
  const privateJobData = doc('job_private', privateJobId, { source: true });
  assert.equal((await privateJob.get()).exists, false, 'UUID private job fixture must be unused');
  assert.equal((await privateJobData.get()).exists, false, 'UUID private data fixture must be unused');
  await privateJob.create({ published: true, active: true,
    title: 'Private fixture job', contact: `private-contact-${runId}` });
  createdRefs.set(privateJob.path, privateJob);
  await privateJobData.create({ contact: `private-contact-${runId}` });
  createdRefs.set(privateJobData.path, privateJobData);

  await test('direct document access follows current Rules, including public jobs denial', async () => {
    for (const [collection, fixtures] of fixturesByCollection) {
      for (const token of [undefined, visitor.idToken, user.idToken]) {
        for (const kind of Object.keys(fixtures)) {
          const visible = ['good', 'future', 'legacy', 'contactUnapproved', 'contactApproved',
            'invalidDestination'].includes(kind);
          const expected = collection === 'jobs' ? 403 : (visible ? 200 : 403);
          assert.equal(await read(collection, `${prefix}-${kind}`, token), expected,
            `unexpected direct get result for ${collection} fixture`);
        }
        assert.equal(await list(collection, token), 403, 'ordinary clients cannot list the collection directly');
      }
      for (const kind of Object.keys(fixtures)) {
        assert.equal(await read(collection, `${prefix}-${kind}`, adminToken), 200,
          'authorized Admin can read administrative content');
      }
      assert.equal(await list(collection, adminToken), 200, 'authorized Admin can list administrative content');
    }
    for (const token of [undefined, visitor.idToken, user.idToken]) {
      assert.equal(await read('jobs', privateJobId, token), 403, 'jobs are never directly readable by public clients');
      assert.equal(await read('job_private', privateJobId, token), 403, 'private job data is never public');
    }
    assert.equal(await read('jobs', privateJobId, adminToken), 200, 'Admin can read the job document');
    assert.equal(await read('job_private', privateJobId, adminToken), 200, 'Admin can read private job data');
  });

  await test('listPublicContent applies each safe projection and visibility policy', async () => {
    for (const collection of PUBLIC_COLLECTIONS) {
      const response = await call('listPublicContent', { collection, limit: 40 }, user.idToken,
        appCheckToken, user.localId);
      assert.equal(response.status, 200, 'public content callable must succeed for valid demo requests');
      const items = response.body?.result?.items?.filter(item => item.id.startsWith(prefix)) || [];
      const actualKinds = items.map(item => item.id.slice(prefix.length + 1)).sort();
      const expectedKinds = collection === 'utilities' ? ['good', 'future']
        : collection === 'establishments' ? ['good', 'future', 'legacy', 'contactUnapproved', 'contactApproved']
          : collection === 'jobs' ? ['good', 'future', 'legacy', 'private-job']
            : ['good', 'future', 'legacy'];
      if (JSON.stringify(actualKinds) !== JSON.stringify([...expectedKinds].sort())) {
        console.error(JSON.stringify({ collection, returnedFixtureKinds: actualKinds,
          expectedFixtureKinds: [...expectedKinds].sort() }));
      }
      assert.deepEqual(actualKinds, [...expectedKinds].sort(),
        `only visible and safely projectable fixtures are returned for ${collection}`);
      for (const item of items) {
        for (const field of ['ownerEmail', 'privateNotes', 'targetEmail', 'unknownPrivate']) {
          assert.equal(item.data[field], undefined, 'private or unknown field must be omitted');
        }
        if (['establishments', 'jobs'].includes(collection)) {
          assert.equal(item.data.contact, undefined, 'administrative contact must be omitted');
        }
        if (collection === 'jobs') {
          for (const field of ['phone', 'whatsapp', 'link', 'instagram', 'maps', 'mapsUrl', 'additionalInfo',
            'salary', 'eventDate', 'date']) {
            assert.equal(item.data[field], undefined, 'unapproved job data must be omitted');
          }
        }
        if (collection === 'establishments' && item.id === `${prefix}-contactUnapproved`) {
          for (const field of ['phone', 'whatsapp', 'instagram']) {
            assert.equal(item.data[field], undefined, 'commercial contact needs explicit approval');
          }
        }
        if (collection === 'establishments' && item.id === `${prefix}-contactApproved`) {
          assert.equal(item.data.phone, '+5521777777777', 'approved public business phone is retained');
          assert.equal(item.data.whatsapp, 'https://wa.me/5521777777777', 'approved public WhatsApp is retained');
          assert.equal(item.data.instagram, '@approved.fixture', 'approved public Instagram is retained');
          assert.equal(item.data.publicContactApproved, undefined, 'approval metadata is not returned');
        }
      }
    }
  });

  await test('public Firestore writes are denied while Admin CRUD remains available', async () => {
    const publicCreateId = `${prefix}-public-write-attempt`;
    const publicCreateRef = doc('jobs', publicCreateId);
    assert.equal((await publicCreateRef.get()).exists, false, 'public create UUID must be unused');
    const publicCreate = await restCreate('jobs', publicCreateId, user.idToken, {
      title: { stringValue: 'Denied public fixture' }, published: { booleanValue: true },
    });
    assert.equal(publicCreate.status, 403, 'ordinary client create must be denied');
    assert.equal(await restUpdate('jobs', `${prefix}-good`, user.idToken,
      { title: { stringValue: 'Denied update' } }).then(response => response.status), 403,
    'ordinary client update must be denied');
    assert.equal(await restDelete('jobs', `${prefix}-good`, user.idToken).then(response => response.status), 403,
      'ordinary client delete must be denied');

    const adminDocId = `${prefix}-admin-crud`;
    const adminDoc = doc('offers', adminDocId, { source: true });
    assert.equal((await adminDoc.get()).exists, false, 'Admin CRUD UUID must be unused');
    const create = await restCreate('offers', adminDocId, adminToken, {
      title: { stringValue: 'Authorized Admin fixture' }, published: { booleanValue: true },
    });
    assert.equal(create.status, 200, 'authorized Admin create must succeed');
    createdRefs.set(adminDoc.path, adminDoc);
    assert.equal(await restUpdate('offers', adminDocId, adminToken,
      { title: { stringValue: 'Authorized Admin updated' } }).then(response => response.status), 200,
    'authorized Admin update must succeed');
    assert.equal(await restDelete('offers', adminDocId, adminToken).then(response => response.status), 200,
      'authorized Admin delete must succeed');
    await adminDoc.delete();

    const privateId = `${prefix}-private-crud`;
    const privateDoc = doc('job_private', privateId);
    assert.equal((await privateDoc.get()).exists, false, 'private CRUD UUID must be unused');
    assert.equal((await restCreate('job_private', privateId, user.idToken, {
      contact: { stringValue: 'denied' },
    })).status, 403, 'ordinary client cannot create private job data');
    await db.collection('job_private').doc(privateId).create({ contact: 'fictional admin data' });
    createdRefs.set(privateDoc.path, privateDoc);
    assert.equal((await restUpdate('job_private', privateId, user.idToken,
      { contact: { stringValue: 'denied' } })).status, 403, 'ordinary client cannot update private job data');
    assert.equal((await restDelete('job_private', privateId, user.idToken)).status, 403,
      'ordinary client cannot delete private job data');
    const adminPrivateId = `${prefix}-admin-private-crud`;
    const adminPrivateDoc = doc('job_private', adminPrivateId);
    assert.equal((await restCreate('job_private', adminPrivateId, adminToken, {
      contact: { stringValue: 'fictional Admin data' },
    })).status, 200, 'authorized Admin can create private job data');
    assert.equal((await restUpdate('job_private', adminPrivateId, adminToken,
      { contact: { stringValue: 'updated fictional Admin data' } })).status, 200,
    'authorized Admin can update private job data');
    assert.equal((await restDelete('job_private', adminPrivateId, adminToken)).status, 200,
      'authorized Admin can delete private job data');
    assert.equal((await restUpdate('job_private', privateId, adminToken,
      { contact: { stringValue: 'authorized update' } })).status, 200,
    'authorized Admin can update private job data');
    assert.equal((await restDelete('job_private', privateId, adminToken)).status, 200,
      'authorized Admin can delete private job data');
    await privateDoc.delete();
  });

  await test('Backend rejects missing Auth/App Check and invalid collection, limits, and cursors', async () => {
    for (const token of [undefined, 'invalid-local-token']) {
      assert.notEqual((await call('listPublicContent', { collection: 'news', limit: 10 }, token)).status, 200,
        'missing or invalid Auth must be rejected');
    }
    for (const token of [null, 'invalid-app']) {
      assert.notEqual((await call('listPublicContent', { collection: 'news', limit: 10 }, user.idToken, token)).status, 200,
        'missing or invalid App Check must be rejected');
    }
    for (const data of [{ collection: 'users', limit: 10 }, { collection: 'news', limit: 999 },
      { collection: 'news', limit: 1, cursor: '../bad' }]) {
      assert.notEqual((await call('listPublicContent', data, user.idToken)).status, 200,
        'invalid request parameters must be rejected');
    }
  });

  await test('Pagination preserves real IDs and returns distinct pages', async () => {
    const first = await call('listPublicContent', { collection: 'ads', limit: 1 }, user.idToken,
      appCheckToken, user.localId);
    assert.equal(first.status, 200);
    assert.equal(first.body?.result?.items?.length, 1);
    const cursor = first.body.result.nextCursor;
    assert.equal(typeof cursor, 'string');
    const second = await call('listPublicContent', { collection: 'ads', limit: 1, cursor }, user.idToken,
      appCheckToken, user.localId);
    assert.equal(second.status, 200);
    assert.notEqual(first.body.result.items[0].id, second.body.result.items[0].id);
  });

  await test('Search index and rate documents are inaccessible to public clients', async () => {
    const indexRef = doc('business_search_index', `establishments__${prefix}-good`, { indexed: true });
    const deadline = Date.now() + 30000;
    while (!(await indexRef.get()).exists && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 200));
    assert.equal((await indexRef.get()).exists, true, 'establishment trigger should create its private index');
    for (const token of [undefined, visitor.idToken, user.idToken]) {
      assert.equal(await read('business_search_index', indexRef.id, token), 403);
      assert.equal(await read('business_search_rate_limits', hash(user.localId), token), 403);
      assert.equal(await read('public_content_rate_limits', hash(user.localId), token), 403);
    }
  });

  await test('Revoked Admin loses restricted jobs, private-job, and administrative-list access', async () => {
    const revoked = await changeAdminClaim({ auth, db, uid: operator.localId, action: 'revoke',
      operator: 'visibility-test', reason: 'demo-only', apply: true,
      confirmation: `${environment.project}:${operator.localId}:revoke` });
    if (revoked.auditId) {
      const auditRef = doc('admin_claim_changes', revoked.auditId);
      createdRefs.set(auditRef.path, auditRef);
    }
    for (const collection of PUBLIC_COLLECTIONS) {
      const expected = collection === 'jobs' ? 403 : 200;
      assert.equal(await read(collection, `${prefix}-good`, adminToken), expected,
        'revoked Admin keeps only ordinary public get access');
      assert.equal(await list(collection, adminToken), 403, 'revoked Admin cannot list administrative collections');
    }
    assert.equal(await read('job_private', privateJobId, adminToken), 403,
      'revoked Admin cannot read private job data');
  });

  console.log(`Visibility Emulator: ${passed} scenarios passed; project=${environment.project}; fixtures are UUID-scoped.`);
}

(async () => {
  let failure;
  try { await main(); }
  catch (error) {
    failure = error;
    console.error(`Visibility Emulator stopped at ${stage} (${error.name}).`);
    const frames = String(error.stack || '').split('\n').filter(line => /^\s+at /.test(line)).slice(0, 8);
    if (frames.length) console.error(frames.join('\n'));
  } finally {
    try { await cleanup(); }
    catch (error) {
      console.error(`Visibility Emulator fixture cleanup failed (${error.name}).`);
      const frames = String(error.stack || '').split('\n').filter(line => /^\s+at /.test(line)).slice(0, 5);
      if (frames.length) console.error(frames.join('\n'));
      failure ||= error;
    }
    await admin.app().delete().catch(() => {});
  }
  if (failure) process.exitCode = 1;
})();
