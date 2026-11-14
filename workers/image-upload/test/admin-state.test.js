import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyAdminState } from '../src/admin-state.js';
import { createHandler } from '../src/index.js';
const auth = { uid: 'fixture', token: { admin: true, adminVersion: 'v1' } };
const fields = { enabled: { booleanValue: true }, pending: { booleanValue: false }, version: { stringValue: 'v1' } };
test('Worker reads only fixed caller state with caller token; rechecks every request', async () => {
  let calls = 0;
  const fetchImpl = async (url, options) => {
    assert.equal(url, 'https://firestore.googleapis.com/v1/projects/tudo-aqui-macacu/databases/(default)/documents/admin_authorizations/fixture');
    assert.equal(options.headers.authorization, 'Bearer local-test-token');
    assert.equal(options.cache, 'no-store');
    return Response.json({ fields: { ...fields, enabled: { booleanValue: ++calls === 1 } } });
  };
  assert.equal(await verifyAdminState(auth, 'local-test-token', 'tudo-aqui-macacu', fetchImpl), true);
  assert.equal(await verifyAdminState(auth, 'local-test-token', 'tudo-aqui-macacu', fetchImpl), false);
});
test('Beta authorization is read only from the Beta project and versioned state', async () => {
  const betaProject = 'macacu-beta-261030-cf4a81';
  let requestedUrl;
  const fetchImpl = async (url, options) => {
    requestedUrl = url;
    assert.equal(options.headers.authorization, 'Bearer beta-caller-token');
    return Response.json({ fields });
  };
  assert.equal(await verifyAdminState(auth, 'beta-caller-token', betaProject, fetchImpl), true);
  assert.equal(requestedUrl, `https://firestore.googleapis.com/v1/projects/${betaProject}/databases/(default)/documents/admin_authorizations/fixture`);
  await assert.rejects(verifyAdminState(auth, 'token', 'demo-universal-search', async () => {
    throw new Error('unsupported project must not be queried');
  }), { code: 'failed-precondition' });
  assert.equal(await verifyAdminState(auth, 'beta-caller-token', betaProject, async () =>
    Response.json({ fields: { ...fields, enabled: { booleanValue: false } } })), false);
});
test('Worker rejects stale version, malformed state, forbidden/missing and unavailable authorization', async () => {
  for (const response of [Response.json({}), Response.json({ fields: { ...fields, version: { stringValue: 'v2' } } }),
    new Response('', { status: 403 }), new Response('', { status: 404 })]) {
    assert.equal(await verifyAdminState(auth, 'local', 'tudo-aqui-macacu', async () => response), false);
  }
  for (const fetchImpl of [async () => { throw Error('offline'); }, async () => new Response('', { status: 500 }),
    async () => new Response('invalid-json')]) {
    await assert.rejects(verifyAdminState(auth, 'local', 'tudo-aqui-macacu', fetchImpl));
  }
});
test('Worker never reaches upload transport on revoked state or service outage', async () => {
  const request = () => new Request('https://local.test/v1/home-logo', { method: 'POST',
    headers: { authorization: 'Bearer test-token', 'content-type': 'application/octet-stream' }, body: new Uint8Array([1]) });
  const env = { FIREBASE_PROJECT_ID: 'tudo-aqui-macacu',
    UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) } };
  for (const [authorize, expected] of [[async () => false, 403], [async () => { throw Error('offline'); }, 502]]) {
    const handler = createHandler({ verify: async () => auth, authorize, send: () => assert.fail('upload reached') });
    assert.equal((await handler(request(), env)).status, expected);
  }
});
test('revocation during body reception blocks the external side effect', async () => {
  let checks = 0;
  const handler = createHandler({ verify: async () => auth,
    authorize: async () => ++checks === 1, send: () => assert.fail('upload reached') });
  const request = new Request('https://local.test/v1/home-logo', { method: 'POST',
    headers: { authorization: 'Bearer test-token', 'content-type': 'application/octet-stream' }, body: new Uint8Array([1]) });
  const env = { FIREBASE_PROJECT_ID: 'tudo-aqui-macacu',
    UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) } };
  assert.equal((await handler(request, env)).status, 403);
  assert.equal(checks, 2);
});
