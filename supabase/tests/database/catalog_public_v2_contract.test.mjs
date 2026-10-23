import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const migrationPath = new URL('../../migrations/20261021000100_public_establishments_v2.sql', import.meta.url);
const docsPath = new URL('../../../docs/public-catalog-v2.md', import.meta.url);
const pgtapPath = new URL('./catalog_public_v2.sql', import.meta.url);
const sql = readFileSync(migrationPath, 'utf8');
const docs = readFileSync(docsPath, 'utf8');
const pgtap = readFileSync(pgtapPath, 'utf8');

test('V2 migration defines an additive public catalog contract', () => {
  assert.match(sql, /create table public\.public_establishment_catalog_v2/i);
  assert.match(sql, /create or replace function public\.search_public_establishments_v2\(/i);
  assert.match(sql, /create or replace function public\.list_public_establishments_v2\(/i);
  assert.match(sql, /create or replace function public\.get_public_establishment_v2\(/i);
  assert.doesNotMatch(sql, /create\s+or\s+replace\s+function\s+public\.(search_public_establishments|get_public_establishment)\s*\(/i);
});

test('taxonomy preserves the nineteen Admin categories and keeps six content types out of establishment RPCs', () => {
  const categories = [
    'Comércio', 'Onde comer?', 'Serviços', 'Profissionais', 'Empregos', 'Turismo',
    'Notícias', 'Eventos', 'Saúde', 'Imóveis', 'Veículos', 'Pets', 'Beleza',
    'Academias', 'Educação', 'Hospedagem', 'Promoções', 'Serviços úteis', 'Tecnologia',
  ];
  for (const category of categories) assert.ok(sql.includes(`'${category}'`), category);
  assert.match(sql, /content_kind = 'establishment'/i);
  assert.match(sql, /content_kind = 'other_content'/i);
  assert.match(sql, /category_group = 'other'/i);
  assert.match(docs, /Empregos.*Turismo.*Notícias.*Eventos.*Promoções.*Serviços úteis/s);
});

test('document IDs follow Firestore constraints without a pilot prefix or restrictive alphabet', () => {
  const validator = sql.match(/create or replace function public\.catalog_firestore_id_valid_v2[\s\S]*?\$function\$;/i)?.[0];
  assert.ok(validator);
  assert.match(validator, /octet_length\(value\) between 1 and 1500/i);
  assert.match(validator, /position\('\/' in value\) = 0/i);
  assert.match(validator, /value not in \('\.', '\.\.'\)/i);
  assert.match(validator, /left\(value, 2\) <> '__'[\s\S]*right\(value, 2\) <> '__'/i);
  assert.match(validator, /__id\[0-9\]\+__/i);
  assert.doesNotMatch(validator, /pilot-|A-Za-z0-9_-\}\{1,128/);
});

test('public RPCs return explicit fields and omit synchronization and lifecycle metadata', () => {
  for (const name of [
    'search_public_establishments_v2',
    'list_public_establishments_v2',
    'get_public_establishment_v2',
  ]) {
    const block = sql.match(new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?\\$function\\$;`, 'i'))?.[0];
    assert.ok(block, name);
    const projection = block.match(/returns table\s*\(([\s\S]*?)\)\s*language/i)?.[1];
    assert.ok(projection, name);
    assert.doesNotMatch(projection, /catalog_version|outbox_operation_id|public_contact_approved|search_document|deleted_at|expires_at/i);
    assert.match(block, /case when .*public_contact_approved then .*phone else null end/i);
  }
});

test('public access is limited to explicit RPC execution and tables stay private', () => {
  assert.match(sql, /alter table public\.public_establishment_catalog_v2 enable row level security/i);
  assert.match(sql, /alter table public\.public_establishment_catalog_v2 force row level security/i);
  assert.match(sql, /alter table public\.catalog_tombstones_v2 enable row level security/i);
  assert.match(sql, /revoke all on table public\.public_establishment_catalog_v2 from public, anon, authenticated/i);
  assert.match(sql, /revoke all on table public\.catalog_tombstones_v2 from public, anon, authenticated/i);
  for (const name of [
    'search_public_establishments_v2(text, text, integer, text)',
    'list_public_establishments_v2(text, integer, text)',
    'get_public_establishment_v2(text)',
  ]) assert.ok(sql.toLowerCase().includes(`grant execute on function public.${name} to anon;`), name);
  assert.doesNotMatch(sql, /grant\s+select\s+on\s+table\s+public\.(public_establishment_catalog_v2|catalog_tombstones_v2)/i);
});

test('visibility checks, bounded pagination, deterministic ordering and search indexes are present', () => {
  assert.equal((sql.match(/e\.published and e\.active and e\.deleted_at is null[\s\S]{0,100}e\.expires_at > statement_timestamp\(\)/gi) ?? []).length, 5);
  assert.match(sql, /p_page_size not between 1 and 40/i);
  assert.match(sql, /order by e\.id collate "C"/i);
  assert.match(sql, /order by e\.name collate "C", e\.id collate "C"/i);
  assert.match(sql, /extensions\.gin_trgm_ops/i);
  assert.match(sql, /public_establishment_catalog_v2_visible_name_idx/i);
  assert.match(sql, /public_establishment_catalog_v2_list_name_idx/i);
  assert.match(sql, /public_establishment_catalog_v2_expiry_idx/i);
});

test('contact approval and field validators are enforced before values reach the public projection', () => {
  assert.match(sql, /check \(public_contact_approved or \(phone is null and whatsapp is null and instagram is null\)\)/i);
  assert.match(sql, /catalog_phone_valid_v2\(phone\)/i);
  assert.match(sql, /catalog_whatsapp_valid_v2\(whatsapp\)/i);
  assert.match(sql, /catalog_instagram_valid_v2\(instagram\)/i);
  assert.match(sql, /catalog_https_array_valid_v2\(gallery_urls, 20\)/i);
  assert.match(sql, /catalog_text_array_valid_v2\(services, 40, 160\)/i);
  assert.match(sql, /catalog_text_array_valid_v2\(products, 40, 160\)/i);
});

test('versioned tombstones serialize writes and block stale or later resurrection', () => {
  assert.match(sql, /create table public\.catalog_tombstones_v2/i);
  assert.equal((sql.match(/pg_advisory_xact_lock\(pg_catalog\.hashtextextended\(new\.id, 0\)\)/gi) ?? []).length, 2);
  assert.match(sql, /new\.catalog_version <= old\.catalog_version/i);
  assert.match(sql, /catalog row is tombstoned/i);
  assert.match(sql, /catalog tombstone is immutable/i);
  assert.match(sql, /stale catalog tombstone/i);
  assert.match(sql, /catalog_prevent_physical_delete_v2/i);
  assert.match(sql, /catalog_tombstone_immutable_v2/i);
  assert.match(sql, /to_jsonb\(new\)[\s\S]{0,80}search_document/i);
  assert.match(sql, /return null/i);
  assert.match(pgtap, /old events cannot resurrect a tombstoned ID/i);
  assert.match(pgtap, /exact version and operation replay is idempotent/i);
  assert.match(pgtap, /projection rows cannot be physically deleted/i);
  assert.match(pgtap, /tombstones cannot be edited/i);
});

test('pgTAP V2 suite declares the same number of assertions it contains', () => {
  const plan = Number(pgtap.match(/select plan\((\d+)\)/i)?.[1]);
  const assertions = pgtap.match(/^select\s+(?:ok|is|isnt|throws_ok|lives_ok)\s*\(/gim) ?? [];
  assert.ok(plan > 0);
  assert.equal(assertions.length, plan);
});

test('V2 SQL tests include legacy IDs, all categories, publication filters, contacts, pagination and V1 contracts', () => {
  assert.match(pgtap, /modelo-legacy-7/);
  assert.match(pgtap, /__id42__/);
  assert.match(pgtap, /Notícias/);
  assert.match(pgtap, /public_contact_approved/);
  assert.match(pgtap, /has_more/);
  assert.match(pgtap, /search_public_establishments\(text,text,integer,text\)/i);
  assert.match(pgtap, /get_public_establishment\(text\)/i);
});
