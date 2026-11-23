'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { validateEnvironment, suites } = require('../security_emulator_tests.cjs');
const root = path.resolve(__dirname, '../..');
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
    'admin_claims_emulator.js', 'job_private_emulator.js', 'notifications_emulator.js', 'content_visibility_emulator.js',
    'user_operations_emulator.js', 'auth_emulator.js', 'security_audit_auth_emulator.js',
    'distribution_public_projection_emulator.js',
  ]);
  assert.ok(!suites.includes('search_emulator.js'));
});

test('normal and local Rules expose only catalog projections and bind Admin writes to canonical changes', () => {
  const rules = ['firestore.rules', 'firestore.claims-local.rules'].map(file =>
    fs.readFileSync(path.join(root, file), 'utf8'));
  assert.equal(rules[0], rules[1]);
  for (const source of rules) {
    const generic = source.match(/match \/\{collection\}\/\{document\} \{([\s\S]*?)\n    \}/)?.[1];
    assert.ok(generic, 'generic top-level collection rule must exist');
    assert.match(generic, /allow get: if publicCollection\(collection\) &&\s*\(admin\(\) \|\| \(collection != 'jobs' && collection != 'establishments' && visibleDocument\(collection\)\)\);/);
    assert.match(generic, /allow list: if publicCollection\(collection\) && admin\(\);/);
    assert.match(source, /match \/beta_public_catalog\/\{collectionId\}\/items\/\{itemId\}/);
    assert.match(source, /function visibleCanonicalAfter\(collection, itemId\)/);
    assert.match(source, /function projectionIsSynchronized\(collection, itemId\)/);
    assert.match(generic, /projectionIsSynchronized\(collection, document\)/);
    assert.match(source, /function projectionsAreRemovedAfter\(collection, itemId\)/);
    assert.match(generic, /projectionsAreRemovedAfter\(collection, document\)/);
    assert.match(source, /source\.get\('updatedAt', null\) == request\.time/);
    assert.match(source, /allow create, update: if admin\(\) &&[\s\S]*?visibleCanonicalAfter\('establishments', itemId\)/);
    assert.match(source, /allow delete: if admin\(\) && collectionId == 'establishments_basic' &&\s*canonicalAfterIsUnavailable\('establishments', itemId\)/);
    assert.match(source, /function validProjectedAdTargetAfter\(data\)/);
  }
});

test('distribution projection Emulator harness can use disposable loopback ports only', () => {
  const harness = fs.readFileSync(path.join(root, 'functions/integration/distribution_public_projection_emulator.js'), 'utf8');
  assert.match(harness, /DISTRIBUTION_TEST_FIRESTORE_HOST \|\| '127\.0\.0\.1:8087'/);
  assert.match(harness, /DISTRIBUTION_TEST_AUTH_HOST \|\| '127\.0\.0\.1:9097'/);
  assert.match(harness, /assert\.equal\(parsed\.hostname, '127\.0\.0\.1'\)/);
  assert.match(harness, /transaction\.set\(adminProjectionRef/);
  assert.match(harness, /Projeção fora da transação canônica/);
  assert.match(harness, /Admin cannot unpublish canonical content while leaving public projections/);
  assert.match(harness, /Admin cannot delete canonical content while leaving public projections/);
  assert.match(harness, /DISTRIBUTION_TEST_EMAIL_ADMIN === 'true'/);
  assert.match(harness, /DISTRIBUTION_TEST_ADMIN_EMAIL/);
  assert.doesNotMatch(harness, /firebase\.google\.com|firebaseapp\.com\/o|\.run\.app/);
});
