import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  createFirebaseSigningKeyResolver,
  createGoogleAccessToken,
} from './firebase_signing_keys.mjs';

async function publicJwk(kid = 'firebase-key-1') {
  const pair = await crypto.subtle.generateKey({
    name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256',
  }, true, ['sign', 'verify']);
  return { ...(await crypto.subtle.exportKey('jwk', pair.publicKey)), kid, alg: 'RS256', use: 'sig' };
}

function response(body, headers = {}) {
  return new Response(JSON.stringify(body), { status: 200, headers });
}

test('loads Google Secure Token JWKs from a fixed endpoint and caches imported keys', async () => {
  const jwk = await publicJwk();
  const requests = [];
  const resolve = createFirebaseSigningKeyResolver({
    now: () => 1_000,
    fetchImpl: async (url, options) => {
      requests.push({ url, options });
      return response({ keys: [jwk] }, { 'cache-control': 'public, max-age=300' });
    },
  });
  const first = await resolve('firebase-key-1');
  const second = await resolve('firebase-key-1');
  assert.ok(first);
  assert.equal(first, second);
  assert.equal(requests.length, 1);
  assert.equal(requests[0].url, 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com');
  assert.equal(await resolve('unknown-key'), null);
  assert.equal(requests.length, 2, 'an unknown kid triggers one rate-limited key refresh');
  assert.equal(await resolve('another-unknown-key'), null);
  assert.equal(requests.length, 2, 'unknown kids cannot trigger repeated key downloads');
});

test('fails closed on malformed or unavailable JWK responses without exposing response text', async () => {
  const secret = 'private-response-sentinel';
  const malformed = createFirebaseSigningKeyResolver({ fetchImpl: async () => new Response(secret, { status: 200 }) });
  await assert.rejects(malformed('key'), (error) => {
    assert.equal(error.code, 'signing-key-unavailable');
    assert.equal(error.message.includes(secret), false);
    return true;
  });
  const unavailable = createFirebaseSigningKeyResolver({ fetchImpl: async () => new Response(secret, { status: 503 }) });
  await assert.rejects(unavailable('key'), { code: 'signing-key-unavailable' });
});

test('signs a fixed datastore OAuth assertion without returning credential material', async () => {
  const pair = await crypto.subtle.generateKey({
    name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256',
  }, true, ['sign', 'verify']);
  const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
  let binary = '';
  for (const byte of der) binary += String.fromCharCode(byte);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).match(/.{1,64}/gu).join('\n')}\n-----END PRIVATE KEY-----`;
  const serviceAccountJson = JSON.stringify({
    type: 'service_account', project_id: 'tudo-aqui-macacu',
    client_email: 'local-test@tudo-aqui-macacu.iam.gserviceaccount.com', private_key: pem,
  });
  let outbound;
  const token = await createGoogleAccessToken({
    serviceAccountJson,
    projectId: 'tudo-aqui-macacu',
    now: () => 1_797_000_000_000,
    fetchImpl: async (url, init) => {
      outbound = { url, init };
      return response({ access_token: 'mock-service-access-token-value', token_type: 'Bearer', expires_in: 3600 });
    },
  });
  assert.equal(token.accessToken, 'mock-service-access-token-value');
  assert.equal(outbound.url, 'https://oauth2.googleapis.com/token');
  const params = new URLSearchParams(outbound.init.body);
  const [, claim] = params.get('assertion').split('.');
  const decoded = JSON.parse(atob(claim.replaceAll('-', '+').replaceAll('_', '/')));
  assert.equal(decoded.scope, 'https://www.googleapis.com/auth/datastore');
  assert.equal(decoded.aud, 'https://oauth2.googleapis.com/token');
  assert.equal(JSON.stringify(token).includes(pem), false);
});

test('rejects a service-account configuration for any other Firebase project before network access', async () => {
  let requests = 0;
  await assert.rejects(createGoogleAccessToken({
    serviceAccountJson: JSON.stringify({
      type: 'service_account', project_id: 'another-project', client_email: 'x@another-project.iam.gserviceaccount.com', private_key: 'secret',
    }),
    projectId: 'tudo-aqui-macacu',
    fetchImpl: async () => { requests += 1; throw new Error('must not be called'); },
  }), (error) => {
    assert.equal(error.code, 'signing-key-unavailable');
    assert.equal(error.message.includes('another-project'), false);
    return true;
  });
  assert.equal(requests, 0);
});

test('rejects a service-account identity outside the fixed Firebase project', async () => {
  let requests = 0;
  await assert.rejects(createGoogleAccessToken({
    serviceAccountJson: JSON.stringify({
      type: 'service_account', project_id: 'tudo-aqui-macacu',
      client_email: 'x@another-project.iam.gserviceaccount.com', private_key: 'secret',
    }),
    projectId: 'tudo-aqui-macacu',
    fetchImpl: async () => { requests += 1; throw new Error('must not be called'); },
  }), { code: 'signing-key-unavailable' });
  assert.equal(requests, 0);
});
