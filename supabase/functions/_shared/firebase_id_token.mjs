const MAX_TOKEN_LENGTH = 16_384;
const MAX_UID_LENGTH = 128;
const DEFAULT_CLOCK_SKEW_SECONDS = 60;

const ERROR_MESSAGES = Object.freeze({
  'invalid-token': 'Firebase ID token is invalid.',
  'invalid-signature': 'Firebase ID token signature is invalid.',
  'unknown-signing-key': 'Firebase ID token signing key is unknown.',
  'signing-key-unavailable': 'Firebase ID token signing key is unavailable.',
  'wrong-project': 'Firebase ID token belongs to another project.',
  'expired-token': 'Firebase ID token is expired.',
  'anonymous-user': 'Anonymous Firebase users are not accepted.',
});

export class FirebaseTokenVerificationError extends Error {
  constructor(code) {
    super(ERROR_MESSAGES[code] ?? ERROR_MESSAGES['invalid-token']);
    this.name = 'FirebaseTokenVerificationError';
    this.code = ERROR_MESSAGES[code] ? code : 'invalid-token';
  }
}

function fail(code) {
  throw new FirebaseTokenVerificationError(code);
}

function decodeBase64Url(value) {
  if (typeof value !== 'string' || value.length === 0 ||
    !/^[A-Za-z0-9_-]+$/u.test(value)) {
    fail('invalid-token');
  }

  const standard = value.replaceAll('-', '+').replaceAll('_', '/');
  const padded = standard + '='.repeat((4 - standard.length % 4) % 4);
  try {
    const binary = atob(padded);
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    fail('invalid-token');
  }
}

function decodeJsonSegment(segment) {
  try {
    const bytes = decodeBase64Url(segment);
    const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    const value = JSON.parse(text);
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      fail('invalid-token');
    }
    return value;
  } catch (error) {
    if (error instanceof FirebaseTokenVerificationError) throw error;
    fail('invalid-token');
  }
}

function isNumericDate(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

/**
 * Verifies a Firebase ID token using an injected public-key resolver.
 * The resolver must return a WebCrypto CryptoKey for the token's `kid` or
 * null when the key is unknown. This module performs no network requests and
 * emits no logs; production key retrieval and caching belong to its caller.
 * @param {string} token
 * @param {{projectId: string, getSigningKey: (kid: string) => Promise<CryptoKey | null>, now?: () => number, clockSkewSeconds?: number}} options
 * @returns {Promise<Readonly<{uid: string, authTime: number, isAnonymous: false, provider: string}>>}
 */
export async function verifyFirebaseIdToken(token, {
  projectId,
  getSigningKey,
  now = Date.now,
  clockSkewSeconds = DEFAULT_CLOCK_SKEW_SECONDS,
} = {}) {
  if (typeof token !== 'string' || token.length > MAX_TOKEN_LENGTH ||
    typeof projectId !== 'string' || projectId.length === 0 ||
    typeof getSigningKey !== 'function' || typeof now !== 'function' ||
    !Number.isSafeInteger(clockSkewSeconds) || clockSkewSeconds < 0 ||
    clockSkewSeconds > 300) {
    fail('invalid-token');
  }

  const segments = token.split('.');
  if (segments.length !== 3) fail('invalid-token');

  const [encodedHeader, encodedPayload, encodedSignature] = segments;
  const header = decodeJsonSegment(encodedHeader);
  if (header.alg !== 'RS256' || typeof header.kid !== 'string' ||
    header.kid.length === 0 || header.kid.length > 256) {
    fail('invalid-token');
  }

  let key;
  try {
    key = await getSigningKey(header.kid);
  } catch {
    fail('signing-key-unavailable');
  }
  if (key === null || key === undefined) fail('unknown-signing-key');

  let validSignature;
  try {
    validSignature = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      decodeBase64Url(encodedSignature),
      new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
    );
  } catch {
    fail('signing-key-unavailable');
  }
  if (!validSignature) fail('invalid-signature');

  const payload = decodeJsonSegment(encodedPayload);
  if (payload.aud !== projectId ||
    payload.iss !== `https://securetoken.google.com/${projectId}`) {
    fail('wrong-project');
  }

  const nowSeconds = Math.floor(now() / 1000);
  if (!Number.isSafeInteger(nowSeconds) ||
    !isNumericDate(payload.exp) || !isNumericDate(payload.iat) ||
    !isNumericDate(payload.auth_time) || payload.exp <= nowSeconds ||
    payload.exp <= payload.iat || payload.auth_time > payload.iat ||
    payload.iat > nowSeconds + clockSkewSeconds ||
    payload.auth_time > nowSeconds + clockSkewSeconds ||
    (payload.nbf !== undefined &&
      (!isNumericDate(payload.nbf) ||
        payload.nbf > nowSeconds + clockSkewSeconds))) {
    fail('expired-token');
  }

  if (typeof payload.sub !== 'string' || payload.sub.length === 0 ||
    payload.sub.length > MAX_UID_LENGTH) {
    fail('invalid-token');
  }

  const provider = payload.firebase?.sign_in_provider;
  if (typeof provider !== 'string' || provider.length === 0 || provider.length > 128) {
    fail('invalid-token');
  }
  if (provider === 'anonymous') fail('anonymous-user');

  return Object.freeze({
    uid: payload.sub,
    authTime: payload.auth_time,
    isAnonymous: false,
    provider,
  });
}
