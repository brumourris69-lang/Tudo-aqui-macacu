const SIGNATURE_HEADER = 'x-catalog-run-signature';
const SIGNATURE_PATTERN = /^(\d{10})\.([A-Za-z0-9_-]{43})$/u;
const MIN_SECRET_BYTES = 32;
const MAX_SECRET_BYTES = 256;
const MAX_PAGE_SIZE = 25;
const SIGNATURE_WINDOW_MS = 90_000;
const AUTH_FAILURE_METRIC_WINDOW_MS = 10_000;
const OUTCOMES = new Set([
  'synced', 'superseded', 'dead_letter', 'pending', 'lease_lost', 'ack_pending',
  'state_unconfirmed', 'not_processed', 'unavailable',
]);

function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });
}

function decodeBase64Url(value) {
  try {
    const base64 = value.replaceAll('-', '+').replaceAll('_', '/') + '='.repeat((4 - value.length % 4) % 4);
    return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

async function hasValidMachineSignature(request, keyPromise, now, pathname) {
  const match = SIGNATURE_PATTERN.exec(request.headers.get(SIGNATURE_HEADER) ?? '');
  if (!match) return false;
  const timestamp = Number(match[1]) * 1_000;
  const currentTime = now();
  if (!Number.isSafeInteger(timestamp) || !Number.isSafeInteger(currentTime) ||
    Math.abs(currentTime - timestamp) > SIGNATURE_WINDOW_MS) return false;
  const bytes = decodeBase64Url(match[2]);
  if (!bytes || bytes.byteLength !== 32) return false;
  try {
    const message = new TextEncoder().encode(`catalog-outbox-consumer-v1\nPOST\n${pathname}\n${match[1]}`);
    return await crypto.subtle.verify('HMAC', await keyPromise, bytes, message);
  } catch {
    return false;
  }
}

async function hasEmptyOrCronEnvelope(request) {
  const declaredLength = request.headers.get('content-length');
  if (declaredLength !== null && !['0', '2'].includes(declaredLength)) return false;
  if (!request.body) return declaredLength === null || declaredLength === '0';
  if (declaredLength === '0' ||
    !/^application\/json(?:\s*;\s*charset=utf-8)?$/iu.test(request.headers.get('content-type') ?? '')) {
    return false;
  }
  const reader = request.body.getReader();
  const chunks = [];
  let byteLength = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value?.byteLength) {
        byteLength += value.byteLength;
        if (byteLength > 2) {
          await reader.cancel();
          return false;
        }
        chunks.push(value);
      }
    }
    if (byteLength !== 2 || (declaredLength !== null && declaredLength !== '2')) return false;
    const bytes = new Uint8Array(2);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    try {
      return new TextDecoder('utf-8', { fatal: true }).decode(bytes) === '{}';
    } catch {
      return false;
    }
  } catch {
    return false;
  } finally {
    reader.releaseLock();
  }
}

function summarize(result) {
  if (!result || !Array.isArray(result.results) || result.results.length > MAX_PAGE_SIZE) {
    throw new TypeError('Invalid processor result.');
  }
  if (result.busy === true) return { busy: true };
  const scannedPages = metricCount(result.scannedPages, 0, 20);
  const scannedDocuments = metricCount(result.scannedDocuments, 0, 100);
  const eligible = metricCount(result.eligibleCount, result.results.length, 100);
  const claimed = metricCount(result.claimedCount, 0, MAX_PAGE_SIZE);
  if (claimed > eligible || eligible < result.results.length) throw new TypeError('Invalid processor counts.');
  const states = Object.create(null);
  for (const item of result.results) {
    const state = OUTCOMES.has(item?.state) ? item.state : 'unavailable';
    states[state] = (states[state] ?? 0) + 1;
  }
  return {
    ok: true,
    busy: false,
    processed: result.results.length,
    states,
    scannedPages,
    scannedDocuments,
    eligible,
    claimed,
    hasMore: result.nextCursor !== null && result.nextCursor !== undefined,
  };
}

function metricCount(value, fallback, maximum) {
  if (value === undefined) return fallback;
  if (!Number.isSafeInteger(value) || value < 0 || value > maximum) throw new TypeError('Invalid processor counts.');
  return value;
}

