const RPC_NAMES = new Set([
  'apply_establishment_projection_v2',
  'apply_establishment_tombstone_v2',
]);
const MAX_RESPONSE_BYTES = 16 * 1024;

export class SupabaseCatalogRpcError extends Error {
  constructor(code = 'catalog_unavailable') {
    const safeCode = ['catalog_unavailable', 'catalog_conflict', 'permanent_failure'].includes(code)
      ? code : 'catalog_unavailable';
    super(safeCode === 'catalog_conflict' ? 'Catalog operation conflicts with persisted state.' :
      safeCode === 'permanent_failure' ? 'Catalog rejected the projection.' : 'Catalog is unavailable.');
    this.name = 'SupabaseCatalogRpcError';
    this.code = safeCode;
  }
}

function validBaseUrl(value) {
  if (typeof value !== 'string' || value.length > 2048) return null;
  try {
    const url = new URL(value);
    const loopback = ['127.0.0.1', '[::1]', 'localhost'].includes(url.hostname);
    if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) ||
      url.username || url.password || url.search || url.hash || url.pathname !== '/') return null;
    return url.origin;
  } catch {
    return null;
  }
}

async function readJsonLimited(response) {
  if (!response.body) return null;
  const reader = response.body.getReader();
  let total = 0;
  const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      total += value.byteLength;
      if (total > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(value);
    }
    const bytes = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    return null;
  } finally {
    reader.releaseLock();
  }
}

function errorFromStatus(status, body) {
  const sqlState = typeof body?.code === 'string' ? body.code : '';
  if (sqlState === '23514' || status === 409) return new SupabaseCatalogRpcError('catalog_conflict');
  if (sqlState === '22023' || status === 400 || status === 422) {
    return new SupabaseCatalogRpcError('permanent_failure');
  }
  return new SupabaseCatalogRpcError('catalog_unavailable');
}

/**
 * Server-only PostgREST RPC transport. The credential is captured by the
 * trusted runtime only; this adapter accepts two fixed RPC names and never
 * forwards raw upstream error bodies or messages to the writer/logs.
 */
export function createSupabaseCatalogRpcRestClient({
  url,
  apiKey,
  restPathPrefix = '/rest/v1',
  fetchImpl = fetch,
  timeoutMs = 10_000,
}) {
  const origin = validBaseUrl(url);
  if (!origin || typeof apiKey !== 'string' || apiKey.length < 32 || apiKey.length > 8192 ||
    !['', '/rest/v1'].includes(restPathPrefix) ||
    typeof fetchImpl !== 'function' || !Number.isSafeInteger(timeoutMs) || timeoutMs < 100 || timeoutMs > 30_000) {
    throw new SupabaseCatalogRpcError();
  }

  return async function rpc(name, args) {
    if (!RPC_NAMES.has(name) || !args || typeof args !== 'object' || Array.isArray(args) ||
      Object.keys(args).length !== 1 || !Object.hasOwn(args, name === 'apply_establishment_projection_v2'
        ? 'p_projection' : 'p_tombstone')) {
      throw new SupabaseCatalogRpcError('permanent_failure');
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
      throw new SupabaseCatalogRpcError();
    }
    const body = await readJsonLimited(response);
    if (!response.ok) throw errorFromStatus(response.status, body);
    if (body === null) throw new SupabaseCatalogRpcError();
    return { data: body };
  };
}
