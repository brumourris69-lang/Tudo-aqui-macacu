begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(49);

create function pg_temp.reconciliation_projection(
  p_id text, p_version bigint, p_operation text, p_published boolean default true,
  p_active boolean default true, p_expires_at timestamptz default null
)
returns jsonb language sql immutable set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', p_id, 'content_kind', 'establishment', 'category_group', 'commerce',
    'name', p_id, 'summary', 'Synthetic reconciliation fixture',
    'category', 'Comércio', 'subcategory', 'Fixture', 'location', null,
    'artwork', 0, 'image_url', '', 'logo_url', '', 'gallery_urls', '[]'::jsonb,
    'featured', false, 'is_open', true, 'maps_url', '', 'hours', '',
    'services', '[]'::jsonb, 'products', '[]'::jsonb, 'additional_info', '',
    'promotion_title', '', 'promotion_description', '', 'public_contact_approved', false,
    'phone', null, 'whatsapp', null, 'instagram', null,
    'published', p_published, 'active', p_active, 'expires_at', p_expires_at,
    'deleted_at', null, 'catalog_version', p_version, 'outbox_operation_id', p_operation
  );
$function$;
grant execute on function pg_temp.reconciliation_projection(text, bigint, text, boolean, boolean, timestamptz)
  to catalog_writer_v2;

select ok(to_regclass('public.catalog_reconciliation_snapshots_v2') is not null,
  'private snapshot header table exists');
select ok(to_regclass('public.catalog_reconciliation_snapshot_rows_v2') is not null,
  'private snapshot row table exists');
select ok(to_regclass('public.public_establishment_catalog_v2_reconciliation_ids_idx') is not null,
  'bounded reconciliation scan has a partial establishment ID index');
select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.catalog_reconciliation_snapshots_v2'::regclass)
  and (select relrowsecurity and relforcerowsecurity from pg_class where oid = 'public.catalog_reconciliation_snapshot_rows_v2'::regclass),
  'both snapshot tables enable and force row-level security');
select ok(
  not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshots_v2', 'SELECT')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshots_v2', 'INSERT')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshots_v2', 'UPDATE')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshots_v2', 'DELETE')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshot_rows_v2', 'SELECT')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshot_rows_v2', 'INSERT')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshot_rows_v2', 'UPDATE')
  and not has_table_privilege('service_role', 'public.catalog_reconciliation_snapshot_rows_v2', 'DELETE'),
  'service_role has no direct SELECT or mutation privilege on snapshot tables');
select ok(
  not has_table_privilege('anon', 'public.catalog_reconciliation_snapshots_v2', 'SELECT')
  and not has_table_privilege('authenticated', 'public.catalog_reconciliation_snapshots_v2', 'SELECT')
  and not has_table_privilege('anon', 'public.catalog_reconciliation_snapshot_rows_v2', 'SELECT')
  and not has_table_privilege('authenticated', 'public.catalog_reconciliation_snapshot_rows_v2', 'SELECT')
  and not has_table_privilege('anon', 'public.catalog_reconciliation_snapshots_v2', 'INSERT')
  and not has_table_privilege('anon', 'public.catalog_reconciliation_snapshot_rows_v2', 'INSERT')
  and not has_table_privilege('authenticated', 'public.catalog_reconciliation_snapshots_v2', 'INSERT')
  and not has_table_privilege('authenticated', 'public.catalog_reconciliation_snapshot_rows_v2', 'INSERT'),
  'anon and authenticated cannot read or insert snapshot data');
select ok(
  has_function_privilege('service_role', 'public.begin_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.read_catalog_reconciliation_page_v2(uuid,text,integer)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.dispose_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE'),
  'service_role can execute the three private snapshot RPCs');
select ok(
  not has_function_privilege('anon', 'public.begin_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.begin_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.read_catalog_reconciliation_page_v2(uuid,text,integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.read_catalog_reconciliation_page_v2(uuid,text,integer)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.dispose_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.dispose_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE'),
  'anon and authenticated cannot execute any private snapshot RPC');
