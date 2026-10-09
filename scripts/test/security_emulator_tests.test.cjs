'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validateEnvironment, suites } = require('../security_emulator_tests.cjs');
const demo = {
  GCLOUD_PROJECT: 'demo-universal-search', FUNCTIONS_EMULATOR: 'true',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097',
  LOCAL_SEARCH_REQUIRE_APP_CHECK: 'true',
};
test('security runner accepts only the configured demo environment', () => {
  assert.doesNotThrow(() => validateEnvironment(demo));
  for (const change of [
    { GCLOUD_PROJECT: 'production-project' }, { GCLOUD_PROJECT: 'demo-other' },
    { FUNCTIONS_EMULATOR: 'false' }, { FIRESTORE_EMULATOR_HOST: 'firestore.googleapis.com:443' },
    { FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099' }, { LOCAL_SEARCH_REQUIRE_APP_CHECK: 'false' },
    { GOOGLE_APPLICATION_CREDENTIALS: 'service-account.json' },
  ]) assert.throws(() => validateEnvironment({ ...demo, ...change }));
  assert.throws(() => validateEnvironment({}));
});
test('all security modules including historical Auth and revocation audit remain mandatory', () => {
  assert.deepEqual([...suites], [
    'admin_claims_emulator.js', 'notifications_emulator.js', 'content_visibility_emulator.js',
    'user_operations_emulator.js', 'auth_emulator.js', 'security_audit_auth_emulator.js',
  ]);
  assert.ok(!suites.includes('search_emulator.js'));
});
