'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { currentAdminState, authorizeCurrentAdmin } = require('../admin_authorization');
const { uploadHomeImage } = require('../home_image_upload');
const { changeAdminClaim } = require('../admin_claim_management');
const auth = { uid: 'fixture', token: { admin: true, adminVersion: 'v1' } };
const state = { enabled: true, pending: false, version: 'v1' };

test('versioned current state rejects old, absent, disabled, malformed and pending permissions', () => {
  assert.equal(currentAdminState(auth.token, state), true);
  for (const value of [null, {}, { ...state, enabled: false }, { ...state, version: 'v2' },
    { ...state, pending: true }, { enabled: true, version: 'v1' }]) {
    assert.equal(currentAdminState(auth.token, value), false);
  }
  for (const token of [{}, { admin: true }, { admin: true, adminVersion: '' },
    { ...auth.token, firebase: { sign_in_provider: 'anonymous' } }]) {
    assert.equal(currentAdminState(token, state), false);
  }
});
test('backend reads state freshly and never grants on database/verification failure', async () => {
  let current = state, reads = 0;
  const db = { collection: () => ({ doc: uid => {
    assert.equal(uid, auth.uid);
    return { get: async () => { reads++; return { exists: true, data: () => current }; } };
  } }) };
  assert.equal(await authorizeCurrentAdmin(auth, { db }), true);
  current = { ...state, enabled: false };
  assert.equal(await authorizeCurrentAdmin(auth, { db }), false);
  assert.equal(reads, 2);
  await assert.rejects(authorizeCurrentAdmin(auth));
  await assert.rejects(authorizeCurrentAdmin(auth, { db: { collection: () => { throw Error('offline'); } } }));
  await assert.rejects(authorizeCurrentAdmin(auth, { db, rawToken: 'test-only',
    firebaseAuth: { verifyIdToken: async (_token, checkRevoked) => { assert.equal(checkRevoked, true); throw Error('revoked'); } } }));
});
test('strict upload blocks before payload/config/provider on missing or failing authorization', async () => {
  for (const authorize of [undefined, async () => false, async () => { throw Error('offline'); }]) {
    await assert.rejects(uploadHomeImage({ auth }, { authorize,
      getConfig: () => assert.fail('provider/config reached') }));
  }
});
test('revocation disables state before Auth and partial Auth failure keeps it disabled', async () => {
  const env = { FUNCTIONS_EMULATOR: 'true', GCLOUD_PROJECT: 'demo-universal-search',
    FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087', FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9097' };
  let current = state;
  const audit = { id: 'audit', set: async () => {}, update: async () => {} };
  const ref = {};
  const db = { collection: name => ({ doc: () => name === 'admin_authorizations' ? ref : audit }),
    runTransaction: async fn => fn({ get: async () => ({ data: () => current }), set: (_ref, data) => { current = data; } }) };
  const firebaseAuth = { getUser: async () => ({ customClaims: auth.token }),
    setCustomUserClaims: async () => {
      assert.equal(current.enabled, false); assert.equal(current.pending, true);
      assert.equal(currentAdminState(auth.token, current), false);
      throw Error('Auth unavailable');
    } };
  await assert.rejects(changeAdminClaim({ env, auth: firebaseAuth, db, uid: auth.uid,
    action: 'revoke', operator: 'test', reason: 'test', apply: true,
    confirmation: `demo-universal-search:${auth.uid}:revoke` }));
  assert.equal(currentAdminState(auth.token, current), false);
  // A pending operation cannot be silently replaced by another grant.
  firebaseAuth.getUser = async () => ({ customClaims: {}, providerData: [{}] });
  firebaseAuth.setCustomUserClaims = () => assert.fail('overlapping mutation');
  await assert.rejects(changeAdminClaim({ env, auth: firebaseAuth, db, uid: auth.uid,
    action: 'grant', operator: 'test', reason: 'test', apply: true,
    confirmation: `demo-universal-search:${auth.uid}:grant` }));
});
