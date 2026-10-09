'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { secureBackendAllowed } = require('../secure_backend_environment');
const { currentAdminState } = require('../admin_authorization');
const root = path.join(__dirname, '../..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8').replace(/\r\n/g, '\n');

test('one strict rules source is used by release configuration and emulator', () => {
  assert.equal(read('firestore.rules'), read('firestore.claims-local.rules'));
  assert.equal(JSON.parse(read('firebase.search-emulator.json')).firestore.rules, 'firestore.rules');
  assert.equal(JSON.parse(read('firebase.json')).firestore.rules, 'firestore.rules');
  assert.deepEqual(JSON.parse(read('firestore.indexes.json')), JSON.parse(read('firestore.search-local.indexes.json')));
  for (const config of ['firebase.json', 'firebase.search-emulator.json']) {
    assert.equal(JSON.parse(read(config)).firestore.indexes, 'firestore.indexes.json');
  }
  for (const file of ['firestore.rules', 'functions/admin_policy.js', 'functions/home_image_upload.js',
    'lib/core/auth/admin_authorization.dart', 'workers/image-upload/src/index.js']) {
    assert.doesNotMatch(read(file), /legacy-transition|isLegacyAdmin|legacyAdminEmail|bru\.mourris69@gmail\.com/);
  }
});
test('stale token and legacy identity never bypass current versioned authorization', () => {
  const state = { enabled: true, pending: false, version: 'v2' };
  for (const token of [{ email: 'legacy-admin@example.com', email_verified: true },
    { role: 'admin' }, { admin: true, adminVersion: 'v1' }]) {
    assert.equal(currentAdminState(token, state), false);
  }
  assert.equal(currentAdminState({ admin: true, adminVersion: 'v2' }, state), true);
});
test('backend preparation has no implicit production activation or mixed emulator project', () => {
  assert.equal(secureBackendAllowed({}), false);
  assert.equal(secureBackendAllowed({ GCLOUD_PROJECT: 'tudo-aqui-macacu' }), false);
  assert.equal(secureBackendAllowed({ GCLOUD_PROJECT: 'tudo-aqui-macacu', SECURE_BACKEND_ENABLED: 'true' }), true);
  assert.equal(secureBackendAllowed({ GCLOUD_PROJECT: 'tudo-aqui-macacu', SECURE_BACKEND_ENABLED: 'true', FUNCTIONS_EMULATOR: 'true' }), false);
  assert.equal(secureBackendAllowed({ GCLOUD_PROJECT: 'demo-universal-search', FUNCTIONS_EMULATOR: 'true', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' }), true);
});
