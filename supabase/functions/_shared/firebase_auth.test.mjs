import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyFirebaseIdToken } from './firebase_id_token.mjs';
import {
  AdminAuthorizationError,
  authorizeAdmin,
} from './admin_authorization.mjs';

const PROJECT_ID = 'tudo-aqui-macacu';
const ISSUER = `https://securetoken.google.com/${PROJECT_ID}`;
const NOW = 1_797_000_000;

const signingKeyPair = await crypto.subtle.generateKey(
  {
    name: 'RSASSA-PKCS1-v1_5',
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: 'SHA-256',
  },
  true,
  ['sign', 'verify'],
);

function encodeBase64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/u, '');
}

function encodeJson(value) {
  return encodeBase64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function makeToken(overrides = {}, keyPair = signingKeyPair) {
  const header = encodeJson({ alg: 'RS256', kid: 'test-key-1', typ: 'JWT' });
  const payload = encodeJson({
    aud: PROJECT_ID,
    iss: ISSUER,
    sub: 'demo-user-123',
    iat: NOW - 30,
    exp: NOW + 300,
    auth_time: NOW - 30,
    firebase: { sign_in_provider: 'password' },
    ...overrides,
  });
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    keyPair.privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${encodeBase64Url(new Uint8Array(signature))}`;
}

function verifierOptions(extra = {}) {
  return {
    projectId: PROJECT_ID,
    now: () => NOW * 1000,
    getSigningKey: async (kid) => kid === 'test-key-1'
      ? signingKeyPair.publicKey
      : null,
    ...extra,
  };
}

test('verifies signature, issuer, audience, expiry and non-anonymous identity', async () => {
  const token = await makeToken();
  let keyLookups = 0;
  const identity = await verifyFirebaseIdToken(token, verifierOptions({
    getSigningKey: async (kid) => {
      keyLookups += 1;
      return kid === 'test-key-1' ? signingKeyPair.publicKey : null;
    },
  }));

  assert.deepEqual(identity, {
    uid: 'demo-user-123',
    authTime: NOW - 30,
    isAnonymous: false,
    provider: 'password',
  });
  assert.equal(keyLookups, 1);
  assert.equal(JSON.stringify(identity).includes(token), false);
});

test('rejects malformed and tampered tokens without echoing token material', async () => {
  const token = await makeToken();
  const [header, payload, encodedSignature] = token.split('.');
  const signature = decodeBase64UrlForTest(encodedSignature);
  signature[0] ^= 0xff;
  const tampered = `${header}.${payload}.${encodeBase64Url(signature)}`;

  await assert.rejects(
    verifyFirebaseIdToken('not-a-jwt', verifierOptions()),
    { code: 'invalid-token' },
  );
  await assert.rejects(
    verifyFirebaseIdToken(tampered, verifierOptions()),
    (error) => {
      assert.equal(error.name, 'FirebaseTokenVerificationError');
      assert.equal(error.code, 'invalid-signature');
      assert.equal(error.message.includes(tampered), false);
      return true;
    },
  );
});

function decodeBase64UrlForTest(value) {
  const standard = value.replaceAll('-', '+').replaceAll('_', '/');
  const padded = standard + '='.repeat((4 - standard.length % 4) % 4);
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

test('rejects a token issued for another Firebase project', async () => {
  const token = await makeToken({ aud: 'another-firebase-project' });
  await assert.rejects(
    verifyFirebaseIdToken(token, verifierOptions()),
    { code: 'wrong-project' },
  );
});

test('rejects a mismatched issuer even when the audience is correct', async () => {
  const token = await makeToken({ iss: 'https://securetoken.google.com/other' });
  await assert.rejects(
    verifyFirebaseIdToken(token, verifierOptions()),
    { code: 'wrong-project' },
  );
});

test('rejects an expired token', async () => {
  const token = await makeToken({ exp: NOW - 1 });
  await assert.rejects(
    verifyFirebaseIdToken(token, verifierOptions()),
    { code: 'expired-token' },
  );
});

test('rejects anonymous sign-in tokens', async () => {
  const token = await makeToken({
    firebase: { sign_in_provider: 'anonymous' },
  });
  await assert.rejects(
    verifyFirebaseIdToken(token, verifierOptions()),
    { code: 'anonymous-user' },
  );
});

test('rejects a signed token without a valid Firebase sign-in provider', async () => {
  await assert.rejects(
    verifyFirebaseIdToken(await makeToken({ firebase: {} }), verifierOptions()),
    { code: 'invalid-token' },
  );
  await assert.rejects(
    verifyFirebaseIdToken(await makeToken({ firebase: { sign_in_provider: 'p'.repeat(129) } }), verifierOptions()),
    { code: 'invalid-token' },
  );
});

test('fails closed when the signing key is unknown or unavailable', async () => {
  const unknownKid = `${encodeJson({ alg: 'RS256', kid: 'unknown-key' })}.${
    (await makeToken()).split('.').slice(1).join('.')
  }`;
  await assert.rejects(
    verifyFirebaseIdToken(unknownKid, verifierOptions()),
    { code: 'unknown-signing-key' },
  );
  await assert.rejects(
    verifyFirebaseIdToken(await makeToken(), verifierOptions({
      getSigningKey: async () => { throw new Error('sensitive provider detail'); },
    })),
    (error) => {
      assert.equal(error.code, 'signing-key-unavailable');
      assert.equal(error.message.includes('sensitive'), false);
      return true;
    },
  );
});

test('authorizes an active, non-pending record with a valid version', async () => {
  let requestedUid;
  const result = await authorizeAdmin(
    { uid: 'demo-user-123', isAnonymous: false },
    async (uid) => {
      requestedUid = uid;
      return { enabled: true, pending: false, version: 'admin-v3' };
    },
  );

  assert.equal(requestedUid, 'demo-user-123');
  assert.deepEqual(result, { authorized: true, version: 'admin-v3' });
});

test('denies absent, disabled, pending, revoked and malformed authorization records', async () => {
  const deniedStates = [
    null,
    { enabled: false, pending: false, version: 'admin-v3' },
    { enabled: true, pending: true, version: 'admin-v3' },
    { enabled: true, pending: false, revoked: true, version: 'admin-v3' },
    { enabled: true, pending: false, revokedAt: '2026-10-19', version: 'admin-v3' },
    { enabled: true, pending: false, version: '' },
    { enabled: true, pending: false, version: 'bad version' },
    { enabled: true, pending: false, version: 'x'.repeat(65) },
  ];

  for (const state of deniedStates) {
    await assert.rejects(
      authorizeAdmin(
        { uid: 'demo-user-123', isAnonymous: false },
        async () => state,
      ),
      { code: 'admin-not-authorized' },
    );
  }
});

test('denies unverified and anonymous identities before reading authorization', async () => {
  let reads = 0;
  const read = async () => {
    reads += 1;
    return { enabled: true, pending: false, version: 'admin-v3' };
  };

  for (const identity of [null, { uid: '', isAnonymous: false }, {
    uid: 'demo-user-123',
    isAnonymous: true,
  }, { uid: 'demo-user-123' }]) {
    await assert.rejects(
      authorizeAdmin(identity, read),
      { code: 'admin-not-authorized' },
    );
  }
  assert.equal(reads, 0);
});

test('fails closed on authorization-store unavailability with sanitized error', async () => {
  const secretDetail = 'private database endpoint and credential';
  await assert.rejects(
    authorizeAdmin(
      { uid: 'demo-user-123', isAnonymous: false },
      async () => { throw new Error(secretDetail); },
    ),
    (error) => {
      assert.ok(error instanceof AdminAuthorizationError);
      assert.equal(error.code, 'authorization-unavailable');
      assert.equal(error.message.includes(secretDetail), false);
      return true;
    },
  );
});

test('does not write token or authorization failure details to console logs', async () => {
  const methods = ['debug', 'info', 'log', 'warn', 'error'];
  const original = Object.fromEntries(
    methods.map((method) => [method, console[method]]),
  );
  const output = [];
  for (const method of methods) {
    console[method] = (...values) => output.push(values.join(' '));
  }

  try {
    await assert.rejects(
      verifyFirebaseIdToken('sensitive-token-sentinel', verifierOptions()),
    );
    await assert.rejects(
      authorizeAdmin(
        { uid: 'demo-user-123', isAnonymous: false },
        async () => { throw new Error('sensitive-store-error-sentinel'); },
      ),
    );
  } finally {
    for (const method of methods) console[method] = original[method];
  }

  assert.deepEqual(output, []);
  assert.equal(output.join(' ').includes('sentinel'), false);
});