select ok(
  not exists (
    select 1 from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid in (
      'public.begin_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure,
      'public.read_catalog_reconciliation_page_v2(uuid,text,integer)'::regprocedure,
      'public.dispose_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure
    ) and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ), 'PUBLIC has no EXECUTE on private snapshot RPCs');
select ok(
  (select count(*) = 3 from pg_proc p
   where p.oid in (
     'public.begin_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure,
     'public.read_catalog_reconciliation_page_v2(uuid,text,integer)'::regprocedure,
     'public.dispose_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure
   ) and p.prosecdef and pg_catalog.pg_get_userbyid(p.proowner) = 'postgres'),
  'all snapshot RPCs are SECURITY DEFINER owned by postgres');
select ok(
  (select count(*) = 3 from pg_proc p
   where p.oid in (
     'public.begin_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure,
     'public.read_catalog_reconciliation_page_v2(uuid,text,integer)'::regprocedure,
     'public.dispose_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure
   ) and p.proconfig @> array['search_path=""']),
  'all snapshot RPCs use an empty search_path');
select ok(
  (select count(*) = 3 from pg_proc p
   where p.oid in (
     'public.begin_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure,
     'public.read_catalog_reconciliation_page_v2(uuid,text,integer)'::regprocedure,
     'public.dispose_catalog_reconciliation_snapshot_v2(uuid)'::regprocedure
   ) and p.proconfig @> array['statement_timeout=30s']),
  'all snapshot RPCs enforce a bounded statement timeout');

-- pgTAP lives in extensions. This test-only schema visibility is rolled back
-- and does not grant production executor access.
grant usage on schema extensions to catalog_writer_v2;
set local role catalog_writer_v2;
select is(public.apply_establishment_projection_v2(pg_temp.reconciliation_projection(
  'modelo-recon-01-active', 1, '61000000-0000-4000-8000-000000000001')), 'applied', 'active fixture is stored');
select is(public.apply_establishment_projection_v2(pg_temp.reconciliation_projection(
  'modelo-recon-02-deleted', 1, '61000000-0000-4000-8000-000000000002')), 'applied', 'deletion fixture is stored');
select is(public.apply_establishment_tombstone_v2(pg_catalog.jsonb_build_object(
  'id', 'modelo-recon-02-deleted', 'catalog_version', 2,
  'outbox_operation_id', '61000000-0000-4000-8000-000000000003',
  'deleted_at', '2026-10-20T12:00:00Z')), 'applied', 'permanent tombstone fixture is stored');
select is(public.apply_establishment_projection_v2(pg_temp.reconciliation_projection(
  'modelo-recon-03-expired', 1, '61000000-0000-4000-8000-000000000004', true, true, '2026-10-20T12:00:00Z')), 'applied', 'expired fixture is stored');
select is(public.apply_establishment_projection_v2(pg_temp.reconciliation_projection(
  'modelo-recon-04-inactive', 1, '61000000-0000-4000-8000-000000000005', true, false)), 'applied', 'inactive fixture is stored');
select is(public.apply_establishment_projection_v2(pg_temp.reconciliation_projection(
  'modelo-recon-05-unpublished', 1, '61000000-0000-4000-8000-000000000006', false, true)), 'applied', 'unpublished fixture is stored');
reset role;

select is(public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000001')->>'replayed',
  'false', 'first begin creates one snapshot');
select is(public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000001')->>'replayed',
  'true', 'repeated begin is idempotent');
