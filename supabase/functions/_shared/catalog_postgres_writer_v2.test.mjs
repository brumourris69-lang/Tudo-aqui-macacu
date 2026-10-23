import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import {
  createSupabaseCatalogPostgresRpcClient,
  SupabaseCatalogPostgresError,
} from './catalog_postgres_writer_v2.mjs';

const migrationUrl = new URL('../../migrations/20261024000100_restrict_catalog_writer_v2.sql', import.meta.url);
const grantTestsUrl = new URL('../../tests/database/catalog_writer_role_v2.sql', import.meta.url);
const projection = { id: 'modelo-synthetic', catalog_version: 1, outbox_operation_id: '71000000-0000-4000-8000-000000000001' };

test('writer preparation preserves service_role and provisions a restricted LOGIN membership', async () => {
  const sql = await readFile(migrationUrl, 'utf8');
  const grants = await readFile(grantTestsUrl, 'utf8');
  assert.match(sql, /create role catalog_writer_v2\s+nologin\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noinherit\s+noreplication\s+nobypassrls/i);
  assert.match(sql, /create role catalog_writer_v2_owner\s+nologin\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noinherit\s+noreplication\s+nobypassrls/i);
  assert.match(sql, /create role catalog_writer_v2_login\s+login\s+inherit\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noreplication\s+nobypassrls/i);
  assert.match(sql, /catalog_writer_v2_login[\s\S]*?connection limit 2 password null/i);
  assert.match(sql, /grant catalog_writer_v2 to catalog_writer_v2_login/i);
  assert.match(sql, /grant select, insert, update on table public\.public_establishment_catalog_v2\s+to catalog_writer_v2_owner/i);
  assert.match(sql, /grant select, insert on table public\.catalog_tombstones_v2\s+to catalog_writer_v2_owner/i);
  assert.doesNotMatch(sql, /grant\s+(?:all|delete|truncate|references|trigger)\s+on\s+table/i);
  assert.match(sql, /alter function public\.apply_establishment_projection_v2\(jsonb\)\s+owner to catalog_writer_v2_owner/i);
  assert.match(sql, /alter function public\.apply_establishment_tombstone_v2\(jsonb\)\s+owner to catalog_writer_v2_owner/i);
  assert.match(sql, /grant execute on function public\.apply_establishment_projection_v2\(jsonb\)\s+to catalog_writer_v2/i);
  assert.match(sql, /grant execute on function public\.apply_establishment_tombstone_v2\(jsonb\)\s+to catalog_writer_v2/i);
  assert.match(sql, /from public, anon, authenticated, catalog_writer_v2, catalog_writer_v2_login/i);
  assert.doesNotMatch(sql, /revoke\s+(?:all|execute)[\s\S]{0,220}\bfrom\s+[^;]*\bservice_role\b/i);
  assert.match(grants, /select plan\(/i);
  assert.match(grants, /set local role catalog_writer_v2/i);
  assert.match(grants, /security definer writers run as the restricted function owner/i);
  assert.match(grants, /legacy service_role remains compatible/i);
});

test('PostgreSQL RPC adapter calls only fixed V2 functions with bound JSON and timeout contract', async () => {
  const calls = [];
  const rpc = createSupabaseCatalogPostgresRpcClient({
    timeoutMs: 2_500,
    query: async (request) => {
      calls.push(request);
      return { rows: [{ result: 'applied' }] };
    },
  });

  assert.deepEqual(await rpc('apply_establishment_projection_v2', { p_projection: projection }), { data: 'applied' });
  assert.deepEqual(calls, [{
    sql: 'select public.apply_establishment_projection_v2($1::jsonb) as result',
    parameters: [JSON.stringify(projection)],
    timeoutMs: 2_500,
  }]);
});

test('PostgreSQL RPC adapter maps a confirmed replay to the existing writer contract', async () => {
  const rpc = createSupabaseCatalogPostgresRpcClient({
    query: async () => ({ rows: [{ result: 'replayed' }] }),
  });
  assert.deepEqual(await rpc('apply_establishment_tombstone_v2', {
    p_tombstone: { id: 'modelo-synthetic', catalog_version: 1, outbox_operation_id: projection.outbox_operation_id, deleted_at: '2026-10-22T12:00:00Z' },
  }), { data: 'replayed' });
});

test('PostgreSQL RPC adapter rejects arbitrary functions and malformed argument shapes before query', async () => {
  let calls = 0;
  const rpc = createSupabaseCatalogPostgresRpcClient({ query: async () => { calls += 1; return { rows: [] }; } });
  await assert.rejects(rpc('arbitrary_sql', { query: 'drop table x' }), SupabaseCatalogPostgresError);
  await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection, extra: true }), SupabaseCatalogPostgresError);
  assert.equal(calls, 0);
});

test('PostgreSQL failures are sanitized and preserve retry versus permanent classifications', async () => {
  for (const [code, expected] of [['23514', 'catalog_conflict'], ['22023', 'permanent_failure'], ['08006', 'catalog_unavailable']]) {
    const rpc = createSupabaseCatalogPostgresRpcClient({
      query: async () => { throw Object.assign(new Error('private connection string'), { code }); },
    });
    await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection }), (error) => {
      assert.ok(error instanceof SupabaseCatalogPostgresError);
      assert.equal(error.code, expected);
      assert.doesNotMatch(error.message, /private|connection/i);
      return true;
    });
  }
});

test('PostgreSQL RPC adapter rejects unbounded timeout and malformed query results', async () => {
  assert.throws(() => createSupabaseCatalogPostgresRpcClient({ query: async () => ({}), timeoutMs: 60_000 }), SupabaseCatalogPostgresError);
  const rpc = createSupabaseCatalogPostgresRpcClient({ query: async () => ({ rows: [{ other: 'unexpected' }] }) });
  await assert.rejects(rpc('apply_establishment_projection_v2', { p_projection: projection }), SupabaseCatalogPostgresError);
});
