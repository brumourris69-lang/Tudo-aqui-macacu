const { createHash, randomUUID } = require('node:crypto');
const { isAdminClaim } = require('./admin_policy');

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const HOME_FOLDER = 'tudo-aqui-macacu/home';
const FORMATS = ['jpg', 'png', 'webp'];

class UploadError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function requireAdmin(auth) {
  if (!auth || !auth.uid) {
    throw new UploadError('unauthenticated', 'Entre novamente para enviar a imagem.');
  }
  const token = auth.token || {};
  if (token.firebase?.sign_in_provider === 'anonymous') {
    throw new UploadError('permission-denied', 'Acesso administrativo necessário.');
  }
  const permitted = isAdminClaim(token);
  if (!permitted) {
    throw new UploadError('permission-denied', 'Somente administradores podem enviar imagens.');
  }
}

function imageFormat(bytes) {
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return 'png';
  if (bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return 'jpg';
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  throw new UploadError('invalid-argument', 'Use uma imagem JPEG, PNG ou WebP.');
}

function readImage(data) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).sort().join(',') !== 'imageBase64,purpose' || data.purpose !== 'home_logo') {
    throw new UploadError('invalid-argument', 'Parâmetros de upload inválidos.');
  }
  const encoded = data.imageBase64;
  const maxEncoded = 4 * Math.ceil(MAX_IMAGE_BYTES / 3);
  if (typeof encoded !== 'string' || !encoded.length || encoded.length > maxEncoded ||
      encoded.length % 4 !== 0 || /[^A-Za-z0-9+/=]/.test(encoded)) {
    throw new UploadError('invalid-argument', 'Imagem inválida ou maior que 5 MiB.');
  }
  const bytes = Buffer.from(encoded, 'base64');
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES || bytes.toString('base64') !== encoded) {
    throw new UploadError('invalid-argument', 'Imagem inválida ou maior que 5 MiB.');
  }
  return { bytes, format: imageFormat(bytes) };
}

// Official Cloudinary REST signing: sort parameters, join with &, append the
// secret, hash UTF-8 using SHA-256. file/api_key/resource_type are not signed.
function signParameters(params, secret) {
  const canonical = Object.keys(params).sort().map((key) => `${key}=${params[key]}`).join('&');
  return createHash('sha256').update(canonical + secret, 'utf8').digest('hex');
}

function validateConfig(config) {
  if (!config || !/^[a-zA-Z0-9_-]{1,128}$/.test(config.cloudName || '') ||
      !/^\d+$/.test(config.apiKey || '') || typeof config.apiSecret !== 'string' ||
      !config.apiSecret || !['dynamic', 'fixed'].includes(config.folderMode)) {
    throw new UploadError('failed-precondition', 'O upload ainda não foi configurado no servidor.');
  }
}

function validateResult(result, cloudName, publicId) {
  let url;
  try { url = new URL(result.secure_url); } catch (_) {
    throw new UploadError('data-loss', 'Resposta de upload inválida.');
  }
  const expectedPath = `/${cloudName}/image/upload/v${result.version}/${publicId}.${result.format}`;
  if (url.protocol !== 'https:' || url.hostname !== 'res.cloudinary.com' || url.port ||
      url.username || url.password || url.search || url.hash || url.pathname !== expectedPath ||
      result.public_id !== publicId || result.resource_type !== 'image' || result.type !== 'upload' ||
      !FORMATS.includes(result.format) || !Number.isSafeInteger(result.version) || result.version <= 0 ||
      !Number.isSafeInteger(result.bytes) || result.bytes <= 0 || result.bytes > MAX_IMAGE_BYTES ||
      !Number.isSafeInteger(result.width) || result.width <= 0 ||
      !Number.isSafeInteger(result.height) || result.height <= 0) {
    throw new UploadError('data-loss', 'Resposta de upload inválida.');
  }
  return {
    secureUrl: url.toString(), publicId, width: result.width, height: result.height,
    format: result.format, bytes: result.bytes,
  };
}

async function uploadHomeImage(request, {
  getConfig, fetchImpl = fetch, now = Date.now, uuid = randomUUID, authorize,
}) {
  requireAdmin(request.auth);
  {
    if (!authorize) throw new UploadError('failed-precondition', 'Autorização administrativa indisponível.');
    let permitted;
    try { permitted = await authorize(request.auth); }
    catch (_) { throw new UploadError('unavailable', 'Não foi possível validar a autorização.'); }
    if (permitted !== true) throw new UploadError('permission-denied', 'Acesso administrativo revogado ou indisponível.');
  }
  const image = readImage(request.data);
  return uploadImageBytes(image.bytes, { getConfig, fetchImpl, now, uuid });
}

// Shared server-only transport for Functions and Workers. Raw bytes avoid the
// base64 expansion/decoding cost on Workers Free. Neither caller trusts MIME.
async function uploadImageBytes(bytes, {
  getConfig, fetchImpl = fetch, now = Date.now, uuid = randomUUID,
}) {
  if (!bytes.length || bytes.length > MAX_IMAGE_BYTES) {
    throw new UploadError('invalid-argument', 'Imagem inválida ou maior que 5 MiB.');
  }
  const image = { bytes, format: imageFormat(bytes) };
  const config = getConfig();
  validateConfig(config);
  const publicId = `${HOME_FOLDER}/${uuid()}`;
  const params = {
    allowed_formats: FORMATS.join(','), overwrite: 'false', public_id: publicId,
    timestamp: String(Math.floor(now() / 1000)), type: 'upload',
  };
  if (config.folderMode === 'dynamic') params.asset_folder = HOME_FOLDER;
  const body = new FormData();
  for (const [key, value] of Object.entries(params)) body.append(key, value);
  body.append('api_key', config.apiKey);
  body.append('signature', signParameters(params, config.apiSecret));
  body.append('file', new Blob([image.bytes], { type: `image/${image.format === 'jpg' ? 'jpeg' : image.format}` }), `image.${image.format}`);
  let response;
  try {
    response = await fetchImpl(`https://api.cloudinary.com/v1_1/${config.cloudName}/image/upload`, {
      method: 'POST', body, redirect: 'error', signal: AbortSignal.timeout(45000),
    });
  } catch (_) {
    // Never log transport errors: they can include request details or credentials.
    throw new UploadError('unavailable', 'Não foi possível enviar. Tente novamente.');
  }
  if (!response.ok) {
    throw new UploadError(response.status === 400 ? 'invalid-argument' : 'unavailable',
      response.status === 400 ? 'O provedor rejeitou a imagem. Use JPEG, PNG ou WebP.' : 'Não foi possível enviar. Tente novamente.');
  }
  let result;
  try { result = await response.json(); } catch (_) {
    throw new UploadError('data-loss', 'Resposta de upload inválida.');
  }
  if (!result || typeof result !== 'object') {
    throw new UploadError('data-loss', 'Resposta de upload inválida.');
  }
  return validateResult(result, config.cloudName, publicId);
}

module.exports = { uploadHomeImage, uploadImageBytes, requireAdmin, UploadError, MAX_IMAGE_BYTES, HOME_FOLDER, imageFormat, signParameters };
