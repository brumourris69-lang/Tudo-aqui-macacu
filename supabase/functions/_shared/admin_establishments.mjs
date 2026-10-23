const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const MAX_VERSION = 2_147_483_647;
const MAX_BODY_BYTES = 32 * 1024;
const CATEGORIES = new Set([
  'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
  'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia',
  'Serviços', 'Profissionais',
]);
const DATA_FIELDS = new Set([
  'name', 'title', 'description', 'shortDescription', 'category', 'subcategory',
  'location', 'address', 'active', 'published', 'featured', 'imageUrl', 'logoUrl',
  'artwork', 'galleryUrls', 'open', 'hours', 'services', 'products',
  'additionalInfo', 'promotionTitle', 'promotionDescription', 'link', 'maps',
  'mapsUrl', 'phone', 'whatsapp', 'instagram', 'publicContactApproved', 'expiresAt',
]);
const STRING_LIMITS = Object.freeze({
  description: 3000, shortDescription: 1000, subcategory: 120,
  location: 240, address: 240, hours: 500, additionalInfo: 3000,
  promotionTitle: 180, promotionDescription: 1000, imageUrl: 2048,
  logoUrl: 2048, link: 2048, maps: 2048, mapsUrl: 2048,
  phone: 64, whatsapp: 2048, instagram: 512,
});
const CATALOG_ROW_FIELDS = Object.freeze([
  'id', 'name', 'summary', 'category', 'subcategory', 'image_url',
  'published', 'active', 'expires_at', 'deleted_at',
]);

const ERRORS = Object.freeze({
  invalid_request: [400, 'A solicitação é inválida.'],
  unauthenticated: [401, 'Entre novamente para continuar.'],
  permission_denied: [403, 'Você não tem autorização para esta operação.'],
  conflict: [409, 'O conteúdo mudou. Atualize e tente novamente.'],
  backend_unavailable: [503, 'O serviço está indisponível. Tente novamente.'],
  internal: [500, 'Não foi possível concluir a operação.'],
});

export class AdminEstablishmentsError extends Error {
  constructor(code) {
    const safeCode = Object.hasOwn(ERRORS, code) ? code : 'internal';
    super(ERRORS[safeCode][1]);
    this.name = 'AdminEstablishmentsError';
    this.code = safeCode;
  }
}

function fail(code) {
  throw new AdminEstablishmentsError(code);
}

function jsonResponse(status, value, extraHeaders = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...extraHeaders },
  });
}

function errorResponse(code) {
  const [status, message] = ERRORS[code] ?? ERRORS.internal;
  return jsonResponse(status, { error: { code, message } });
}

function parseBearer(request) {
  const value = request.headers.get('authorization') ?? '';
  const match = /^Bearer ([A-Za-z0-9._~-]{1,16384})$/u.exec(value);
  if (!match) fail('unauthenticated');
  return match[1];
}

async function parseRequest(request) {
  const declaredLength = Number(request.headers.get('content-length') ?? 0);
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) fail('invalid_request');
  const reader = request.body?.getReader();
  if (!reader) fail('invalid_request');
  const chunks = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > MAX_BODY_BYTES) {
        await reader.cancel();
        fail('invalid_request');
      }
      chunks.push(value);
    }
  } catch (error) {
    if (error instanceof AdminEstablishmentsError) throw error;
    fail('invalid_request');
  } finally {
    reader.releaseLock();
  }
  if (length === 0) fail('invalid_request');
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let body;
  try {
    body = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    fail('invalid_request');
  }
  if (body === null || typeof body !== 'object' || Array.isArray(body) ||
    Object.keys(body).some((key) => !['operation', 'requestId', 'entityId', 'expectedVersion', 'data'].includes(key))) {
    fail('invalid_request');
  }
  if (!['create', 'update', 'unpublish', 'republish', 'delete'].includes(body.operation) ||
    typeof body.requestId !== 'string' || !REQUEST_ID_PATTERN.test(body.requestId)) {
    fail('invalid_request');
  }
  if (body.operation === 'create') {
    if (Object.hasOwn(body, 'expectedVersion') ||
      (Object.hasOwn(body, 'entityId') && !isFirestoreDocumentId(body.entityId))) fail('invalid_request');
    body.data = validateData(body.data, { creating: true });
  } else {
    if (!isFirestoreDocumentId(body.entityId) || !Number.isSafeInteger(body.expectedVersion) ||
      body.expectedVersion < 0 || body.expectedVersion >= MAX_VERSION) fail('invalid_request');
    if (body.operation === 'update' || body.operation === 'republish') {
      if (body.operation === 'republish' && !Object.hasOwn(body, 'data')) {
        // Backward-compatible metadata-only republish remains supported.
      } else {
        body.data = validateData(body.data, { creating: false });
        if (body.operation === 'republish' && body.data.published === false) {
          fail('invalid_request');
        }
      }
    } else if (Object.hasOwn(body, 'data')) fail('invalid_request');
  }
  return body;
}

