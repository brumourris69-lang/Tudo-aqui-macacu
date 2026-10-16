'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { stagingBackendAllowed, stagingProjectContext } = require('../secure_staging_environment');

const project = 'tudo-aqui-macacu-staging';
const valid = () => ({ STAGING_BACKEND_ENABLED: 'true',
  STAGING_FIREBASE_PROJECT_ID: project, GCLOUD_PROJECT: project });

test('staging gate requires explicit opt-in and matching external, runtime, and Admin project IDs', () => {
  assert.equal(stagingBackendAllowed({ env: valid(), adminProjectId: project }), true);
  for (const env of [
    { ...valid(), STAGING_BACKEND_ENABLED: 'false' },
    { ...valid(), STAGING_BACKEND_ENABLED: undefined },
    { ...valid(), STAGING_FIREBASE_PROJECT_ID: '' },
    { ...valid(), GCLOUD_PROJECT: 'another-project' },
  ]) assert.equal(stagingBackendAllowed({ env, adminProjectId: project }), false);
  assert.equal(stagingBackendAllowed({ env: valid(), adminProjectId: 'another-project' }), false);
  assert.equal(stagingBackendAllowed({ env: valid(), adminProjectId: '' }), false);
});

test('staging gate accepts only project IDs explicitly named for staging or homologation', () => {
  for (const projectId of ['tudo-aqui-macacu-staging', 'tudo-aqui-macacu-homologacao']) {
    const env = { STAGING_BACKEND_ENABLED: 'true', STAGING_FIREBASE_PROJECT_ID: projectId,
      GCLOUD_PROJECT: projectId };
    assert.equal(stagingBackendAllowed({ env, adminProjectId: projectId }), true, projectId);
  }
  for (const projectId of ['unrelated-firebase-project', 'tudo-aqui-macacu-stage', 'tudo-aqui-macacu-production']) {
    const env = { STAGING_BACKEND_ENABLED: 'true', STAGING_FIREBASE_PROJECT_ID: projectId,
      GCLOUD_PROJECT: projectId };
    assert.equal(stagingBackendAllowed({ env, adminProjectId: projectId }), false, projectId);
  }
});

test('staging gate rejects production, demo, and every configured emulator environment', () => {
  for (const forbidden of ['tudo-aqui-macacu', 'demo-universal-search']) {
    const env = { ...valid(), STAGING_FIREBASE_PROJECT_ID: forbidden, GCLOUD_PROJECT: forbidden };
    assert.equal(stagingBackendAllowed({ env, adminProjectId: forbidden }), false);
  }
  for (const key of ['FUNCTIONS_EMULATOR', 'FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST',
    'PUBSUB_EMULATOR_HOST', 'FIREBASE_EMULATOR_HUB']) {
    assert.equal(stagingBackendAllowed({ env: { ...valid(), [key]: key === 'FUNCTIONS_EMULATOR' ? 'false' : '127.0.0.1:8087' },
      adminProjectId: project }), false, key);
  }
});

test('staging gate rejects conflicting Google project identity and explicit credentials', () => {
  for (const env of [
    { ...valid(), GOOGLE_CLOUD_PROJECT: 'tudo-aqui-macacu' },
    { ...valid(), GOOGLE_APPLICATION_CREDENTIALS: 'service-account.json' },
    { ...valid(), FIREBASE_TOKEN: 'token' },
    { ...valid(), FIREBASE_CONFIG: JSON.stringify({ projectId: 'tudo-aqui-macacu' }) },
    { ...valid(), FIREBASE_CONFIG: '{invalid' },
  ]) assert.equal(stagingBackendAllowed({ env, adminProjectId: project }), false);
  assert.equal(stagingBackendAllowed({
    env: { ...valid(), GOOGLE_CLOUD_PROJECT: project,
      FIREBASE_CONFIG: JSON.stringify({ projectId: project }) },
    adminProjectId: project,
  }), true);
});

test('staging context is recognized even when its activation gate is invalid', () => {
  assert.equal(stagingProjectContext({ env: { GCLOUD_PROJECT: project } }), true);
  assert.equal(stagingProjectContext({ env: { GOOGLE_CLOUD_PROJECT: project } }), true);
  assert.equal(stagingProjectContext({ env: {
    FIREBASE_CONFIG: JSON.stringify({ projectId: project }),
  } }), true);
  assert.equal(stagingProjectContext({ env: {}, adminProjectId: project }), true);
  assert.equal(stagingProjectContext({ env: { GCLOUD_PROJECT: 'demo-universal-search' } }), false);
});

