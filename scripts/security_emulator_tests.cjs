'use strict';
// Explicit allowlist: never run search_emulator.js, which clears the demo DB.
// Run inside firebase emulators:exec, or against the existing local demo suite.
const assert = require('node:assert/strict');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const suites = Object.freeze([
  'admin_claims_emulator.js',
  'notifications_emulator.js',
  'content_visibility_emulator.js',
  'user_operations_emulator.js',
  'auth_emulator.js',
  'security_audit_auth_emulator.js',
]);

function validateEnvironment(env) {
  assert.equal(env.GCLOUD_PROJECT, 'demo-universal-search', 'Security tests require the exact demo project');
  assert.equal(env.FUNCTIONS_EMULATOR, 'true');
  assert.equal(env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8087');
  assert.equal(env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9097');
  assert.equal(env.LOCAL_SEARCH_REQUIRE_APP_CHECK, 'true', 'App Check policy cannot be disabled in CI');
  assert.ok(!env.GOOGLE_APPLICATION_CREDENTIALS, 'Do not supply real service credentials to emulator tests');
}

function run(env = process.env) {
  validateEnvironment(env); // Fail before loading Firebase SDKs or launching tests.
  const root = path.resolve(__dirname, '..');
  for (const suite of suites) {
    console.log(`\nSecurity Emulator suite: ${suite}`);
    const result = spawnSync(process.execPath, [path.join(root, 'functions', 'integration', suite)], {
      cwd: root, env, stdio: 'inherit', timeout: 180000,
    });
    if (result.error) throw result.error;
    assert.equal(result.status, 0, `Security suite failed: ${suite}`);
  }
  console.log(`\nAll ${suites.length} mandatory security emulator suites passed (demo only).`);
}

module.exports = { validateEnvironment, suites, run };
if (require.main === module) {
  try { run(); } catch (error) { console.error(error.message); process.exitCode = 1; }
}
