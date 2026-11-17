import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, SignJWT, createLocalJWKSet, exportJWK } from 'jose';
import { createHandler, verifyFirebaseToken } from '../src/index.js';
import { createMunicipalNewsHandler, parseFeed } from '../src/municipal-news-feed.js';
import { verifyAdminState } from '../src/admin-state.js';
import upload from '../../../functions/home_image_upload.js';

const pair = await generateKeyPair('RS256');
const jwk = await exportJWK(pair.publicKey);
jwk.kid = 'test-key';
const keySet = createLocalJWKSet({ keys: [jwk] });
const project = 'tudo-aqui-macacu';
const betaProject = 'macacu-beta-261030-cf4a81';
const now = Math.floor(Date.now() / 1000);
const env = {
  FIREBASE_PROJECT_ID: project,
  UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) },
};
const image = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function token(claims = {}, targetProject = project) {
  return new SignJWT({ auth_time: now - 10, admin: true, ...claims })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setIssuer(`https://securetoken.google.com/${targetProject}`)
    .setAudience(targetProject).setSubject('admin-uid').setIssuedAt(now - 1)
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

test('authorized Beta identity is isolated to its project and Cloudinary folder', async () => {
  let providerConfig;
  let authorizationReads = 0;
  const betaEnv = { ...env, FIREBASE_PROJECT_ID: betaProject,
    CLOUDINARY_FOLDER: 'tudo-aqui-macacu-beta/home' };
  const betaToken = await token({ adminVersion: 'beta-v3' }, betaProject);
  const handler = createHandler({
    verify: (value, id) => verifyFirebaseToken(value, id, keySet),
    authorize: async (auth, value, id) => verifyAdminState(auth, value, id, async (url, options) => {
      assert.equal(id, betaProject);
      assert.equal(url, `https://firestore.googleapis.com/v1/projects/${betaProject}/databases/(default)/documents/admin_authorizations/admin-uid`);
      assert.equal(options.headers.authorization, `Bearer ${betaToken}`);
      assert.equal(auth.token.adminVersion, 'beta-v3');
      authorizationReads++;
      return Response.json({ fields: { enabled: { booleanValue: true },
        pending: { booleanValue: false }, version: { stringValue: 'beta-v3' } } });
    }),
    send: async (bytes, options) => {
      assert.deepEqual(bytes, image);
      providerConfig = options;
      return { secureUrl: 'https://res.cloudinary.com/example/image/upload/v1/photo.png' };
    },
  });
  assert.equal((await handler(request(betaToken), betaEnv)).status, 200);
  assert.equal(providerConfig.firebaseProjectId, betaProject);
  assert.equal(providerConfig.folder, 'tudo-aqui-macacu-beta/home');
  assert.equal(authorizationReads, 2);
  const revokedHandler = createHandler({
    verify: (value, id) => verifyFirebaseToken(value, id, keySet),
    authorize: (auth, value, id) => verifyAdminState(auth, value, id, async () =>
      Response.json({ fields: { enabled: { booleanValue: false },
        pending: { booleanValue: false }, version: { stringValue: 'beta-v3' } } })),
    send: async () => assert.fail('revoked Beta admin must not reach Cloudinary'),
  });
  assert.equal((await revokedHandler(request(betaToken), betaEnv)).status, 403);
  assert.equal((await handler(request(await token({ admin: false }, betaProject)), betaEnv)).status, 403);
});

test('Beta and production Firebase tokens cannot cross Worker project identities', async () => {
  const handler = createHandler({
    verify: (value, id) => verifyFirebaseToken(value, id, keySet),
    authorize: async () => assert.fail('authorization must not run'),
    send: async () => assert.fail('Cloudinary must not run'),
  });
  const betaToken = await token({ adminVersion: 'beta-v3' }, betaProject);
  const productionToken = await token({}, project);
  assert.equal((await handler(request(productionToken), { ...env, FIREBASE_PROJECT_ID: betaProject })).status, 401);
  assert.equal((await handler(request(betaToken), env)).status, 401);
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

test('municipal RSS parser extracts only safe official articles', () => {
  const xml = '<?xml version="1.0"?><rss version="2.0"><channel><item>' +
    '<title><![CDATA[Notícia &amp; serviço]]></title>' +
    '<description><![CDATA[Resumo da Prefeitura.]]></description>' +
    '<link>https://www.prefeituracachoeiras.com/post/aviso</link>' +
    '<guid>news-1</guid><pubDate>Sun, 15 Nov 2026 10:00:00 GMT</pubDate>' +
    '<enclosure url="https://static.wixstatic.com/media/notice.jpg" type="image/jpeg"/>' +
    '</item><item><title>Malicioso</title><link>https://attacker.invalid/</link>' +
    '<guid>bad</guid></item></channel></rss>';
  const feed = parseFeed(xml);
  assert.equal(feed.source, 'Prefeitura de Cachoeiras de Macacu');
  assert.equal(feed.posts.length, 1);
  assert.equal(feed.posts[0].title, 'Notícia & serviço');
  assert.equal(feed.posts[0].imageUrl, 'https://static.wixstatic.com/media/notice.jpg');
  assert.throws(() => parseFeed('<!DOCTYPE rss [<!ENTITY x SYSTEM "file:///etc/passwd">]><rss/>'));
});

test('city news Worker fetches the fixed public RSS and caches the normalized result', async () => {
  let fetchCalls = 0;
  let rateCalls = 0;
  const handler = createMunicipalNewsHandler({ fetchFeed: async (url, options) => {
    fetchCalls++;
    assert.equal(url, 'https://www.prefeituracachoeiras.com/blog-feed.xml');
    assert.equal(options.redirect, 'error');
    return new Response('<rss><channel><item><title>Alerta</title><description>Resumo</description>' +
      '<link>https://www.prefeituracachoeiras.com/post/alerta</link><guid>n2</guid>' +
      '<pubDate>Sun, 15 Nov 2026 10:00:00 GMT</pubDate>' +
      '<enclosure url="https://static.wixstatic.com/media/alerta.jpg"/></item></channel></rss>');
  } });
  const request = () => new Request('https://test.workers.dev/v1/city-news', {
    headers: { 'cf-connecting-ip': '192.0.2.4' },
  });
  const env = { UPLOAD_RATE_LIMITER: { limit: async ({ key }) => {
    rateCalls++;
    assert.equal(key, 'city-news:192.0.2.4');
    return { success: true };
  } } };
  const result = await handler(request(), env);
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('cache-control'), 'public, max-age=300');
  const payload = await result.json();
  assert.equal(payload.posts[0].title, 'Alerta');
  const cached = await handler(request(), env);
  assert.equal(cached.status, 200);
  assert.equal(fetchCalls, 1);
  assert.equal(rateCalls, 1);
});

test('city news Worker is read-only, rate limited, and returns safe errors', async () => {
  let fetchCalls = 0;
  const handler = createMunicipalNewsHandler({ fetchFeed: async () => {
    fetchCalls++;
    return new Response('internal source detail', { status: 500 });
  } });
  const env = { UPLOAD_RATE_LIMITER: { limit: async () => ({ success: false }) } };
  const get = () => new Request('https://test.workers.dev/v1/city-news', {
    headers: { 'cf-connecting-ip': '192.0.2.4' },
  });
  assert.equal((await handler(new Request('https://test.workers.dev/v1/city-news', { method: 'POST' }), env)).status, 405);
  assert.equal((await handler(new Request('https://test.workers.dev/v1/city-news?source=other'), env)).status, 404);
  assert.equal((await handler(new Request('https://test.workers.dev/v1/city-news', {
    headers: { origin: 'https://web.example', 'cf-connecting-ip': '192.0.2.4' },
  }), env)).status, 403);
  assert.equal((await handler(get(), env)).status, 429);
  assert.equal(fetchCalls, 0);
  const noLimiter = await handler(get(), {});
  assert.equal(noLimiter.status, 503);
  const failing = createMunicipalNewsHandler({ fetchFeed: async () => new Response('private detail', { status: 500 }) });
  const result = await failing(get(), { UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) } });
  assert.equal(result.status, 502);
  assert.equal(await result.text(), '{"error":"feed-unavailable"}');
});

test('city news Worker rejects an oversized feed before parsing it', async () => {
  const handler = createMunicipalNewsHandler({ fetchFeed: async () =>
    new Response(Buffer.alloc(2_000_001), { headers: { 'content-type': 'application/xml' } })
  });
  const request = new Request('https://test.workers.dev/v1/city-news', {
    headers: { 'cf-connecting-ip': '192.0.2.5' },
  });
  const result = await handler(request, {
    UPLOAD_RATE_LIMITER: { limit: async () => ({ success: true }) },
  });
  assert.equal(result.status, 502);
  assert.equal(await result.text(), '{"error":"feed-unavailable"}');
});