function validString(value, max, { required = false } = {}) {
  return typeof value === 'string' && value.trim().length <= max &&
    (!required || value.trim().length > 0) && !/[\u0000-\u001f\u007f]/u.test(value);
}

function isFirestoreDocumentId(value) {
  if (typeof value !== 'string' || value.length === 0 || value.includes('/') ||
    new TextEncoder().encode(value).byteLength > 1500 || value === '.' || value === '..') return false;
  return !value.startsWith('__') || !value.endsWith('__') || /^__id\d+__$/u.test(value);
}

function validHttpsUrl(value, { geo = false } = {}) {
  if (value === '') return true;
  try {
    const url = new URL(value);
    return (url.protocol === 'https:' && Boolean(url.hostname) && !url.username && !url.password) ||
      (geo && url.protocol === 'geo:' && value.length <= 2048);
  } catch {
    return geo && /^geo:[0-9.+-]+,[0-9.+-]+(?:\?.*)?$/iu.test(value);
  }
}

function validPhone(value) {
  if (value === '') return true;
  const normalized = value.startsWith('tel:') ? value.slice(4) : value;
  return /^\+?[0-9][0-9 ()().-]{4,30}$/u.test(normalized);
}

function validWhatsapp(value) {
  if (value === '') return true;
  if (validPhone(value)) return true;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      ['wa.me', 'api.whatsapp.com'].includes(url.hostname.toLowerCase()) && url.pathname.length > 1;
  } catch {
    return false;
  }
}

function validInstagram(value) {
  if (value === '') return true;
  if (/^@?[A-Za-z0-9._]{1,30}$/u.test(value)) return true;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password &&
      ['instagram.com', 'www.instagram.com'].includes(url.hostname.toLowerCase()) && url.pathname.length > 1;
  } catch {
    return false;
  }
}

function isValidIsoTimestamp(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-](\d{2}):(\d{2}))$/u.exec(value);
  if (!match) return false;
  const [, yearText, monthText, dayText, hourText, minuteText, secondText, , offsetHourText, offsetMinuteText] = match;
  const year = Number(yearText), month = Number(monthText), day = Number(dayText);
  const hour = Number(hourText), minute = Number(minuteText), second = Number(secondText);
  if (year < 1 || month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) return false;
  const date = new Date(0);
  date.setUTCHours(0, 0, 0, 0);
  date.setUTCFullYear(year, month - 1, day);
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return false;
  if (offsetHourText !== undefined && (Number(offsetHourText) > 23 || Number(offsetMinuteText) > 59)) return false;
  return Number.isFinite(Date.parse(value));
}