select is((public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000001')->>'entity_count')::integer,
  5, 'snapshot captures all establishment IDs including hidden states');
select ok((select payload_bytes between 0 and 67108864 from public.catalog_reconciliation_snapshots_v2
  where snapshot_id = '62000000-0000-4000-8000-000000000001'), 'snapshot payload remains within the byte limit');
select ok(not exists(
  select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and coalesce(r.catalog_row, '{}'::jsonb) ? 'search_document'), 'materialized rows exclude derived search_document');
select ok(exists(select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and r.entity_id = 'modelo-recon-05-unpublished' and r.catalog_row->>'published' = 'false'),
  'snapshot includes unpublished rows');
select ok(exists(select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and r.entity_id = 'modelo-recon-04-inactive' and r.catalog_row->>'active' = 'false'),
  'snapshot includes inactive rows');
select ok(exists(select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and r.entity_id = 'modelo-recon-03-expired'
    and (r.catalog_row->>'expires_at')::timestamptz = '2026-10-20T12:00:00Z'::timestamptz),
  'snapshot includes expired rows');
select ok(exists(select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and r.entity_id = 'modelo-recon-02-deleted' and r.catalog_row->>'deleted_at' is not null),
  'snapshot includes logically deleted catalog rows');
select ok(exists(select 1 from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = '62000000-0000-4000-8000-000000000001'
    and r.entity_id = 'modelo-recon-02-deleted'
    and r.tombstone->>'catalog_version' = '2'
    and r.tombstone->>'outbox_operation_id' = '61000000-0000-4000-8000-000000000003'),
  'snapshot includes tombstone version and operation');

select is((public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 2)->>'done'), 'false', 'first bounded page reports more rows');
select is(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 2)->>'next_cursor',
  'modelo-recon-02-deleted', 'first page cursor follows deterministic C ordering');
select is(jsonb_array_length(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 2)->'catalog_rows'), 2,
  'first page includes the two catalog rows');
select is(jsonb_array_length(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 2)->'tombstones'), 1,
  'first page includes tombstone paired with the same entity ID');
select is((public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-02-deleted', 2)->>'done'),
  'false', 'second bounded page reports remaining rows');
select is(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-02-deleted', 2)->>'next_cursor',
  'modelo-recon-04-inactive', 'second page cursor remains deterministic');
select is((public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-04-inactive', 2)->>'done'),
  'true', 'final page reports completion');
select is(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-04-inactive', 2)->>'next_cursor',
  'modelo-recon-05-unpublished', 'final cursor is the last returned ID');
select is(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-04-inactive', 2)->'catalog_rows'->0->>'published',
  'false', 'final page returns the unpublished row');
select is(public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'modelo-recon-04-inactive', 2),
  public.read_catalog_reconciliation_page_v2(
    '62000000-0000-4000-8000-000000000001', 'modelo-recon-04-inactive', 2),
  'repeated page reads return an identical immutable snapshot');

select throws_ok($$select public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 0)$$,
  '22023', null, 'page size below one is rejected');
select throws_ok($$select public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', 'bad/id', 1)$$,
  '22023', null, 'invalid Firestore cursor is rejected');
select throws_ok($$select public.read_catalog_reconciliation_page_v2(
  '62999999-0000-4000-8000-000000000001', null, 1)$$,
  '55000', null, 'unknown snapshot is reported as expired');

insert into public.catalog_reconciliation_snapshots_v2(snapshot_id, created_at, expires_at)
values ('62000000-0000-4000-8000-000000000099', statement_timestamp() - interval '2 hours',
  statement_timestamp() - interval '1 hour');
select throws_ok($$select public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000099', null, 1)$$,
  '55000', null, 'expired snapshot cannot be read');

select is((public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000002')->>'replayed'),
  'false', 'second concurrent snapshot slot can be used');
select is((public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000003')->>'replayed'),
  'false', 'third concurrent snapshot slot can be used');
select is((public.begin_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000004')->>'replayed'),
  'false', 'fourth concurrent snapshot slot can be used');
select throws_ok($$select public.begin_catalog_reconciliation_snapshot_v2(
  '62000000-0000-4000-8000-000000000005')$$,
  '54000', null, 'concurrent snapshot capacity is bounded');

select is(public.dispose_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000001'),
  true, 'dispose removes only the requested snapshot');
select is(public.dispose_catalog_reconciliation_snapshot_v2('62000000-0000-4000-8000-000000000001'),
  false, 'repeated dispose is idempotent');
select throws_ok($$select public.read_catalog_reconciliation_page_v2(
  '62000000-0000-4000-8000-000000000001', null, 1)$$,
  '55000', null, 'disposed snapshot cannot be read');

reset role;
select * from finish();
rollback;
