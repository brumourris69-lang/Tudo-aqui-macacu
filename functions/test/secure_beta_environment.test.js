'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {
  BETA_FIREBASE_PROJECT_ID,
  betaBackendAllowed,
  betaProjectContext,
} = require('../secure_beta_environment');

function validEnv() {
  return {
    GCLOUD_PROJECT: BETA_FIREBASE_PROJECT_ID,
    GOOGLE_CLOUD_PROJECT: BETA_FIREBASE_PROJECT_ID,
    FIREBASE_CONFIG: JSON.stringify({ projectId: BETA_FIREBASE_PROJECT_ID }),
  };
}

test('Beta gate requires matching exact Firebase and Admin project identities', () => {
  const env = validEnv();
  assert.equal(betaBackendAllowed({ env, adminProjectId: BETA_FIREBASE_PROJECT_ID }), true);
  for (const candidate of [
    { ...env, GCLOUD_PROJECT: 'tudo-aqui-macacu' },
    { ...env, GOOGLE_CLOUD_PROJECT: 'tudo-aqui-macacu' },
    { ...env, FIREBASE_CONFIG: JSON.stringify({ projectId: 'tudo-aqui-macacu' }) },
    { ...env, FIREBASE_CONFIG: '{invalid' },
    { ...env, GCLOUD_PROJECT: 'macacu-beta-261030-cf4a81-other' },
  ]) assert.equal(betaBackendAllowed({ env: candidate, adminProjectId: BETA_FIREBASE_PROJECT_ID }), false);
  assert.equal(betaBackendAllowed({ env, adminProjectId: 'tudo-aqui-macacu' }), false);
  assert.equal(betaBackendAllowed({ env: {}, adminProjectId: BETA_FIREBASE_PROJECT_ID }), false);
});

test('Beta gate rejects emulator endpoints and every other project', () => {
  for (const key of [
    'FUNCTIONS_EMULATOR', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'PUBSUB_EMULATOR_HOST', 'FIREBASE_EMULATOR_HUB',
  ]) {
    assert.equal(betaBackendAllowed({
      env: { ...validEnv(), [key]: key === 'FUNCTIONS_EMULATOR' ? 'false' : '127.0.0.1:8087' },
      adminProjectId: BETA_FIREBASE_PROJECT_ID,
    }), false, key);
  }
  for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'GOOGLE_CLOUD_KEYFILE_JSON', 'FIREBASE_TOKEN',
    'STAGING_FIREBASE_PROJECT_ID']) {
    assert.equal(betaBackendAllowed({ env: { ...validEnv(), [key]: 'unexpected-value' },
      adminProjectId: BETA_FIREBASE_PROJECT_ID }), false, key);
  }
  for (const projectId of ['tudo-aqui-macacu', 'macacu-staging-261022', 'demo-universal-search', 'other-project']) {
    assert.equal(betaBackendAllowed({
      env: { GCLOUD_PROJECT: projectId, GOOGLE_CLOUD_PROJECT: projectId,
        FIREBASE_CONFIG: JSON.stringify({ projectId }) }, adminProjectId: projectId,
    }), false, projectId);
  }
});

test('Beta context suppresses normal backend discovery even when its gate fails', () => {
  assert.equal(betaProjectContext({ env: validEnv() }), true);
  assert.equal(betaProjectContext({ env: {}, adminProjectId: BETA_FIREBASE_PROJECT_ID }), true);
  assert.equal(betaProjectContext({ env: { GCLOUD_PROJECT: 'tudo-aqui-macacu' } }), false);
});

test('Beta entrypoint exports only the public catalog and bounded search functions', () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const env = validEnv();
  const exported = {};
  const calls = [];
  const admin = { initializeApp() {}, app: () => ({ options: { projectId: BETA_FIREBASE_PROJECT_ID } }), firestore: () => ({}) };
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return admin;
    if (name === 'firebase-admin/firestore') return { FieldValue: { serverTimestamp() {} } };
    if (name === 'firebase-functions/v2/https') return { onCall: (options, handler) => ({ options, handler }), HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({ value: () => '' }) };
    if (name === './business_search') return { localOnly: () => false };
    if (name === './secure_staging_environment') return { stagingBackendAllowed: () => false, stagingProjectContext: () => false };
    if (name === './secure_beta_environment') return { betaBackendAllowed: args => betaBackendAllowed({ ...args, env }), betaProjectContext };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './public_content') return {
      registerBetaPublicContent: () => {
        calls.push('beta-public-content');
        return { listPublicContent() {}, getPublicContentDetail() {} };
      },
      registerPublicContent: () => { throw new Error('Normal registrar must not run for Beta.'); },
      registerStagingPublicContent: () => { throw new Error('Staging registrar must not run for Beta.'); },
    };
    if (name === './beta_public_search') return {
      registerBetaPublicSearch: () => {
        calls.push('beta-public-search');
        return {
          searchPublicContent() {},
          syncBetaSearchEstablishments() {},
          syncBetaSearchRoutes() {},
          syncBetaSearchEvents() {},
        };
      },
    };
    if (name === './user_operations' || name === './admin_job_management') {
      throw new Error('Admin and user operation modules must not be loaded for Beta.');
    }
    if (name === './home_image_upload') return { uploadHomeImage: async () => {}, UploadError: Error };
    if (name === './notification_delivery') return { notificationTarget() {}, loadTargetDevices() {}, sendPushBatch() {} };
    if (name === './admin_authorization') return { authorizeCurrentAdmin() {} };
    throw new Error(`Unexpected import: ${name}`);
  };

  vm.runInNewContext(source, { require: fakeRequire, exports: exported, process: { env }, Buffer, URL, console });
  assert.deepEqual(Object.keys(exported).sort(), [
    'getPublicContentDetail', 'listPublicContent', 'searchPublicContent',
    'syncBetaSearchEstablishments', 'syncBetaSearchEvents', 'syncBetaSearchRoutes',
  ]);
  assert.deepEqual(calls, ['beta-public-content', 'beta-public-search']);
});

