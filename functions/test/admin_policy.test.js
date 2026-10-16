'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { isAdminClaim } = require('../admin_policy');
const { requireAdmin } = require('../home_image_upload');
const { changeAdminClaim } = require('../admin_claim_management');

test('strict policy accepts only boolean admin claim on non-anonymous accounts', () => {
  for (const token of [{}, { admin: 'true' }, { role: 'admin' },
    { email: 'legacy-admin@example.com', email_verified: true },
    { admin: true, firebase: { sign_in_provider: 'anonymous' } }]) {
    assert.equal(isAdminClaim(token), false);
    assert.throws(() => requireAdmin({ uid: 'u', token }));
  }
  for (const email_verified of [undefined, false, true]) {
    requireAdmin({ uid: 'u', token: { admin: true, email_verified } });
  }
  assert.throws(() => requireAdmin(null));

});
test('grant/revoke procedure refuses real environments before touching Auth', async () => {
  await assert.rejects(changeAdminClaim({ env: {}, auth: { getUser: () => assert.fail('Auth access') } }));
});
test('local Admin claim helper accepts alternate loopback emulator ports and rejects remote Auth', async () => {
  const env = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:18087', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:19097' };
  const auth = { getUser: async () => ({ providerData: [{}], customClaims: {} }) };
  const result = await changeAdminClaim({ env, auth, uid: 'fixture-user', action: 'grant',
    operator: 'local-test', reason: 'demo fixture' });
  assert.equal(result.dryRun, true);
  await assert.rejects(changeAdminClaim({ env: { ...env,
    FIREBASE_AUTH_EMULATOR_HOST: 'auth.example.invalid:19097' }, auth: {
    getUser: () => assert.fail('Remote Auth access'),
  } }));
});
test('claim mutation is dry-run by default and preserves unrelated claims with audit', async () => {
  const env = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search', FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097' };
  const writes = [], audits = [];
  const user = { customClaims: { subscriber: true }, providerData: [{ providerId: 'password' }] };
  const auth = { getUser: async () => user, setCustomUserClaims: async (_uid, claims) => { writes.push(claims); user.customClaims = claims; }, revokeRefreshTokens: async () => writes.push('revoked') };
  const audit = { id: 'audit', set: async data => audits.push(data), update: async data => audits.push(data) };
  let state;
  const stateRef = {};
  const db = { collection: name => ({ doc: () => name === 'admin_authorizations' ? stateRef : audit }),
    runTransaction: async fn => fn({ get: async () => ({ data: () => state }), set: (_ref, data) => { state = data; } }) };
  const options = { env, auth, db, uid: 'test-user', action: 'grant', operator: 'local-operator', reason: 'test' };
  assert.equal((await changeAdminClaim(options)).dryRun, true); assert.equal(writes.length, 0);
  await assert.rejects(changeAdminClaim({ ...options, apply: true })); assert.equal(writes.length, 0);
  await changeAdminClaim({ ...options, apply: true, confirmation: 'demo-universal-search:test-user:grant' });
  assert.equal(writes[0].subscriber, true); assert.equal(writes[0].admin, true);
  assert.equal(typeof writes[0].adminVersion, 'string'); assert.equal(state.enabled, true); assert.equal(state.pending, false);
  await changeAdminClaim({ ...options, action: 'revoke', apply: true, confirmation: 'demo-universal-search:test-user:revoke' });
  assert.deepEqual(writes[1], { subscriber: true }); assert.equal(state.enabled, false); assert.equal(writes[2], 'revoked');
  assert.equal(audits.filter(v => v.status === 'applied').length, 2);
});
