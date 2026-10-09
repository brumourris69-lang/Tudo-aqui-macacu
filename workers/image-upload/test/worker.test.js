import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT, createLocalJWKSet, exportJWK } from 'jose';
import { createHandler, verifyFirebaseToken } from '../src/index.js';
import upload from '../../../functions/home_image_upload.js';

const pair = await generateKeyPair('RS256');
const jwk = await exportJWK(pair.publicKey);
jwk.kid = 'test-key';
const keySet = createLocalJWKSet({ keys: [jwk] });
const project = 'tudo-aqui-macacu';
const now = Math.floor(Date.now() / 1000);
const env = {
  FIREBASE_PROJECT_ID: project,
  UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) },
};
const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function token(claims = {}) {
  return new SignJWT({ auth_time: now - 10, admin: true, ...claims })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setIssuer(`https://securetoken.google.com/${project}`)
    .setAudience(project).setSubject('admin-uid').setIssuedAt(now - 1)
    .setExpirationTime(now + 3600).sign(pair.privateKey);
}
const verify = (value, id) => verifyFirebaseToken(value, id, keySet);
function request(value, body = image, headers = {}) {
  return new Request('https://test.workers.dev/v1/home-logo', {
    method: 'POST', headers: { authorization: `Bearer ${value}`,
      'content-type': 'application/octet-stream', ...headers }, body,
  });
}

test('valid signed admin receives only safe upload metadata', async () => {
  let calls = 0;
  const handler = createHandler({ verify, authorize: async () => true, send: async (bytes) => {
    assert.deepEqual(bytes, image);
    calls++;
    return { secureUrl: 'https://res.cloudinary.com/example/image/upload/v1/photo.png' };
  } });
  const result = await handler(request(await token()), env);
  assert.equal(result.status, 200);
  assert.equal(calls, 1);
  assert.equal(result.headers.get('cache-control'), 'no-store');
});

test('regular user cannot upload even when requesting it', async () => {
  const handler = createHandler({ verify, authorize: async () => true, send: () => assert.fail('provider reached') });
  assert.equal((await handler(request(await token({ admin: false })), env)).status, 403);
});

test('unified Worker denies verified legacy email/role and anonymous, allows boolean claim', async () => {
  const strict = { ...env };
  const handler = createHandler({ verify, authorize: async () => true, send: async () => ({ secureUrl: 'https://res.cloudinary.com/example/image/upload/test.png' }) });
  for (const claims of [
    { admin: false, email: 'legacy-admin@example.com', email_verified: true },
    { admin: false, role: 'admin' }, { admin: 'true' },
    { admin: true, firebase: { sign_in_provider: 'anonymous' } },
  ]) assert.equal((await handler(request(await token(claims)), strict)).status, 403);
  assert.equal((await handler(request(await token({ admin: true })), strict)).status, 200);
});

test('legacy email and role never authorize without a boolean Admin claim', () => {
  for (const token of [{ role: 'admin' }, { email: 'legacy-admin@example.com', email_verified: true }]) {
    assert.throws(() => upload.requireAdmin({ uid: 'u', token }), /administradores/);
  }
});

test('forged, expired, wrong audience and wrong issuer tokens are rejected', async () => {
  const forged = (await token()).split('.');
  forged[1] = Buffer.from(JSON.stringify({ admin: true })).toString('base64url');
  const make = (audience, issuer, expiration) => new SignJWT({ auth_time: now - 10, admin: true })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('u').setIssuedAt(now - 100)
    .setAudience(audience).setIssuer(issuer).setExpirationTime(expiration).sign(pair.privateKey);
  const issuer = `https://securetoken.google.com/${project}`;
  for (const value of [forged.join('.'), await make(project, issuer, now - 1),
    await make('other-project', issuer, now + 100), await make(project, 'https://evil.test', now + 100)]) {
    await assert.rejects(verify(value, project), (error) => error.code === 'unauthenticated');
  }
});

test('missing/future auth_time and untrusted signing key are rejected', async () => {
  for (const value of [null, now + 100]) {
    await assert.rejects(verify(await token({ auth_time: value }), project));
  }
  const other = await generateKeyPair('RS256');
  const value = await new SignJWT({ admin: true, auth_time: now - 10 })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setSubject('u')
    .setIssuedAt(now - 1).setExpirationTime(now + 100).setAudience(project)
    .setIssuer(`https://securetoken.google.com/${project}`).sign(other.privateKey);
  await assert.rejects(verify(value, project));
});

test('missing token, wrong method, path and browser origin never reach provider', async () => {
  const handler = createHandler({ verify, authorize: async () => true, send: () => assert.fail('provider reached') });
  assert.equal((await handler(new Request('https://test.workers.dev/v1/home-logo'), env)).status, 405);
  assert.equal((await handler(new Request('https://test.workers.dev/other'), env)).status, 404);
  assert.equal((await handler(request('', image), env)).status, 401);
  assert.equal((await handler(request(await token(), image, { origin: 'https://evil.test' }), env)).status, 403);
});

test('rate limit and absent binding fail closed before reading/uploading', async () => {
  const handler = createHandler({ verify, authorize: async () => true, send: () => assert.fail('provider reached') });
  const req = () => request('test');
  const auth = { uid: 'u', token: { admin: true } };
  const local = createHandler({ verify: async () => auth, send: () => assert.fail('provider reached') });
  assert.equal((await local(req(), { ...env, UPLOAD_RATE_LIMITER: undefined })).status, 503);
  assert.equal((await local(req(), { ...env,
    UPLOAD_RATE_LIMITER: { limit: async () => ({ success: false }) } })).status, 429);
  assert.equal((await handler(req(), env)).status, 401);
});

test('oversized streaming body, forged MIME and malformed image fail safely', async () => {
  const handler = createHandler({ verify, authorize: async () => true, send: (bytes) => upload.uploadImageBytes(bytes, {
    getConfig: () => { throw new Error('must not reach config'); },
  }) });
  const jwt = await token();
  assert.equal((await handler(request(jwt, image, { 'content-type': 'image/png' }), env)).status, 400);
  assert.equal((await handler(request(jwt, Buffer.alloc(5 * 1024 * 1024 + 1)), env)).status, 400);
  assert.equal((await handler(request(jwt, Buffer.from('<script>bad</script>')), env)).status, 400);
  assert.equal((await handler(request(jwt, Buffer.alloc(0)), env)).status, 400);
});

test('unknown errors never disclose internal secrets or provider request', async () => {
  const handler = createHandler({ verify, authorize: async () => true, send: () => { throw new Error('SECRET-DO-NOT-RETURN'); } });
  const result = await handler(request(await token()), env);
  assert.equal(result.status, 502);
  assert.equal(await result.text(), '{"error":"unavailable"}');
});
