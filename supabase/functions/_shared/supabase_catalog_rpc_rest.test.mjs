import assert from 'node:assert/strict';
import test from 'node:test';
import { createSupabaseCatalogRpcRestClient, SupabaseCatalogRpcError } from './supabase_catalog_rpc_rest.mjs';

const key = 'synthetic-server-key-for-local-unit-tests-123456';
const projection = { id: 'synthetic-id', catalog_version: 1 };

test('PostgREST adapter sends only allowlisted private RPC and returns its JSON value', async () => {
  const calls = [];
  const rpc = createSupabaseCatalogRpcRestClient({
    url: 'http://127.0.0.1:54321', apiKey: key,
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return Response.json('applied');
    },
  });
  assert.deepEqual(await rpc('apply_establishment_projection_v2', { p_projection: projection }), {
    data: 'applied',
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'http://127.0.0.1:54321/rest/v1/rpc/apply_establishment_projection_v2');
  assert.equal(calls[0].init.method, 'POST');
  assert.equal(calls[0].init.headers.apikey, key);
  assert.equal(calls[0].init.headers.authorization, `Bearer ${key}`);
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_projection: projection });
});

test('PostgREST adapter supports only the root RPC path for standalone local PostgREST', async () => {
  const calls = [];
  const rpc = createSupabaseCatalogRpcRestClient({
    url: 'http://127.0.0.1:25432', apiKey: key, restPathPrefix: '',
    fetchImpl: async (url) => { calls.push(url); return Response.json('applied'); },
  });
  assert.deepEqual(await rpc('apply_establishment_projection_v2', { p_projection: projection }), { data: 'applied' });
  assert.equal(calls[0], 'http://127.0.0.1:25432/rpc/apply_establishment_projection_v2');
  assert.throws(() => createSupabaseCatalogRpcRestClient({
    url: 'http://127.0.0.1:25432', apiKey: key, restPathPrefix: '/arbitrary',
  }), SupabaseCatalogRpcError);
});

test('PostgREST adapter maps only known SQL error codes and never exposes response messages', async () => {
  const rpc = createSupabaseCatalogRpcRestClient({
    url: 'https://synthetic.supabase.co', apiKey: key,
    fetchImpl: async () => Response.json({ code: '23514', message: 'private payload and token' }, { status: 400 }),
  });
  await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection }), (error) => {
    assert.ok(error instanceof SupabaseCatalogRpcError);
    assert.equal(error.code, 'catalog_conflict');
    assert.doesNotMatch(error.message, /private|token/u);
    return true;
  });
});

test('PostgREST adapter maps validation errors to permanent failures and network errors to unavailable', async () => {
  const badInputRpc = createSupabaseCatalogRpcRestClient({
    url: 'https://synthetic.supabase.co', apiKey: key,
    fetchImpl: async () => Response.json({ code: '22023', message: 'do not forward' }, { status: 400 }),
  });
  await assert.rejects(badInputRpc('apply_establishment_projection_v2', { p_projection: projection }),
    (error) => error.code === 'permanent_failure' && !error.message.includes('forward'));
  const failedRpc = createSupabaseCatalogRpcRestClient({
    url: 'https://synthetic.supabase.co', apiKey: key,
    fetchImpl: async () => { throw new Error('private url / credential'); },
  });
  await assert.rejects(failedRpc('apply_establishment_projection_v2', { p_projection: projection }),
    (error) => error.code === 'catalog_unavailable' && !error.message.includes('credential'));
});

test('PostgREST adapter rejects non-loopback HTTP, credentials in URLs, arbitrary RPC names and arguments', async () => {
  for (const url of ['http://198.51.100.2', 'https://user:pass@synthetic.supabase.co',
    'https://synthetic.supabase.co/path']) {
    assert.throws(() => createSupabaseCatalogRpcRestClient({ url, apiKey: key }), SupabaseCatalogRpcError);
  }
  let calls = 0;
  const rpc = createSupabaseCatalogRpcRestClient({
    url: 'https://synthetic.supabase.co', apiKey: key,
    fetchImpl: async () => { calls += 1; return Response.json('applied'); },
  });
  await assert.rejects(rpc('arbitrary_sql', { query: 'select 1' }),
    (error) => error.code === 'permanent_failure');
  await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection, extra: true }),
    (error) => error.code === 'permanent_failure');
  assert.equal(calls, 0);
});

test('PostgREST adapter bounds response bodies and rejects malformed success responses', async () => {
  const rpc = createSupabaseCatalogRpcRestClient({
    url: 'https://synthetic.supabase.co', apiKey: key,
    fetchImpl: async () => new Response('not-json'),
  });
  await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection }),
    (error) => error.code === 'catalog_unavailable');
});
