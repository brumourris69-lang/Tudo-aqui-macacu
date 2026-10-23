const PROJECTION_FIELDS = Object.freeze([
  'id', 'content_kind', 'category_group', 'name', 'summary', 'category', 'subcategory',
  'location', 'artwork', 'image_url', 'logo_url', 'gallery_urls', 'featured', 'is_open',
  'maps_url', 'hours', 'services', 'products', 'additional_info', 'promotion_title',
  'promotion_description', 'public_contact_approved', 'phone', 'whatsapp', 'instagram',
  'published', 'active', 'expires_at', 'deleted_at', 'catalog_version', 'outbox_operation_id',
]);
const TOMBSTONE_FIELDS = Object.freeze(['id', 'catalog_version', 'outbox_operation_id', 'deleted_at']);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

/**
 * Server-only adapter for the two private SQL V2 RPCs. `rpc` must be supplied
 * by a trusted server client; this module never stores or logs credentials.
 * @param {{rpc: (name: string, args: Record<string, unknown>) => Promise<unknown>}} options
 */
export function createSupabaseCatalogWriterV2({ rpc }) {
  if (typeof rpc !== 'function') throw new TypeError('A trusted Supabase RPC adapter is required.');

  async function call(name, argument, payload) {
    let response;
    try {
      response = await rpc(name, { [argument]: structuredClone(payload) });
    } catch (error) {
      const safeError = safeRpcError(error);
      if (safeError.code === 'catalog_conflict') return Object.freeze({ result: 'conflict' });
      throw safeError;
    }
    const rpcError = response && typeof response === 'object' ? response.error : null;
    if (rpcError) {
      const error = safeRpcError(rpcError);
      if (error.code === 'catalog_conflict') return Object.freeze({ result: 'conflict' });
      throw error;
    }
    const value = response && typeof response === 'object' && Object.hasOwn(response, 'data')
      ? response.data : response;
    if (value === 'applied') return Object.freeze({ result: 'applied' });
    if (value === 'replayed') return Object.freeze({ result: 'duplicate' });
    return Object.freeze({ result: 'invalid' });
  }

  return Object.freeze({
    async applyProjection(projection) {
      if (!validProjection(projection)) throw new CatalogWriterV2Error('invalid_projection');
      return call('apply_establishment_projection_v2', 'p_projection', projection);
    },
    async applyTombstone(tombstone) {
      if (!validTombstone(tombstone)) throw new CatalogWriterV2Error('invalid_projection');
      return call('apply_establishment_tombstone_v2', 'p_tombstone', tombstone);
    },
  });
}

export class CatalogWriterV2Error extends Error {
  constructor(code) {
    const safeCode = ['invalid_projection', 'catalog_conflict', 'permanent_failure', 'catalog_unavailable'].includes(code)
      ? code : 'catalog_unavailable';
    super(safeCode === 'invalid_projection' ? 'Catalog projection is invalid.' :
      safeCode === 'catalog_conflict' ? 'Catalog operation conflicts with persisted state.' :
      safeCode === 'permanent_failure' ? 'Catalog rejected the projection.' : 'Catalog is unavailable.');
    this.name = 'CatalogWriterV2Error';
    this.code = safeCode;
    if (safeCode === 'permanent_failure') this.permanent = true;
  }
}

function validProjection(value) {
  if (!plainObject(value) || !exactKeys(value, PROJECTION_FIELDS) || value.deleted_at !== null ||
    typeof value.id !== 'string' || value.id.length === 0 || value.content_kind !== 'establishment' ||
    !Number.isSafeInteger(value.catalog_version) || value.catalog_version < 1 ||
    typeof value.outbox_operation_id !== 'string' || !UUID_PATTERN.test(value.outbox_operation_id)) return false;
  return true;
}

function validTombstone(value) {
  return plainObject(value) && exactKeys(value, TOMBSTONE_FIELDS) &&
    typeof value.id === 'string' && value.id.length > 0 &&
    Number.isSafeInteger(value.catalog_version) && value.catalog_version > 0 &&
    typeof value.outbox_operation_id === 'string' && UUID_PATTERN.test(value.outbox_operation_id) &&
    typeof value.deleted_at === 'string' && Number.isFinite(Date.parse(value.deleted_at));
}

function exactKeys(value, fields) {
  const keys = Object.keys(value);
  return keys.length === fields.length && fields.every((field) => Object.hasOwn(value, field));
}

function plainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    (Object.getPrototypeOf(value) === Object.prototype || Object.getPrototypeOf(value) === null);
}

function safeRpcError(error) {
  const code = typeof error?.code === 'string' ? error.code : '';
  if (code === 'catalog_conflict') return new CatalogWriterV2Error('catalog_conflict');
  if (code === 'permanent_failure') return new CatalogWriterV2Error('permanent_failure');
  if (code === '23514') return new CatalogWriterV2Error('catalog_conflict');
  if (code === '22023') return new CatalogWriterV2Error('permanent_failure');
  return new CatalogWriterV2Error('catalog_unavailable');
}