test('Beta public registrar keeps App Check and rejects a mismatched deployment identity', () => {
  const { registerBetaPublicContent } = require('../public_content');
  const admin = { app: () => ({ options: { projectId: BETA_FIREBASE_PROJECT_ID } }), firestore: () => ({}) };
  const handlers = registerBetaPublicContent({ admin, env: validEnv(), HttpsError: Error,
    onCall: (options, handler) => ({ options, handler }) });
  assert.deepEqual(Object.keys(handlers).sort(), ['getPublicContentDetail', 'listPublicContent']);
  assert.equal(handlers.listPublicContent.options.enforceAppCheck, true);
  assert.equal(handlers.getPublicContentDetail.options.enforceAppCheck, true);
  assert.throws(() => registerBetaPublicContent({ admin, env: { ...validEnv(),
    GCLOUD_PROJECT: 'tudo-aqui-macacu' }, HttpsError: Error, onCall: (_, handler) => handler }));
});

test('Beta public search retains App Check and indexes only its public source collections', () => {
  const { registerBetaPublicSearch } = require('../beta_public_search');
  const admin = {
    app: () => ({ options: { projectId: BETA_FIREBASE_PROJECT_ID } }),
    firestore: () => ({}),
  };
  const registrations = [];
  const handlers = registerBetaPublicSearch({
    admin,
    env: validEnv(),
    HttpsError: Error,
    onCall: (options, handler) => ({ options, handler }),
    onDocumentWritten: (options, handler) => {
      registrations.push(options.document);
      return { options, handler };
    },
  });
  assert.deepEqual(Object.keys(handlers).sort(), [
    'searchPublicContent', 'syncBetaSearchEstablishments',
    'syncBetaSearchEvents', 'syncBetaSearchRoutes',
  ]);
  assert.equal(handlers.searchPublicContent.options.enforceAppCheck, true);
  assert.deepEqual(registrations.sort(), [
    'establishments/{id}', 'events/{id}', 'routes/{id}',
  ]);
  assert.throws(() => registerBetaPublicSearch({
    admin,
    env: { ...validEnv(), GCLOUD_PROJECT: 'tudo-aqui-macacu' },
    HttpsError: Error,
    onCall: (options, handler) => ({ options, handler }),
    onDocumentWritten: (options, handler) => ({ options, handler }),
  }));
});

test('Beta public search rejects missing App Check before touching Firestore', async () => {
  const { registerBetaPublicSearch } = require('../beta_public_search');
  let firestoreTouched = false;
  const admin = {
    app: () => ({ options: { projectId: BETA_FIREBASE_PROJECT_ID } }),
    firestore: () => ({
      collection: () => { firestoreTouched = true; throw new Error('must not read'); },
    }),
  };
  class FakeHttpsError extends Error {
    constructor(code, message) { super(message); this.code = code; }
  }
  const handlers = registerBetaPublicSearch({
    admin,
    env: validEnv(),
    HttpsError: FakeHttpsError,
    onCall: (options, handler) => ({ options, handler }),
    onDocumentWritten: (options, handler) => ({ options, handler }),
  });
  await assert.rejects(handlers.searchPublicContent.handler({
    data: { query: 'padaria', filter: 'all', limit: 20 },
    auth: null,
    app: null,
  }), error => error.code === 'failed-precondition');
  assert.equal(firestoreTouched, false);
});

test('Beta context prevents fallback to the normal backend on identity mismatch', () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const env = { GCLOUD_PROJECT: 'tudo-aqui-macacu', SECURE_BACKEND_ENABLED: 'true',
    FIREBASE_CONFIG: JSON.stringify({ projectId: BETA_FIREBASE_PROJECT_ID }) };
  const exported = {};
  const admin = { initializeApp() {}, app: () => ({ options: { projectId: BETA_FIREBASE_PROJECT_ID } }), firestore: () => ({}) };
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return admin;
    if (name === 'firebase-admin/firestore') return { FieldValue: { serverTimestamp() {} } };
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => ({ handler }), HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({ value: () => '' }) };
    if (name === './business_search') return { localOnly: () => false };
    if (name === './secure_staging_environment') return { stagingBackendAllowed: () => false, stagingProjectContext: () => false };
    if (name === './secure_beta_environment') return { betaBackendAllowed: args => betaBackendAllowed({ ...args, env }), betaProjectContext };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './public_content' || name === './user_operations' || name === './admin_job_management') {
      throw new Error('Mismatched Beta identity must not load any backend surface.');
    }
    if (name === './home_image_upload') return { uploadHomeImage: async () => {}, UploadError: Error };
    if (name === './notification_delivery') return { notificationTarget() {}, loadTargetDevices() {}, sendPushBatch() {} };
    if (name === './admin_authorization') return { authorizeCurrentAdmin() {} };
    throw new Error(`Unexpected import: ${name}`);
  };
  vm.runInNewContext(source, { require: fakeRequire, exports: exported, process: { env }, Buffer, URL, console });
  assert.deepEqual(Object.keys(exported), []);
});
