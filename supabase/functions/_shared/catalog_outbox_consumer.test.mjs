import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import { createCatalogOutboxConsumerHandler } from './catalog_outbox_consumer.mjs';

const SECRET = 'synthetic-only-secret-material-at-least-32-bytes';
const NOW = Math.floor(Date.parse('2026-10-21T00:00:00.000Z') / 1_000);
function sign(secret = SECRET, timestamp = NOW) {
  const signature = createHmac('sha256', secret)
    .update(`catalog-outbox-consumer-v1\nPOST\n/consume\n${timestamp}`, 'utf8').digest('base64url');
  return `${timestamp}.${signature}`;
}

function request({ method = 'POST', signature = sign(), body, url = 'https://local.invalid/consume' } = {}) {
  return new Request(url, {
    method,
    headers: {
      ...(signature === null ? {} : { 'x-catalog-run-signature': signature }),
      ...(body === undefined ? {} : { 'content-type': 'application/json' }),
    },
    ...(body === undefined ? {} : { body }),
  });
}

test('consumer fails closed when disabled or machine secret is missing/too short', async () => {
  let calls = 0;
  for (const options of [
    { enabled: false, secret: SECRET },
    { enabled: true, secret: '' },
    { enabled: true, secret: 'short' },
  ]) {
    const handler = createCatalogOutboxConsumerHandler({
      ...options, processPage: async () => { calls += 1; return { results: [] }; },
      now: () => NOW * 1_000,
    });
    assert.equal((await handler(request())).status, 503);
  }
  assert.equal(calls, 0);
});

test('consumer rejects unauthenticated, malformed, queried, and non-POST requests before processing', async () => {
  let calls = 0;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, processPage: async () => { calls += 1; return { results: [] }; },
    now: () => NOW * 1_000,
  });
  assert.equal((await handler(request({ signature: null }))).status, 401);
  assert.equal((await handler(request({ signature: 'invalid' }))).status, 401);
  assert.equal((await handler(request({ signature: sign(SECRET, NOW - 120) }))).status, 401);
  assert.equal((await handler(request({ url: 'https://local.invalid/other' }))).status, 401);
  assert.equal((await handler(request({ method: 'GET' }))).status, 405);
  assert.equal((await handler(request({ body: '{"limit":1}' }))).status, 400);
  assert.equal((await handler(request({ url: 'https://local.invalid/consume?limit=100000' }))).status, 400);
  assert.equal(calls, 0);
});

test('consumer accepts only an empty JSON envelope for pg_net and rejects caller parameters', async () => {
  let calls = 0;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, now: () => NOW * 1_000,
    processPage: async () => { calls += 1; return { results: [] }; },
  });
  const accepted = await handler(request({ body: '{}' }));
  assert.equal(accepted.status, 200);
  assert.equal(calls, 1);
  const rejected = await handler(request({ body: '{"cursor":"attacker"}' }));
  assert.equal(rejected.status, 400);
  assert.equal(calls, 1);
});

test('consumer invokes exactly one bounded processor page and returns only sanitized counts', async () => {
  const calls = [];
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true,
    secret: SECRET,
    pageSize: 7,
    now: () => NOW * 1_000,
    processPage: async (input) => {
      calls.push(input);
      return { readTime: '2026-10-20T12:00:00.000Z', nextCursor: 'private-cursor', results: [
        { eventId: 'private-id-1', state: 'synced', write: 'applied' },
        { eventId: 'private-id-2', state: 'pending', reason: 'retry_scheduled' },
        { eventId: 'private-id-3', state: 'unsafe-state', errorCode: 'unsafe secret' },
      ] };
    },
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(calls, [{ limit: 7, cursor: null }]);
  const text = await response.text();
  assert.doesNotMatch(text, /private-id|private-cursor|unsafe secret/u);
  assert.deepEqual(JSON.parse(text), {
    ok: true, busy: false,
    processed: 3,
    states: { synced: 1, pending: 1, unavailable: 1 },
    scannedPages: 0, scannedDocuments: 0, eligible: 3, claimed: 0,
    hasMore: true,
  });
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('consumer returns a safe no-pending-events result without exposing event data', async () => {
  let calls = 0;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true,
    secret: SECRET,
    now: () => NOW * 1_000,
    processPage: async (input) => {
      calls += 1;
      assert.deepEqual(input, { limit: 25, cursor: null });
      return { readTime: '2026-10-20T12:00:00.000Z', nextCursor: null, results: [] };
    },
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.equal(calls, 1);
  assert.deepEqual(await response.json(), { ok: true, busy: false, processed: 0, states: {},
    scannedPages: 0, scannedDocuments: 0, eligible: 0, claimed: 0, hasMore: false });
});

test('consumer reports bounded scan counts separately from eligible and claimed events', async () => {
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, now: () => NOW * 1_000,
    processPage: async () => ({ results: [{ state: 'synced' }], nextCursor: 'opaque',
      scannedPages: 4, scannedDocuments: 100, eligibleCount: 2, claimedCount: 1 }),
  });
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, busy: false, processed: 1, states: { synced: 1 },
    scannedPages: 4, scannedDocuments: 100, eligible: 2, claimed: 1, hasMore: true });
});