function validateData(input, { creating }) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) fail('invalid_request');
  const keys = Object.keys(input);
  if (keys.length === 0 || keys.some((key) => !DATA_FIELDS.has(key))) fail('invalid_request');

  for (const key of ['name', 'title']) {
    if (Object.hasOwn(input, key) && !validString(input[key], 140, { required: true })) fail('invalid_request');
  }
  if (input.name !== undefined && input.title !== undefined && input.name.trim() !== input.title.trim()) fail('invalid_request');
  if (creating && !((typeof input.name === 'string' && input.name.trim()) ||
    (typeof input.title === 'string' && input.title.trim()))) fail('invalid_request');
  if (creating && (typeof input.category !== 'string' || !CATEGORIES.has(input.category))) fail('invalid_request');

  for (const [key, max] of Object.entries(STRING_LIMITS)) {
    if (Object.hasOwn(input, key) && !validString(input[key], max)) fail('invalid_request');
  }
  if (Object.hasOwn(input, 'category') &&
    (typeof input.category !== 'string' || !CATEGORIES.has(input.category))) fail('invalid_request');
  if (Object.hasOwn(input, 'imageUrl') && !validHttpsUrl(input.imageUrl)) fail('invalid_request');
  if (Object.hasOwn(input, 'logoUrl') && !validHttpsUrl(input.logoUrl)) fail('invalid_request');
  for (const key of ['link', 'mapsUrl']) {
    if (Object.hasOwn(input, key) && !validHttpsUrl(input[key])) fail('invalid_request');
  }
  if (Object.hasOwn(input, 'maps') && !validHttpsUrl(input.maps, { geo: true })) fail('invalid_request');
  if (Object.hasOwn(input, 'phone') && !validPhone(input.phone)) fail('invalid_request');
  if (Object.hasOwn(input, 'whatsapp') && !validWhatsapp(input.whatsapp)) fail('invalid_request');
  if (Object.hasOwn(input, 'instagram') && !validInstagram(input.instagram)) fail('invalid_request');
  for (const key of ['active', 'published', 'featured', 'open', 'publicContactApproved']) {
    if (Object.hasOwn(input, key) && typeof input[key] !== 'boolean') fail('invalid_request');
  }
  if (Object.hasOwn(input, 'artwork') && (!Number.isSafeInteger(input.artwork) || input.artwork < 0)) fail('invalid_request');
  for (const key of ['services', 'products', 'galleryUrls']) {
    if (!Object.hasOwn(input, key)) continue;
    const max = key === 'galleryUrls' ? 20 : 100;
    const maxItemLength = key === 'galleryUrls' ? 2048 : 240;
    if (!Array.isArray(input[key]) || input[key].length > max ||
      input[key].some((value) => !validString(value, maxItemLength) ||
        (key === 'galleryUrls' && !validHttpsUrl(value)))) fail('invalid_request');
  }
  if (Object.hasOwn(input, 'expiresAt') && input.expiresAt !== null &&
    (typeof input.expiresAt !== 'string' || !isValidIsoTimestamp(input.expiresAt))) fail('invalid_request');

  return structuredClone(input);
}

function sourceFields(data, { creating }) {
  const result = { ...data };
  const deleteFields = [];
  if (result.expiresAt === null) {
    delete result.expiresAt;
    if (!creating) deleteFields.push('expiresAt');
  } else if (typeof result.expiresAt === 'string') {
    result.expiresAt = new Date(result.expiresAt);
  }
  if (data.name !== undefined || data.title !== undefined) {
    const name = (data.name ?? data.title).trim();
    result.name = name;
    result.title = name;
  }
  if (creating) {
    result.active ??= true;
    result.published ??= true;
    result.featured ??= false;
  }
  return { data: result, deleteFields };
}

function validStoredVersion(data) {
  const version = data.catalogVersion === undefined ? 0 : data.catalogVersion;
  if (!Number.isSafeInteger(version) || version < 0 || version >= MAX_VERSION) fail('conflict');
  return version;
}

function makeOutboxEvent({ operationId, entityId, authorUid, version }) {
  return {
    schemaVersion: 2,
    operationId,
    entityType: 'establishment',
    entityId,
    authorUid,
    version,
    operation: 'reconcile',
    state: 'pending',
    attemptCount: 0,
    workerId: null,
    leaseToken: null,
    leaseExpiresAt: null,
    nextAttemptAt: null,
    lastErrorCode: null,
    syncedAt: null,
  };
}

function replayResult(event, identity, requestId) {
  const lifecycleFields = [
    'workerId', 'leaseToken', 'leaseExpiresAt', 'nextAttemptAt', 'lastErrorCode', 'syncedAt',
  ];
  const supportedSchema = event?.schemaVersion === 1 ||
    (event?.schemaVersion === 2 && lifecycleFields.every((field) => Object.hasOwn(event, field)));
  if (event?.authorUid !== identity.uid || event?.entityType !== 'establishment' ||
    !supportedSchema || event?.operationId !== requestId || event?.operation !== 'reconcile' ||
    !isFirestoreDocumentId(event.entityId) || !Number.isSafeInteger(event.version) || event.version < 1) {
    fail('conflict');
  }
  return { status: 200, result: 'replayed', operationId: event.operationId,
    entityId: event.entityId, version: event.version, replayed: true };
}

