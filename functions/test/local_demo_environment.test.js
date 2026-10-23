'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  seedSearchLocalFixtures,
  provisionSearchLocalAdmin,
  requireSearchLocalEnvironment,
} = require('../local_demo_environment');

function demoEnvironment() {
  return {
    GCLOUD_PROJECT: 'demo-universal-search',
    FUNCTIONS_EMULATOR: 'true',
    FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087',
    FUNCTIONS_EMULATOR_HOST: '127.0.0.1:5007',
    FUNCTIONS_EMULATOR_PORT: '5007',
  };
}

function fakeFirestore() {
  const documents = new Map();
  const ref = (collection, id) => ({ collection, id, key: `${collection}/${id}` });
  return {
    documents,
    collection: (collection) => ({ doc: (id) => ref(collection, id) }),
    runTransaction: async (work) => work({
      get: async (document) => ({ exists: documents.has(document.key) }),
      create: (document, data) => {
        if (documents.has(document.key)) throw new Error('already exists');
        documents.set(document.key, structuredClone(data));
      },
    }),
  };
}

test('local fixture seed creates only absent fictional records and is repeatable', async () => {
  const db = fakeFirestore();
  const env = demoEnvironment();
  const first = await seedSearchLocalFixtures({ db, env });
  assert.equal(first.created, 4);
  assert.equal(first.preserved, 0);
  assert.equal(first.conflicts, 0);
  assert.equal(db.documents.get('jobs/local-demo-job-assistant')?.title,
    'Vaga fictícia de demonstração');
  assert.equal(db.documents.get('job_private/local-demo-job-assistant')?.contact,
    'contato-ficticio@example.invalid');
  assert.equal(db.documents.has('job_private/local-demo-job-assistant/'), false);
  const original = structuredClone(db.documents.get('establishments/local-demo-establishment'));
  db.documents.get('establishments/local-demo-establishment').name = 'edited locally';

  const second = await seedSearchLocalFixtures({ db, env });
  assert.equal(second.created, 0);
  assert.equal(second.preserved, 4);
  assert.equal(second.conflicts, 0);
  assert.equal(db.documents.get('establishments/local-demo-establishment').name,
    'edited locally');
  assert.equal(original.published, true);
});

test('a half-existing public/private job pair is reported and left untouched', async () => {
  const db = fakeFirestore();
  db.documents.set('jobs/local-demo-job-assistant', { title: 'Existing public value' });
  const result = await seedSearchLocalFixtures({ db, env: demoEnvironment() });
  assert.equal(result.conflicts, 1);
  assert.equal(result.created, 3);
  assert.equal(db.documents.get('jobs/local-demo-job-assistant').title,
    'Existing public value');
  assert.equal(db.documents.has('job_private/local-demo-job-assistant'), false);
});

test('local setup refuses project, emulator host, or confirmation mismatches', () => {
  const env = demoEnvironment();
  assert.throws(() => requireSearchLocalEnvironment({ ...env, GCLOUD_PROJECT: 'tudo-aqui-macacu' }),
    /local demo environment/);
  assert.throws(() => requireSearchLocalEnvironment({ ...env, FIRESTORE_EMULATOR_HOST: '192.0.2.2:8087' }),
    /local demo environment/);
  assert.throws(() => requireSearchLocalEnvironment({ ...env, GOOGLE_APPLICATION_CREDENTIALS: 'adc.json' }),
    /local demo environment/);
  assert.throws(() => requireSearchLocalEnvironment({
    ...env, FIREBASE_CONFIG: JSON.stringify({ projectId: 'tudo-aqui-macacu' }),
  }), /Local Firebase identity/);
  assert.throws(() => requireSearchLocalEnvironment(env, 'wrong-project'),
    /local demo environment/);
});

test('Admin bootstrap creates a new local identity and grants versioned authorization', async () => {
  const env = demoEnvironment();
  let grantRequest;
  const account = { uid: 'fixture-owner-uid', email: 'owner@example.invalid', customClaims: {} };
  const auth = {
    getUserByEmail: async () => { throw Object.assign(new Error('missing'), { code: 'auth/user-not-found' }); },
    createUser: async ({ email, password }) => {
      assert.equal(email, account.email);
      assert.equal(password, 'never-logged-password');
      return account;
    },
    getUser: async () => ({ ...account, customClaims: { admin: true, adminVersion: 'v1' } }),
  };
  const db = {
    collection: (name) => ({ doc: () => ({ get: async () => ({ data: () =>
      name === 'admin_authorizations'
        ? { enabled: true, pending: false, version: 'v1' }
        : undefined }) }) }),
  };
  const result = await provisionSearchLocalAdmin({
    auth, db, env, email: account.email, password: 'never-logged-password',
    confirmation: 'demo-universal-search',
    grantAdmin: async (input) => { grantRequest = input; return { dryRun: false }; },
  });
  assert.equal(result.project, 'demo-universal-search');
  assert.equal(result.uid, account.uid);
  assert.deepEqual(grantRequest, {
    auth, db, uid: account.uid, action: 'grant', operator: 'local-owner-setup',
    reason: 'Fictional local demo owner account',
    confirmation: `demo-universal-search:${account.uid}:grant`, apply: true, env,
  });
  assert.equal(JSON.stringify(result).includes('never-logged-password'), false);
});

test('Admin bootstrap refuses existing identities and does not disclose credentials', async () => {
  const password = 'never-logged-password';
  await assert.rejects(() => provisionSearchLocalAdmin({
    auth: { getUserByEmail: async () => ({ uid: 'existing' }) },
    db: {}, env: demoEnvironment(), email: 'owner@example.invalid', password,
    confirmation: 'demo-universal-search',
  }), /already exists/);
});