test('consumer reports a globally leased scan as busy without claiming or advancing work', async () => {
  let calls = 0;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, now: () => NOW * 1_000,
    processPage: async () => { calls += 1; return { busy: true, results: [], scannedPages: 0,
      scannedDocuments: 0, eligibleCount: 0, claimedCount: 0, nextCursor: null, readTime: null }; },
  });
  const response = await handler(request());
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: 'run_in_progress' });
  assert.equal(calls, 1);
});

test('consumer rejects impossible result pages instead of producing a partial success', async () => {
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, now: () => NOW * 1_000,
    processPage: async () => ({ results: Array.from({ length: 26 }, () => ({ state: 'synced' })) }),
  });
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: 'consumer_unavailable' });
});

test('consumer rejects overlapping requests in one isolate and releases the guard afterward', async () => {
  let release;
  let calls = 0;
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true,
    secret: SECRET,
    now: () => NOW * 1_000,
    processPage: async () => {
      calls += 1;
      if (calls === 1) await new Promise((resolve) => { release = resolve; });
      return { results: [] };
    },
  });
  const first = handler(request());
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal((await handler(request())).status, 409);
  release();
  assert.equal((await first).status, 200);
  assert.equal((await handler(request())).status, 200);
  assert.equal(calls, 2);
});

test('consumer sanitizes processor errors and does not leak exception data', async () => {
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET,
    now: () => NOW * 1_000,
    processPage: async () => { throw new Error('sensitive-project-path-and-token'); },
  });
  const response = await handler(request());
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /sensitive|token|path/u);
});

test('consumer emits only aggregate run metrics and samples authentication failures', async () => {
  let clock = NOW * 1_000;
  const metrics = [];
  const handler = createCatalogOutboxConsumerHandler({
    enabled: true, secret: SECRET, now: () => clock,
    onMetric: (metric) => metrics.push(metric),
    processPage: async () => ({
      nextCursor: 'private-cursor',
      results: [
        { eventId: 'private-event-id', state: 'synced' },
        { eventId: 'private-event-id-2', state: 'pending', errorCode: 'catalog_unavailable' },
      ],
    }),
  });

  assert.equal((await handler(request({ signature: 'invalid' }))).status, 401);
  clock += 1_000;
  assert.equal((await handler(request({ signature: 'invalid' }))).status, 401);
  assert.equal(metrics.length, 1, 'repeated auth failures are rate-limited per isolate');
  assert.deepEqual(metrics[0], { event: 'catalog_outbox_auth_failure_sampled' });

  clock += 1_000;
  const response = await handler(request());
  assert.equal(response.status, 200);
  assert.deepEqual(metrics[1], {
    event: 'catalog_outbox_run', outcome: 'completed', durationMs: 0,
    processed: 2, scannedPages: 0, scannedDocuments: 0, eligible: 2, claimed: 0,
    states: { synced: 1, pending: 1 }, hasMore: true,
  });
  assert.doesNotMatch(JSON.stringify(metrics), /private-event|private-cursor|secret/iu);
});
