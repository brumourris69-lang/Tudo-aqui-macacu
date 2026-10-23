const FIREBASE_SIGNING_KEYS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const MAX_RESPONSE_BYTES = 128 * 1024;
const MAX_CACHE_SECONDS = 6 * 60 * 60;
const FALLBACK_CACHE_SECONDS = 60 * 60;

export class FirebaseSigningKeysError extends Error {
  constructor() {
    super('Firebase signing keys are unavailable.');
    this.name = 'FirebaseSigningKeysError';
    this.code = 'signing-key-unavailable';
  }
}

function cacheSeconds(header, maximum) {
  const match = /(?:^|,)\s*max-age=(\d+)/iu.exec(header ?? '');
  if (!match) return Math.min(FALLBACK_CACHE_SECONDS, maximum);
  return Math.max(0, Math.min(Number(match[1]), maximum));
}

function base64Url(bytes) {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
}

function encodeJson(value) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

async function readTextLimited(response, maximumBytes) {
  const reader = response.body?.getReader();
  if (!reader) return '';
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > maximumBytes) {
        await reader.cancel();
        throw new Error();
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw new FirebaseSigningKeysError();
  }
}

function decodePem(pem) {
  if (typeof pem !== 'string') throw new FirebaseSigningKeysError();
  const normalized = pem.replace(/\\n/gu, '\n').replace(/\r/gu, '');
  const match = /-----BEGIN PRIVATE KEY-----\s*([A-Za-z0-9+/=\s]+)\s*-----END PRIVATE KEY-----/u.exec(normalized);
  if (!match) throw new FirebaseSigningKeysError();
  try {
    const binary = atob(match[1].replace(/\s/gu, ''));
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  } catch {
    throw new FirebaseSigningKeysError();
  }
}

function decodeServiceAccount(raw, expectedProjectId) {
  try {
    if (typeof raw === 'string' && raw.length > 32 * 1024) throw new Error();
    const config = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!config || config.type !== 'service_account' || config.project_id !== expectedProjectId ||
      typeof config.client_email !== 'string' ||
      !config.client_email.endsWith(`@${expectedProjectId}.iam.gserviceaccount.com`) ||
      typeof config.private_key !== 'string') throw new Error();
    return config;
  } catch {
    throw new FirebaseSigningKeysError();
  }
}

async function importSigningKey(jwk) {
  try {
    if (!jwk || jwk.kty !== 'RSA' || typeof jwk.kid !== 'string' || !jwk.kid ||
      (jwk.use !== undefined && jwk.use !== 'sig') ||
      (jwk.alg !== undefined && jwk.alg !== 'RS256') ||
      typeof jwk.n !== 'string' || typeof jwk.e !== 'string') throw new Error();
    return await crypto.subtle.importKey(
      'jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify'],
    );
  } catch {
    throw new FirebaseSigningKeysError();
  }
}

/** Loads and caches Google's Firebase Secure Token signing JWKs. */
export function createFirebaseSigningKeyResolver({
  fetchImpl = fetch,
  now = Date.now,
  maxCacheSeconds = MAX_CACHE_SECONDS,
} = {}) {
  if (typeof fetchImpl !== 'function' || typeof now !== 'function' ||
    !Number.isSafeInteger(maxCacheSeconds) || maxCacheSeconds < 0) {
    throw new TypeError('Invalid Firebase key resolver configuration.');
  }
  let keys = new Map();
  let expiresAt = 0;
  let loading;
  let lastUnknownKeyRefreshAt = Number.NEGATIVE_INFINITY;

  async function load() {
    if (loading) return loading;
    loading = (async () => {
      try {
        const response = await fetchImpl(FIREBASE_SIGNING_KEYS_URL, {
          headers: { accept: 'application/json' },
          signal: AbortSignal.timeout(10_000),
        });
        if (!response.ok) throw new Error();
        const length = Number(response.headers.get('content-length') ?? 0);
        if (Number.isFinite(length) && length > MAX_RESPONSE_BYTES) throw new Error();
        const text = await readTextLimited(response, MAX_RESPONSE_BYTES);
        const parsed = JSON.parse(text);
        if (!Array.isArray(parsed?.keys) || parsed.keys.length === 0 || parsed.keys.length > 10) throw new Error();
        const next = new Map();
        for (const jwk of parsed.keys) {
          if (next.has(jwk?.kid)) throw new Error();
          next.set(jwk.kid, await importSigningKey(jwk));
        }
        keys = next;
        expiresAt = now() + cacheSeconds(response.headers.get('cache-control'), maxCacheSeconds) * 1000;
      } catch {
        throw new FirebaseSigningKeysError();
      } finally {
        loading = undefined;
      }
    })();
    return loading;
  }

  return async function getSigningKey(kid) {
    if (typeof kid !== 'string' || kid.length === 0 || kid.length > 256) return null;
    if (expiresAt <= now()) await load();
    let key = keys.get(kid);
    if (!key && now() - lastUnknownKeyRefreshAt >= 60_000) {
      lastUnknownKeyRefreshAt = now();
      expiresAt = 0;
      await load();
      key = keys.get(kid);
    }
    return key ?? null;
  };
}

/** Creates a short-lived OAuth assertion for server-only Firestore REST access. */
export async function createGoogleAccessToken({
  serviceAccountJson,
  projectId,
  fetchImpl = fetch,
  now = Date.now,
}) {
  if (typeof fetchImpl !== 'function' || typeof now !== 'function') throw new FirebaseSigningKeysError();
  const config = decodeServiceAccount(serviceAccountJson, projectId);
  let privateKey;
  try {
    privateKey = await crypto.subtle.importKey(
      'pkcs8', decodePem(config.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
    );
  } catch {
    throw new FirebaseSigningKeysError();
  }
  const issuedAt = Math.floor(now() / 1000);
  const header = encodeJson({ alg: 'RS256', typ: 'JWT' });
  const claim = encodeJson({
    iss: config.client_email,
    scope: 'https://www.googleapis.com/auth/datastore',
    aud: 'https://oauth2.googleapis.com/token',
    iat: issuedAt,
    exp: issuedAt + 3600,
  });
  const signingInput = `${header}.${claim}`;
  let signature;
  try {
    signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', privateKey,
      new TextEncoder().encode(signingInput));
  } catch {
    throw new FirebaseSigningKeysError();
  }
  const assertion = `${signingInput}.${base64Url(new Uint8Array(signature))}`;
  let response;
  try {
    response = await fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error();
    const length = Number(response.headers.get('content-length') ?? 0);
    if (Number.isFinite(length) && length > 16 * 1024) throw new Error();
    const text = await readTextLimited(response, 16 * 1024);
    const result = JSON.parse(text);
    if (typeof result?.access_token !== 'string' || result.access_token.length < 20 ||
      result.access_token.length > 8192 || result.token_type !== 'Bearer' ||
      !Number.isSafeInteger(result.expires_in) || result.expires_in < 60) throw new Error();
    return Object.freeze({ accessToken: result.access_token, expiresAt: now() + result.expires_in * 1000 });
  } catch {
    throw new FirebaseSigningKeysError();
  }
}
