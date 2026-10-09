import { Buffer } from 'node:buffer';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import upload from '../../../functions/home_image_upload.js';
import { verifyAdminState } from './admin-state.js';

const { requireAdmin, uploadImageBytes, UploadError, MAX_IMAGE_BYTES } = upload;
// Keys come only from Google's fixed endpoint; never from a JWT-supplied URL.
const keys = createRemoteJWKSet(new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
), { timeoutDuration: 5000 });

export async function verifyFirebaseToken(token, projectId, keySet = keys) {
  if (projectId !== 'tudo-aqui-macacu') {
    throw new UploadError('failed-precondition', 'Configuração de autenticação inválida.');
  }
  try {
    const { payload, protectedHeader } = await jwtVerify(token, keySet, {
      algorithms: ['RS256'], audience: projectId,
      issuer: `https://securetoken.google.com/${projectId}`,
      requiredClaims: ['exp', 'iat', 'sub', 'auth_time'],
    });
    const now = Math.floor(Date.now() / 1000);
    if (typeof protectedHeader.kid !== 'string' || !protectedHeader.kid.length ||
        typeof payload.sub !== 'string' || !payload.sub.length || payload.sub.length > 128 ||
        !Number.isSafeInteger(payload.iat) || payload.iat > now ||
        !Number.isSafeInteger(payload.auth_time) || payload.auth_time > now) {
      throw new Error('invalid claims');
    }
    return { uid: payload.sub, token: payload };
  } catch (_) {
    throw new UploadError('unauthenticated', 'Entre novamente para enviar a imagem.');
  }
}

function json(body, status = 200) {
  return Response.json(body, { status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  } });
}

async function readBoundedBody(request) {
  const declared = request.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > MAX_IMAGE_BYTES)) {
    throw new UploadError('invalid-argument', 'Escolha uma imagem de até 5 MiB.');
  }
  if (!request.body) throw new UploadError('invalid-argument', 'Imagem vazia.');
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_IMAGE_BYTES) {
        await reader.cancel();
        throw new UploadError('invalid-argument', 'Escolha uma imagem de até 5 MiB.');
      }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return Buffer.concat(chunks, size);
}

export function createHandler({ verify = verifyFirebaseToken, send = uploadImageBytes,
  authorize = verifyAdminState } = {}) {
  return async (request, env) => {
    const url = new URL(request.url);
    if (url.pathname !== '/v1/home-logo' || url.search) return json({ error: 'not-found' }, 404);
    if (request.method !== 'POST') return json({ error: 'method-not-allowed' }, 405);
    // Native Android/iOS endpoint. Browser origins are deliberately not enabled.
    if (request.headers.has('origin')) return json({ error: 'permission-denied' }, 403);
    try {
      const authorization = request.headers.get('authorization') || '';
      if (!/^Bearer [A-Za-z0-9_.-]{1,8192}$/.test(authorization)) {
        throw new UploadError('unauthenticated', 'Entre novamente para enviar a imagem.');
      }
      const auth = await verify(authorization.slice(7), env.FIREBASE_PROJECT_ID);
      requireAdmin(auth);
      // Fail closed if the binding is missing, instead of silently removing protection.
      if (!env.UPLOAD_RATE_LIMITER) throw new UploadError('failed-precondition', 'Upload não configurado.');
      const { success } = await env.UPLOAD_RATE_LIMITER.limit({ key: `home-logo:${auth.uid}` });
      if (!success) throw new UploadError('resource-exhausted', 'Aguarde um minuto antes de enviar novamente.');
      if (await authorize(auth, authorization.slice(7), env.FIREBASE_PROJECT_ID) !== true) {
        throw new UploadError('permission-denied', 'Acesso administrativo revogado ou indisponível.');
      }
      if (request.headers.get('content-type') !== 'application/octet-stream') {
        throw new UploadError('invalid-argument', 'Formato da requisição inválido.');
      }
      const bytes = await readBoundedBody(request);
      // Body streaming can take time. Recheck immediately before the external
      // side effect so a revocation during reception cannot authorize upload.
      if (await authorize(auth, authorization.slice(7), env.FIREBASE_PROJECT_ID) !== true) {
        throw new UploadError('permission-denied', 'Acesso administrativo revogado ou indisponível.');
      }
      const result = await send(bytes, { getConfig: () => ({
        cloudName: env.CLOUDINARY_CLOUD_NAME, apiKey: env.CLOUDINARY_API_KEY,
        apiSecret: env.CLOUDINARY_API_SECRET, folderMode: env.CLOUDINARY_FOLDER_MODE,
      }) });
      return json(result);
    } catch (error) {
      // No JWTs, payloads, provider responses or credentials enter logs/responses.
      const code = error instanceof UploadError ? error.code : 'unavailable';
      const statuses = { unauthenticated: 401, 'permission-denied': 403,
        'invalid-argument': 400, 'failed-precondition': 503,
        'resource-exhausted': 429, 'data-loss': 502, unavailable: 502 };
      return json({ error: code }, statuses[code] || 502);
    }
  };
}

export default { fetch: createHandler() };
