import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import test from 'node:test';

const migrationPath = new URL('../../migrations/20261022000100_private_catalog_writer_v2.sql', import.meta.url);
const tapPath = new URL('../../tests/database/catalog_private_writer_v2.sql', import.meta.url);
const v2Path = new URL('../../migrations/20261021000100_public_establishments_v2.sql', import.meta.url);
const protocolPath = new URL('./catalog_outbox_protocol.mjs', import.meta.url);
const adapterPath = new URL('./supabase_catalog_writer_v2.mjs', import.meta.url);
const concurrencyPath = new URL('../../tests/database/catalog_private_writer_v2_concurrency.mjs', import.meta.url);
const restrictedMigrationPath = new URL('../../migrations/20261024000100_restrict_catalog_writer_v2.sql', import.meta.url);
const restrictedTestsPath = new URL('../../tests/database/catalog_writer_role_v2.sql', import.meta.url);
const cutoverPath = new URL('../../operations/cutover_catalog_writer_v2.sql', import.meta.url);
const sql = existsSync(migrationPath) ? readFileSync(migrationPath, 'utf8') : '';
const tap = existsSync(tapPath) ? readFileSync(tapPath, 'utf8') : '';
const v2 = readFileSync(v2Path, 'utf8');
const protocol = readFileSync(protocolPath, 'utf8');
const adapter = existsSync(adapterPath) ? readFileSync(adapterPath, 'utf8') : '';
const concurrency = existsSync(concurrencyPath) ? readFileSync(concurrencyPath, 'utf8') : '';
const restrictedMigration = existsSync(restrictedMigrationPath) ? readFileSync(restrictedMigrationPath, 'utf8') : '';
const restrictedTests = existsSync(restrictedTestsPath) ? readFileSync(restrictedTestsPath, 'utf8') : '';
const cutover = existsSync(cutoverPath) ? readFileSync(cutoverPath, 'utf8') : '';

test('incremental migration adds separate projection and permanent tombstone writers', () => {
  assert.match(sql, /create or replace function public\.apply_establishment_projection_v2\(p_projection jsonb\)/i);
  assert.match(sql, /create or replace function public\.apply_establishment_tombstone_v2\(p_tombstone jsonb\)/i);
  assert.match(sql, /returns text[\s\S]*?language plpgsql[\s\S]*?security definer[\s\S]*?set search_path = ''/i);
  assert.match(sql, /alter function public\.apply_establishment_projection_v2\(jsonb\) owner to postgres/i);
  assert.match(sql, /alter function public\.apply_establishment_tombstone_v2\(jsonb\) owner to postgres/i);
  assert.doesNotMatch(sql, /create\s+(?:or replace\s+)?table/i);
});