function emitMetric(onMetric, metric) {
  try { onMetric(Object.freeze(metric)); } catch { /* Metrics must never affect processing. */ }
}

function safeDurationMs(now, startedAt) {
  try {
    const endedAt = now();
    return Number.isSafeInteger(endedAt) ? Math.max(0, Math.min(600_000, endedAt - startedAt)) : 0;
  } catch {
    return 0;
  }
}

/**
 * Creates a private, one-page trigger for a scheduled trusted caller.
 * The signature is HMAC-SHA-256 over a fixed versioned challenge and is
 * verified with WebCrypto; it is never logged or returned. The only accepted
 * body is absent or the empty JSON object used by pg_net defaults. The body
 * cannot choose page size, cursor, or filters. Firestore lease transactions
 * remain the cross-instance concurrency control.
 * @param {{processPage: (request: {limit: number, cursor: null}) => Promise<Record<string, unknown>> | Record<string, unknown>, secret: string, enabled?: boolean, pageSize?: number, now?: () => number, onMetric?: (metric: Readonly<Record<string, unknown>>) => void}} options
 */
export function createCatalogOutboxConsumerHandler({
  processPage,
  secret,
  enabled = false,
  pageSize = 25,
  now = Date.now,
  onMetric = () => {},
}) {
  const secretBytes = typeof secret === 'string' ? new TextEncoder().encode(secret) : new Uint8Array();
  if (typeof processPage !== 'function' || typeof enabled !== 'boolean' ||
    !Number.isSafeInteger(pageSize) || pageSize < 1 || pageSize > MAX_PAGE_SIZE ||
    typeof now !== 'function' || typeof onMetric !== 'function') {
    throw new TypeError('Invalid consumer configuration.');
  }
  const configured = enabled && secretBytes.byteLength >= MIN_SECRET_BYTES &&
    secretBytes.byteLength <= MAX_SECRET_BYTES;
  const keyPromise = configured
    ? crypto.subtle.importKey('raw', secretBytes, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify'])
    : null;
  let running = false;
  let lastAuthFailureMetricAt = Number.MIN_SAFE_INTEGER;

  return async function handle(request) {
    if (request.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    if (!configured || !keyPromise) return json(503, { error: 'consumer_unavailable' });
    let url;
    try { url = new URL(request.url); } catch { return json(400, { error: 'invalid_request' }); }
    if (url.search || url.hash || url.username || url.password ||
      !(await hasEmptyOrCronEnvelope(request))) return json(400, { error: 'invalid_request' });
    if (!(await hasValidMachineSignature(request, keyPromise, now, url.pathname))) {
      const rejectedAt = now();
      if (Number.isSafeInteger(rejectedAt) &&
        rejectedAt - lastAuthFailureMetricAt >= AUTH_FAILURE_METRIC_WINDOW_MS) {
        lastAuthFailureMetricAt = rejectedAt;
        emitMetric(onMetric, { event: 'catalog_outbox_auth_failure_sampled' });
      }
      return json(401, { error: 'unauthorized' });
    }
    if (running) {
      emitMetric(onMetric, { event: 'catalog_outbox_overlap_rejected' });
      return json(409, { error: 'run_in_progress' });
    }
    running = true;
    const startedAt = now();
    try {
      const result = await processPage({ limit: pageSize, cursor: null });
      const summary = summarize(result);
      if (summary.busy) {
        emitMetric(onMetric, { event: 'catalog_outbox_overlap_rejected' });
        return json(409, { error: 'run_in_progress' });
      }
      emitMetric(onMetric, {
        event: 'catalog_outbox_run',
        outcome: 'completed',
        durationMs: safeDurationMs(now, startedAt),
        processed: summary.processed,
        scannedPages: summary.scannedPages,
        scannedDocuments: summary.scannedDocuments,
        eligible: summary.eligible,
        claimed: summary.claimed,
        states: { ...summary.states },
        hasMore: summary.hasMore,
      });
      return json(200, summary);
    } catch {
      emitMetric(onMetric, {
        event: 'catalog_outbox_run',
        outcome: 'failed',
        durationMs: safeDurationMs(now, startedAt),
        processed: 0,
      });
      return json(503, { error: 'consumer_unavailable' });
    } finally {
      running = false;
    }
  };
}