function mapFailure(error) {
  if (error instanceof AdminEstablishmentsError) return error.code;
  if (['invalid-token', 'invalid-signature', 'unknown-signing-key', 'wrong-project', 'expired-token'].includes(error?.code)) {
    return 'unauthenticated';
  }
  if (error?.code === 'anonymous-user') return 'permission_denied';
  if (error?.code === 'signing-key-unavailable') return 'backend_unavailable';
  if (error?.code === 'admin-not-authorized') return 'permission_denied';
  if (error?.code === 'authorization-unavailable' || error?.code === 'backend_unavailable' ||
    error?.code === 'signing-key-unavailable' || error?.code === 'invalid-config') return 'backend_unavailable';
  if (error?.code === 'conflict') return 'conflict';
  return 'internal';
}

/**
 * Returns the allowlisted row shape for the private Supabase catalog table.
 * Lifecycle controls are retained there so RPCs can filter visibility; this
 * object is not an HTTP response. Public RPCs return narrower SQL projections.
 * Contact fields, owner details, arbitrary legacy fields, and private data are
 * intentionally absent. Pilot SQL ID/category restrictions remain a separate
 * integration decision for legacy Firestore IDs and categories.
 */
export function projectPublicEstablishment(id, data) {
  const name = data?.name ?? data?.title;
  if (!isFirestoreDocumentId(id) ||
    !validString(name, 100, { required: true }) || !CATEGORIES.has(data.category)) return null;
  const expiresAt = data.expiresAt == null ? null : new Date(data.expiresAt);
  if (expiresAt && !Number.isFinite(expiresAt.getTime())) return null;
  const deletedAt = data.deletedAt == null ? null : new Date(data.deletedAt);
  if (deletedAt && !Number.isFinite(deletedAt.getTime())) return null;
  const summary = typeof data.shortDescription === 'string'
    ? data.shortDescription
    : (typeof data.description === 'string' ? data.description : '');
  const subcategory = typeof data.subcategory === 'string' ? data.subcategory : '';
  if (!validString(summary, 3000) || !validString(subcategory, 120)) return null;
  const image = typeof data.imageUrl === 'string' ? data.imageUrl : '';
  if (image !== '' && !validHttpsUrl(image)) return null;
  return Object.freeze({
    id,
    name: name.trim(),
    summary: summary.slice(0, 500),
    category: data.category,
    subcategory: subcategory.slice(0, 80),
    image_url: image,
    published: data.published === undefined ? true : data.published === true,
    active: data.active === undefined ? true : data.active === true,
    expires_at: expiresAt?.toISOString() ?? null,
    deleted_at: deletedAt?.toISOString() ?? null,
  });
}

export const CATALOG_ROW_FIELDS_ALLOWLIST = CATALOG_ROW_FIELDS;