test('projection writer permits only the outbox projection allowlist and rejects deletion payloads', () => {
  const block = sql.match(/create or replace function public\.apply_establishment_projection_v2\([\s\S]*?\$function\$;/i)?.[0] ?? '';
  for (const key of [
    'id', 'content_kind', 'category_group', 'name', 'summary', 'category', 'subcategory',
    'location', 'artwork', 'image_url', 'logo_url', 'gallery_urls', 'featured', 'is_open',
    'maps_url', 'hours', 'services', 'products', 'additional_info', 'promotion_title',
    'promotion_description', 'public_contact_approved', 'phone', 'whatsapp', 'instagram',
    'published', 'active', 'expires_at', 'deleted_at', 'catalog_version', 'outbox_operation_id',
  ]) assert.ok(block.includes(`'${key}'`), `allowlist must explicitly include ${key}`);
  assert.match(block, /jsonb_object_keys/);
  assert.match(block, /select pg_catalog\.count\(\*\) from pg_catalog\.jsonb_object_keys\(p_projection\)/i);
  assert.doesNotMatch(block, /jsonb_object_length/i);
  assert.match(block, /deleted_at is not null/i);
  assert.match(block, /unknown projection field|invalid catalog projection/i);
  assert.doesNotMatch(block, /adminNote|ownerEmail|admin_email|service_role/i);
  const allowedKeyBlock = block.match(/allowed_keys constant text\[\] := array\[([\s\S]*?)\];/)?.[1] ?? '';
  const writerKeys = [...allowedKeyBlock.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  const projectBlock = protocol.match(/const row = \{([\s\S]*?)\n  \};/)?.[1] ?? '';
  const protocolKeys = [...projectBlock.matchAll(/^\s*([a-z_]+)(?=\s*[:,])/gim)].map((match) => match[1]);
  assert.deepEqual(writerKeys, protocolKeys, 'writer allowlist must exactly match the protocol projection fields');
});

test('server RPC adapter allowlist matches the private SQL writer contract', () => {
  const block = adapter.match(/const PROJECTION_FIELDS = Object\.freeze\(\[([\s\S]*?)\]\);/)?.[1] ?? '';
  const adapterKeys = [...block.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  const sqlBlock = sql.match(/allowed_keys constant text\[\] := array\[([\s\S]*?)\];/)?.[1] ?? '';
  const sqlKeys = [...sqlBlock.matchAll(/'([a-z_]+)'/g)].map((match) => match[1]);
  assert.ok(adapterKeys.length > 0, 'RPC adapter must declare an explicit projection allowlist');
  assert.deepEqual(adapterKeys, sqlKeys);
  assert.match(adapter, /apply_establishment_projection_v2/);
  assert.match(adapter, /apply_establishment_tombstone_v2/);
  assert.doesNotMatch(adapter, /console\.(?:log|error|warn)/);
});

test('both writers serialize by original ID and check version and tombstone in one function transaction', () => {
  for (const name of ['apply_establishment_projection_v2', 'apply_establishment_tombstone_v2']) {
    const block = sql.match(new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?\\$function\\$;`, 'i'))?.[0] ?? '';
    assert.match(block, /pg_advisory_xact_lock\(\s*pg_catalog\.hashtextextended\(/i, name);
    assert.match(block, /for update/i, name);
    assert.match(block, /catalog_tombstones_v2/i, name);
    assert.match(block, /7302,\s*pg_catalog\.hashtext\('catalog-op:'/i, name);
  }
  assert.match(sql, /return 'replayed'/i);
  assert.match(sql, /return 'applied'/i);
  assert.match(sql, /catalog_version\s*</i);
  assert.match(sql, /same-version|same version|conflict/i);
});

test('ACL restricts writers to service_role and denies table bypass', () => {
  for (const name of ['apply_establishment_projection_v2(jsonb)', 'apply_establishment_tombstone_v2(jsonb)']) {
    const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(sql, new RegExp(`revoke all on function public\\.${escaped}\\s+from public, anon, authenticated, service_role`, 'i'));
    assert.match(sql, new RegExp(`grant execute on function public\\.${escaped} to service_role`, 'i'));
  }
  assert.match(sql, /revoke all on table public\.public_establishment_catalog_v2, public\.catalog_tombstones_v2\s+from service_role/i);
  assert.match(sql, /revoke all on function public\.apply_establishment_projection_v2\(jsonb\)\s+from public, anon, authenticated, service_role/i);
  assert.match(sql, /alter function public\.apply_establishment_projection_v2\(jsonb\) owner to postgres/i);
  assert.match(sql, /set search_path = ''/i);
});

test('preparation migration adds a login identity while preserving the legacy writer until explicit cutover', () => {
  assert.match(restrictedMigration, /create role catalog_writer_v2\s+nologin\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noinherit\s+noreplication\s+nobypassrls/i);
  assert.match(restrictedMigration, /create role catalog_writer_v2_owner\s+nologin\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noinherit\s+noreplication\s+nobypassrls/i);
  assert.match(restrictedMigration, /create role catalog_writer_v2_login\s+login\s+inherit\s+nosuperuser\s+nocreatedb\s+nocreaterole\s+noreplication\s+nobypassrls/i);
  assert.match(restrictedMigration, /grant catalog_writer_v2 to catalog_writer_v2_login/i);
  assert.match(restrictedMigration, /grant connect on database postgres to catalog_writer_v2_login/i);
  assert.doesNotMatch(restrictedMigration, /revoke\s+(?:all|execute)[\s\S]{0,220}\bfrom\s+[^;]*\bservice_role\b/i);
  for (const functionName of ['apply_establishment_projection_v2', 'apply_establishment_tombstone_v2']) {
    const escaped = functionName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    assert.match(restrictedMigration, /from public, anon, authenticated, catalog_writer_v2, catalog_writer_v2_login/i);
    assert.match(restrictedMigration, new RegExp(`grant execute on function public\\.${escaped}\\(jsonb\\)\\s+to catalog_writer_v2`, 'i'));
  }
  assert.match(restrictedMigration, /alter function public\.apply_establishment_projection_v2\(jsonb\)\s+owner to catalog_writer_v2_owner/i);
  assert.match(restrictedMigration, /alter function public\.apply_establishment_tombstone_v2\(jsonb\)\s+owner to catalog_writer_v2_owner/i);
  assert.match(restrictedMigration, /create policy catalog_writer_v2_owner_projection_select/i);
  assert.match(restrictedMigration, /create policy catalog_writer_v2_owner_tombstone_update/i);
  assert.match(restrictedMigration, /revoke create on schema public from catalog_writer_v2_owner/i);
  assert.match(restrictedTests, /select plan\(52\)/i);
  const assertions = restrictedTests.match(/^select\s+(?:ok|is|isnt|throws_ok)\s*\(/gim) ?? [];
  assert.equal(assertions.length, 52, 'restricted-role pgTAP plan must match the actual assertion count');
  for (const phrase of ['legacy service_role remains compatible', 'LOGIN inherits EXECUTE',
    'runtime role has no direct table privileges', 'no grants on unrelated application tables',
    'runtime role is denied direct SELECT',
    'tombstone rejects a later projection']) {
    assert.ok(restrictedTests.toLowerCase().includes(phrase.toLowerCase()), phrase);
  }
});

test('legacy EXECUTE revocation is a guarded manual operation outside automatic migrations', () => {
  assert.match(cutover, /restricted LOGIN role is absent or has unsafe attributes/i);
  assert.match(cutover, /do not match the approved executor/i);
  assert.match(cutover, /restricted LOGIN cannot connect to the current database/i);
  assert.match(cutover, /table privileges outside the allowlisted catalog objects/i);
  assert.match(cutover, /pg_catalog\.pg_class/);
  assert.match(cutover, /revoke all on function public\.apply_establishment_projection_v2\(jsonb\) from service_role/i);
  assert.match(cutover, /revoke all on function public\.apply_establishment_tombstone_v2\(jsonb\) from service_role/i);
  assert.match(cutover, /begin;[\s\S]*commit;/i);
  assert.doesNotMatch(restrictedMigration, /revoke all on function[^;]*service_role/i);
});

test('pgTAP covers ACL, projection, replay, conflict, lifecycle, tombstones, and public RPC compatibility', () => {
  const plan = Number(tap.match(/select plan\((\d+)\)/i)?.[1]);
  const assertions = tap.match(/^select\s+(?:ok|is|isnt|throws_ok|lives_ok|has_function)\s*\(/gim) ?? [];
  assert.ok(plan >= 25);
  assert.equal(assertions.length, plan);
  for (const phrase of [
    'same-version exact replay', 'same-version content conflict', 'older catalog version',
    'logical deletion', 'unpublish', 'republish', 'service_role', 'search_public_establishments_v2',
    'list_public_establishments_v2', 'get_public_establishment_v2', 'search_public_establishments(',
    'get_public_establishment(', 'advisory transaction lock',
  ]) assert.ok(tap.toLowerCase().includes(phrase.toLowerCase()), phrase);
});

test('migration leaves the additive V2 catalog schema and public RPC declarations untouched', () => {
  assert.doesNotMatch(sql, /create\s+or\s+replace\s+function\s+public\.(search_public_establishments_v2|list_public_establishments_v2|get_public_establishment_v2)\s*\(/i);
  assert.doesNotMatch(sql, /drop\s+(?:function|table)\s+public\.(?:public_establishment_catalog_v2|catalog_tombstones_v2|search_public_establishments_v2|get_public_establishment_v2)/i);
  for (const name of ['search_public_establishments_v2', 'list_public_establishments_v2', 'get_public_establishment_v2']) {
    assert.match(v2, new RegExp(`create or replace function public\\.${name}\\(`, 'i'));
  }
});

test('concurrency harness holds session A open and proves session B waits on its advisory lock before release', () => {
  assert.match(concurrency, /function startPsqlSession\(/);
  assert.match(concurrency, /'exec',\s*'--interactive'/);
  assert.match(concurrency, /child\.stdin\.write\(/);
  assert.match(concurrency, /pg_backend_pid\(\)/);
  assert.match(concurrency, /wait_event_type\s*=\s*'Lock'/i);
  assert.match(concurrency, /wait_event\s*=\s*'advisory'/i);
  assert.match(concurrency, /pg_catalog\.pg_locks|\bpg_locks\b/i);
  assert.match(concurrency, /waiterPid\s*!==\s*winnerPid/);
  assert.doesNotMatch(concurrency, /waitForOutput\(winner,\s*'applied'/);

  const waitForLock = concurrency.indexOf('const loserBlocked = distinctBackends');
  const releaseWinner = concurrency.indexOf('winner.sendLine("commit;")');
  assert.ok(waitForLock >= 0 && releaseWinner > waitForLock, 'session A must commit only after session B lock wait is observed');
});
