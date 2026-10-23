const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const RPC_ARGUMENTS = Object.freeze({
  begin_catalog_reconciliation_snapshot_v2: ['p_snapshot_id'],
  read_catalog_reconciliation_page_v2: ['p_snapshot_id', 'p_after_id', 'p_page_size'],
  dispose_catalog_reconciliation_snapshot_v2: ['p_snapshot_id'],
});
const PROJECTION_FIELDS = Object.freeze([
  'id', 'content_kind', 'category_group', 'name', 'summary', 'category', 'subcategory',
  'location', 'artwork', 'image_url', 'logo_url', 'gallery_urls', 'featured', 'is_open',
  'maps_url', 'hours', 'services', 'products', 'additional_info', 'promotion_title',
  'promotion_description', 'public_contact_approved', 'phone', 'whatsapp', 'instagram',
  'published', 'active', 'expires_at', 'deleted_at', 'catalog_version', 'outbox_operation_id',
]);
const TOMBSTONE_FIELDS = Object.freeze(['id', 'catalog_version', 'outbox_operation_id', 'tombstoned_at']);
const MAX_RESPONSE_BYTES = 4 * 1024 * 1024;

export class SupabaseCatalogReconciliationRpcError extends Error {
  constructor(code = 'catalog_unavailable') {
    const safeCode = ['catalog_unavailable', 'invalid_snapshot', 'snapshot_expired'].includes(code)
      ? code : 'catalog_unavailable';
    super(safeCode === 'invalid_snapshot' ? 'Reconciliation snapshot request is invalid.' :
      safeCode === 'snapshot_expired' ? 'Reconciliation snapshot expired.' : 'Catalog is unavailable.');
    this.name = 'SupabaseCatalogReconciliationRpcError';
    this.code = safeCode;
  }
}

/**
 * Server-only PostgREST client for the private, read-only reconciliation snapshot RPCs.
 * It has a separate closed allowlist from the catalog writer and exposes no table API.
 */