export function createAdminEstablishmentsHandler({
  projectId,
  verifyIdentity,
  authorizeAdmin,
  store,
  uuid = () => crypto.randomUUID(),
}) {
  if (projectId !== 'tudo-aqui-macacu' || typeof verifyIdentity !== 'function' ||
    typeof authorizeAdmin !== 'function' || typeof store?.runTransaction !== 'function' ||
    typeof uuid !== 'function') throw new TypeError('Invalid handler configuration.');

  return async function handle(request) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'POST, OPTIONS',
        'access-control-allow-headers': 'authorization, content-type, apikey, x-client-info',
      } });
    }
    if (request.method !== 'POST') return errorResponse('invalid_request');
    if (!/^application\/json(?:\s*;|$)/iu.test(request.headers.get('content-type') ?? '')) {
      return errorResponse('invalid_request');
    }

    let identity;
    try {
      const token = parseBearer(request);
      identity = await verifyIdentity(token, projectId);
      if (!identity || typeof identity.uid !== 'string' || !identity.uid ||
        typeof identity.provider !== 'string' || identity.provider.length === 0 || identity.provider.length > 128) {
        fail('unauthenticated');
      }
      if (identity.isAnonymous !== false || identity.provider === 'anonymous') fail('permission_denied');
    } catch (error) {
      return errorResponse(mapFailure(error) === 'internal' ? 'unauthenticated' : mapFailure(error));
    }

    let input;
    try {
      input = await parseRequest(request);
    } catch (error) {
      return errorResponse(mapFailure(error) === 'internal' ? 'invalid_request' : mapFailure(error));
    }

    try {
      const result = await store.runTransaction(async (transaction) => {
        await authorizeAdmin(identity, async (uid) => {
          if (uid !== identity.uid) return null;
          const record = await transaction.get('admin_authorizations', uid);
          return record?.data ?? null;
        });

        const existingOperation = await transaction.get('catalog_outbox', input.requestId);
        if (existingOperation) return replayResult(existingOperation.data, identity, input.requestId);

        if (input.operation === 'create') {
          const entityId = input.entityId ?? uuid();
            if (!isFirestoreDocumentId(entityId)) fail('internal');
          const source = sourceFields(input.data, { creating: true }).data;
          Object.assign(source, { catalogVersion: 1, outboxOperationId: input.requestId });
          transaction.create('establishments', entityId, source, {
            serverTimestampFields: ['createdAt', 'updatedAt'],
          });
          transaction.create('catalog_outbox', input.requestId,
            makeOutboxEvent({ operationId: input.requestId, entityId,
              authorUid: identity.uid, version: 1 }),
          { serverTimestampFields: ['createdAt', 'updatedAt'] });
          return { status: 201, result: 'created', operationId: input.requestId,
            entityId, version: 1, replayed: false };
        }

        const current = await transaction.get('establishments', input.entityId);
        if (!current) fail('conflict');
        const currentData = current.data ?? {};
        if (currentData.deletedAt != null) fail('conflict');
        const priorVersion = validStoredVersion(currentData);
        if (input.expectedVersion !== priorVersion) fail('conflict');
        const version = priorVersion + 1;
        if (version > MAX_VERSION) fail('conflict');
        let patch;
        let deleteFields = [];
        let serverTimestampFields = ['updatedAt'];
        if (input.operation === 'unpublish') {
          patch = { published: false, active: false };
        } else if (input.operation === 'republish') {
          if (currentData.published !== false) fail('conflict');
          const prepared = input.data
            ? sourceFields(input.data, { creating: false })
            : { data: {}, deleteFields: [] };
          patch = { ...prepared.data, published: true, active: true };
          deleteFields = prepared.deleteFields;
        } else if (input.operation === 'delete') {
          patch = { published: false, active: false };
          serverTimestampFields = ['updatedAt', 'deletedAt'];
        } else {
          if (currentData.published === false && input.data.published === true) fail('conflict');
          const prepared = sourceFields(input.data, { creating: false });
          patch = prepared.data;
          deleteFields = prepared.deleteFields;
        }
        Object.assign(patch, { catalogVersion: version, outboxOperationId: input.requestId });
        transaction.update('establishments', input.entityId, patch, {
          updateTime: current.updateTime,
          serverTimestampFields,
          deleteFields,
        });
        transaction.create('catalog_outbox', input.requestId,
          makeOutboxEvent({ operationId: input.requestId, entityId: input.entityId,
            authorUid: identity.uid, version }),
        { serverTimestampFields: ['createdAt', 'updatedAt'] });
        const result = input.operation === 'unpublish' ? 'unpublished' :
          input.operation === 'republish' ? 'republished' :
            input.operation === 'delete' ? 'deleted' : 'updated';
        return { status: 200, result,
          operationId: input.requestId, entityId: input.entityId, version, replayed: false };
      });
      return jsonResponse(result.status, { result: result.result, operationId: result.operationId,
        entityId: result.entityId, version: result.version, replayed: result.replayed });
    } catch (error) {
      const code = mapFailure(error);
      return errorResponse(code === 'internal' ? 'backend_unavailable' : code);
    }
  };
}