test('staging entrypoint registers only the staging public-content surface', () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const exported = {};
  const calls = [];
  const admin = { initializeApp() {}, app: () => ({ options: { projectId: project } }), firestore: () => ({}) };
  const env = valid();
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return admin;
    if (name === 'firebase-admin/firestore') return { FieldValue: { serverTimestamp() {} } };
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => handler, HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({ value: () => '' }) };
    if (name === './business_search') return { localOnly: () => false };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './secure_staging_environment') return { stagingProjectContext, stagingBackendAllowed: (args) => {
      calls.push(['gate', args.adminProjectId]); return stagingBackendAllowed({ ...args, env });
    } };
    if (name === './public_content') return {
      registerStagingPublicContent: () => {
        calls.push(['staging-register']);
        return { listPublicContent() {}, getPublicContentDetail() {}, getPublicJob() {} };
      },
      registerPublicContent: () => { calls.push(['normal-register']); return { listPublicContent() {}, getPublicContentDetail() {} }; },
    };
    if (name === './user_operations') return { registerUserOperations: () => { calls.push(['users-register']); return { submitUserOperation() {} }; } };
    if (name === './home_image_upload') return { uploadHomeImage: async () => {}, UploadError: Error };
    if (name === './notification_delivery') return { notificationTarget() {}, loadTargetDevices() {}, sendPushBatch() {} };
    if (name === './admin_authorization') return { authorizeCurrentAdmin() {} };
    throw new Error(`Unexpected import: ${name}`);
  };
  vm.runInNewContext(source, { require: fakeRequire, exports: exported, process: { env }, Buffer, URL, console });
  assert.deepEqual(Object.keys(exported).sort(), ['getPublicContentDetail', 'getPublicJob', 'listPublicContent']);
  assert.deepEqual(calls.filter(([kind]) => kind.endsWith('register')), [['staging-register']]);
});

test('invalid gate suppresses exports when only FIREBASE_CONFIG identifies staging', () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const exported = {};
  const admin = { initializeApp() {}, app: () => ({ options: { projectId: 'default-project' } }), firestore: () => ({}) };
  const env = { FIREBASE_CONFIG: JSON.stringify({ projectId: project }), STAGING_BACKEND_ENABLED: 'false' };
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return { onDocumentCreated: (_options, handler) => handler };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return admin;
    if (name === 'firebase-admin/firestore') return { FieldValue: { serverTimestamp() {} } };
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => handler, HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({ value: () => '' }) };
    if (name === './business_search') return { localOnly: () => false };
    if (name === './secure_staging_environment') return { stagingBackendAllowed, stagingProjectContext };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './home_image_upload') return { uploadHomeImage: async () => {}, UploadError: Error };
    if (name === './notification_delivery') return { notificationTarget() {}, loadTargetDevices() {}, sendPushBatch() {} };
    if (name === './admin_authorization') return { authorizeCurrentAdmin() {} };
    if (name === './public_content') return { registerPublicContent: () => ({ listPublicContent() {}, getPublicContentDetail() {} }),
      registerStagingPublicContent: () => ({ listPublicContent() {}, getPublicContentDetail() {}, getPublicJob() {} }) };
    if (name === './user_operations') return { registerUserOperations: () => ({ submitUserOperation() {} }) };
    throw new Error(`Unexpected import: ${name}`);
  };
  vm.runInNewContext(source, { require: fakeRequire, exports: exported, process: { env }, Buffer, URL, console });
  assert.deepEqual(Object.keys(exported), []);
});

test('demo entrypoint still registers local search and the pre-existing secure backend surface', () => {
  const source = fs.readFileSync(path.join(__dirname, '../index.js'), 'utf8');
  const exported = {};
  const admin = { initializeApp() {}, app: () => ({ options: { projectId: 'demo-universal-search' } }), firestore: () => ({}) };
  const fakeRequire = (name) => {
    if (name === 'firebase-functions/v2/firestore') return {
      onDocumentCreated: (_options, handler) => handler,
      onDocumentWritten: (_options, handler) => handler,
    };
    if (name === 'firebase-functions/logger') return {};
    if (name === 'firebase-admin') return admin;
    if (name === 'firebase-admin/firestore') return { FieldValue: { serverTimestamp() {} } };
    if (name === 'firebase-functions/v2/https') return { onCall: (_options, handler) => handler, HttpsError: Error };
    if (name === 'firebase-functions/params') return { defineSecret: () => ({}), defineString: () => ({ value: () => '' }) };
    if (name === './business_search') return { localOnly: () => true };
    if (name === './secure_staging_environment') return { stagingBackendAllowed: () => false, stagingProjectContext: () => false };
    if (name === './secure_backend_environment') return { secureBackendAllowed: () => true };
    if (name === './business_search_functions') return { registerLocalSearch: () => ({
      searchBusinesses() {}, getSearchJob() {}, getPublicJob() {}, syncJobsSearchIndex() {},
    }) };
    if (name === './public_content') return { registerPublicContent: () => ({ listPublicContent() {}, getPublicContentDetail() {} }) };
    if (name === './user_operations') return { registerUserOperations: () => ({ submitUserOperation() {} }) };
    if (name === './home_image_upload') return { uploadHomeImage: async () => {}, UploadError: Error };
    if (name === './notification_delivery') return { notificationTarget() {}, loadTargetDevices() {}, sendPushBatch() {} };
    if (name === './admin_authorization') return { authorizeCurrentAdmin() {} };
    throw new Error(`Unexpected import: ${name}`);
  };
  vm.runInNewContext(source, { require: fakeRequire, exports: exported, process: { env: {} }, Buffer, URL, console });
  for (const name of ['searchBusinesses', 'getSearchJob', 'getPublicJob', 'syncJobsSearchIndex',
    'listPublicContent', 'getPublicContentDetail', 'submitUserOperation', 'uploadHomeImage', 'deliverPushNotification']) {
    assert.equal(typeof exported[name], 'function', `${name} should retain its existing demo registration`);
  }
});