export function createSupabaseCatalogReconciliationRpcClient({
  url,
  apiKey,
  restPathPrefix = '/rest/v1',
  fetchImpl = fetch,
  timeoutMs = 10_000,
  maxResponseBytes = MAX_RESPONSE_BYTES,
}) {
  const origin = validBaseUrl(url);
  if (!origin || typeof apiKey !== 'string' || apiKey.length < 32 || apiKey.length > 8192 ||
    !['', '/rest/v1'].includes(restPathPrefix) || typeof fetchImpl !== 'function' ||
    !Number.isSafeInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30_000 ||
    !Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1024 || maxResponseBytes > MAX_RESPONSE_BYTES) {
    throw new SupabaseCatalogReconciliationRpcError();
  }

  async function rpc(name, args) {
    if (!Object.hasOwn(RPC_ARGUMENTS, name) || !plainObject(args) ||
      !sameKeys(args, RPC_ARGUMENTS[name]) || !validArguments(name, args)) {
      throw new SupabaseCatalogReconciliationRpcError('invalid_snapshot');
    }
    let response;
    try {
      response = await fetchImpl(`${origin}${restPathPrefix}/rpc/${name}`, {
        method: 'POST',
        headers: {
          apikey: apiKey,
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      throw new SupabaseCatalogReconciliationRpcError();
    }
    const body = await readJsonLimited(response, maxResponseBytes);
    if (!response.ok) throw errorFromStatus(response.status, body);
    if (body === null || !validResult(name, body, args)) {
      throw new SupabaseCatalogReconciliationRpcError();
    }
    return body;
  }

  return Object.freeze({
    rpc,
    beginSnapshot(snapshotId) {
      return rpc('begin_catalog_reconciliation_snapshot_v2', { p_snapshot_id: snapshotId });
    },
    readPage({ snapshotId, afterId = null, limit = 100 }) {
      return rpc('read_catalog_reconciliation_page_v2', {
        p_snapshot_id: snapshotId, p_after_id: afterId, p_page_size: limit,
      });
    },
    disposeSnapshot(snapshotId) {
      return rpc('dispose_catalog_reconciliation_snapshot_v2', { p_snapshot_id: snapshotId });
    },
  });
}

function validArguments(name, args) {
  if (!UUID_PATTERN.test(args.p_snapshot_id)) return false;
  if (name === 'begin_catalog_reconciliation_snapshot_v2' ||
    name === 'dispose_catalog_reconciliation_snapshot_v2') return true;
  return (args.p_after_id === null || validDocumentId(args.p_after_id)) &&
    Number.isSafeInteger(args.p_page_size) && args.p_page_size >= 1 && args.p_page_size <= 200;
}

function validResult(name, value, args) {
  if (name === 'begin_catalog_reconciliation_snapshot_v2') {
    return plainObject(value) && sameKeys(value, [
      'snapshot_id', 'captured_at', 'expires_at', 'entity_count', 'payload_bytes', 'replayed',
    ]) && value.snapshot_id === args.p_snapshot_id && validTimestamp(value.captured_at) &&
      validTimestamp(value.expires_at) && Date.parse(value.expires_at) > Date.parse(value.captured_at) &&
      Number.isSafeInteger(value.entity_count) && value.entity_count >= 0 && value.entity_count <= 10_000 &&
      Number.isSafeInteger(value.payload_bytes) && value.payload_bytes >= 0 && value.payload_bytes <= 67_108_864 &&
      typeof value.replayed === 'boolean';
  }
  if (name === 'dispose_catalog_reconciliation_snapshot_v2') return typeof value === 'boolean';
  if (!plainObject(value) || !sameKeys(value, [
    'snapshot_id', 'captured_at', 'expires_at', 'next_cursor', 'done', 'catalog_rows', 'tombstones',
  ]) || value.snapshot_id !== args.p_snapshot_id || !validTimestamp(value.captured_at) ||
    !validTimestamp(value.expires_at) || Date.parse(value.expires_at) <= Date.parse(value.captured_at) ||
    (value.next_cursor !== null && !validDocumentId(value.next_cursor)) || typeof value.done !== 'boolean' ||
    !Array.isArray(value.catalog_rows) || !Array.isArray(value.tombstones) ||
    value.catalog_rows.length > args.p_page_size || value.tombstones.length > args.p_page_size) return false;

  if (!value.catalog_rows.every(validProjectionRow) || !value.tombstones.every(validTombstone)) return false;
  const ids = [...value.catalog_rows.map((row) => row.id), ...value.tombstones.map((row) => row.id)];
  const unique = [...new Set(ids)].sort(compareCodePoints);
  if (unique.length > args.p_page_size || ids.length !== new Set(ids).size +
    value.catalog_rows.filter((row) => value.tombstones.some((tombstone) => tombstone.id === row.id)).length) return false;
  if (unique.some((id, index) => index > 0 && compareCodePoints(unique[index - 1], id) >= 0)) return false;
  if (args.p_after_id !== null && unique.some((id) => compareCodePoints(id, args.p_after_id) <= 0)) return false;
  const expectedCursor = unique.at(-1) ?? args.p_after_id;
  if (value.next_cursor !== expectedCursor || (!value.done && unique.length !== args.p_page_size)) return false;
  if (!isSorted(value.catalog_rows.map((row) => row.id)) || !isSorted(value.tombstones.map((row) => row.id))) return false;
  return true;
}

function validProjectionRow(row) {
  if (!plainObject(row) || !sameKeys(row, PROJECTION_FIELDS) || !validDocumentId(row.id) ||
    row.content_kind !== 'establishment' || !['commerce', 'services'].includes(row.category_group) ||
    !['name', 'summary', 'category', 'subcategory', 'image_url', 'logo_url', 'maps_url', 'hours',
      'additional_info', 'promotion_title', 'promotion_description'].every((key) => typeof row[key] === 'string') ||
    (row.location !== null && typeof row.location !== 'string') ||
    !Number.isSafeInteger(row.artwork) || row.artwork < 0 || row.artwork > 18 ||
    !['gallery_urls', 'services', 'products'].every((key) => Array.isArray(row[key]) && row[key].every((item) => typeof item === 'string')) ||
    !['featured', 'is_open', 'public_contact_approved', 'published', 'active'].every((key) => typeof row[key] === 'boolean') ||
    !['phone', 'whatsapp', 'instagram'].every((key) => row[key] === null || typeof row[key] === 'string') ||
    (!row.public_contact_approved && [row.phone, row.whatsapp, row.instagram].some((value) => value !== null)) ||
    !validNullableTimestamp(row.expires_at) || !validNullableTimestamp(row.deleted_at) ||
    !Number.isSafeInteger(row.catalog_version) || row.catalog_version < 1 ||
    typeof row.outbox_operation_id !== 'string' || !UUID_PATTERN.test(row.outbox_operation_id)) return false;
  return true;
}

function validTombstone(value) {
  return plainObject(value) && sameKeys(value, TOMBSTONE_FIELDS) && validDocumentId(value.id) &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === 'string' && UUID_PATTERN.test(value.outbox_operation_id) &&
    validTimestamp(value.tombstoned_at);
}

function errorFromStatus(status, body) {
  const sqlState = typeof body?.code === 'string' ? body.code : '';
  if (sqlState === '55000' || status === 410) return new SupabaseCatalogReconciliationRpcError('snapshot_expired');
  if (sqlState === '22023' || status === 400 || status === 422) {
    return new SupabaseCatalogReconciliationRpcError('invalid_snapshot');
  }
  return new SupabaseCatalogReconciliationRpcError();
}

async function readJsonLimited(response, maximumBytes) {
  if (!response.body) return null;
  const reader = response.body.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > maximumBytes) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

function validBaseUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value);
    const loopback = ['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname);
    if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) || url.username ||
      url.password || url.search || url.hash || url.pathname !== '/') return null;
    return url.origin;
  } catch {
    return null;
  }
}

function validDocumentId(value) {
  return typeof value === 'string' && new TextEncoder().encode(value).byteLength > 0 &&
    new TextEncoder().encode(value).byteLength <= 1500 && value !== '.' && value !== '..' &&
    !value.includes('/') && (!value.startsWith('__') || !value.endsWith('__') || /^__id\d+__$/u.test(value));
}

function validTimestamp(value) {
  return typeof value === 'string' && Number.isFinite(Date.parse(value));
}

function validNullableTimestamp(value) {
  return value === null || validTimestamp(value);
}

function sameKeys(value, expected) {
  const actual = Object.keys(value);
  return actual.length === expected.length && expected.every((key) => Object.hasOwn(value, key));
}

function isSorted(values) {
  return values.every((value, index) => index === 0 || compareCodePoints(values[index - 1], value) < 0);
}

function compareCodePoints(left, right) {
  const a = Array.from(left, (character) => character.codePointAt(0));
  const b = Array.from(right, (character) => character.codePointAt(0));
  for (let index = 0; index < Math.min(a.length, b.length); index += 1) {
    if (a[index] !== b[index]) return a[index] - b[index];
  }
  return a.length - b.length;
}

function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}
