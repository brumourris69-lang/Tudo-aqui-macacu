begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(49);

create function pg_temp.writer_projection(
  p_id text,
  p_version bigint,
  p_operation text,
  p_name text default 'Writer Market',
  p_published boolean default true,
  p_deleted_at timestamptz default null
)
returns jsonb language sql immutable set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', p_id,
    'content_kind', 'establishment',
    'category_group', 'commerce',
    'name', p_name,
    'summary', 'Public writer fixture',
    'category', 'Comércio',
    'subcategory', 'Market',
    'location', 'Cachoeiras de Macacu',
    'artwork', 0,
    'image_url', '',
    'logo_url', '',
    'gallery_urls', '[]'::jsonb,
    'featured', false,
    'is_open', true,
    'maps_url', '',
    'hours', '',
    'services', '[]'::jsonb,
    'products', '[]'::jsonb,
    'additional_info', '',
    'promotion_title', '',
    'promotion_description', '',
    'public_contact_approved', false,
    'phone', null,
    'whatsapp', null,
    'instagram', null,
    'published', p_published,
    'active', true,
    'expires_at', null,
    'deleted_at', p_deleted_at,
    'catalog_version', p_version,
    'outbox_operation_id', p_operation
  );
$function$;
grant execute on function pg_temp.writer_projection(text, bigint, text, text, boolean, timestamptz)
  to catalog_writer_v2;

select ok(
  has_function_privilege('catalog_writer_v2', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE'),
  'dedicated catalog writer can execute the projection writer'
);
select ok(
  has_function_privilege('catalog_writer_v2', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'dedicated catalog writer can execute the tombstone writer'
);
select ok(
  not exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = 'public.apply_establishment_projection_v2(jsonb)'::regprocedure
      and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege('anon', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and not exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = 'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
      and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  )
  and not has_function_privilege('anon', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'public client roles stay denied while service_role remains during the compatibility phase'
);
select ok(
  not has_table_privilege('service_role', 'public.public_establishment_catalog_v2', 'INSERT')
  and not has_table_privilege('service_role', 'public.public_establishment_catalog_v2', 'UPDATE')
  and not has_table_privilege('service_role', 'public.public_establishment_catalog_v2', 'DELETE')
  and not has_table_privilege('service_role', 'public.public_establishment_catalog_v2', 'SELECT')
  and not has_table_privilege('service_role', 'public.catalog_tombstones_v2', 'INSERT')
  and not has_table_privilege('service_role', 'public.catalog_tombstones_v2', 'UPDATE')
  and not has_table_privilege('service_role', 'public.catalog_tombstones_v2', 'DELETE')
  and not has_table_privilege('service_role', 'public.catalog_tombstones_v2', 'SELECT'),
  'service_role cannot bypass the writers with direct table writes'
);
select ok(
  (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.apply_establishment_projection_v2(jsonb)'::regprocedure)
  and (select prosecdef and proconfig @> array['search_path=""']
   from pg_proc where oid = 'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure),
  'writers are SECURITY DEFINER with an empty search_path'
);

-- pgTAP lives in extensions. This test-only schema visibility is rolled back
-- and is not part of the production executor grants.
grant usage on schema extensions to catalog_writer_v2;
set local role catalog_writer_v2;
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 1,
      '30000000-0000-4000-8000-000000000001')
  ),
  'applied', 'legacy modelo-* ID is accepted through the authorized writer'
);
reset role;
select ok(
  exists(select 1 from pg_locks where locktype = 'advisory'
    and pid = pg_backend_pid() and granted and objsubid = 1),
  'writer holds an advisory transaction lock for per-ID serialization'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 1,
      '30000000-0000-4000-8000-000000000001')
  ),
  'replayed', 'same-version exact replay is idempotent'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 1,
      '30000000-0000-4000-8000-000000000001', 'Conflicting name'))$$,
  '23514', null, 'same-version content conflict is rejected'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 1,
      '30000000-0000-4000-8000-000000000002'))$$,
  '23514', null, 'same-version operation conflict is rejected'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 0,
      '30000000-0000-4000-8000-000000000003'))$$,
  '22023', null, 'zero catalog version is rejected'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 2,
      '30000000-0000-4000-8000-000000000004', 'Updated Writer Market')
  ),
  'applied', 'newer version updates an existing projection'
);
select is(
  (select name from public.public_establishment_catalog_v2 where id = 'modelo-writer-legacy'),
  'Updated Writer Market', 'newer projection content is stored'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 1,
      '30000000-0000-4000-8000-000000000018', 'Older Writer Market'))$$,
  '23514', null, 'a positive but older catalog version is rejected'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 3,
      '30000000-0000-4000-8000-000000000005', 'Updated Writer Market', false)
  ),
  'applied', 'reversible unpublish is an ordinary newer projection'
);
select ok(
  (select not published and deleted_at is null
   from public.public_establishment_catalog_v2 where id = 'modelo-writer-legacy')
  and not exists(select 1 from public.catalog_tombstones_v2 where id = 'modelo-writer-legacy'),
  'unpublish hides the row without creating a permanent tombstone'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-writer-legacy')),
  0, 'public V2 detail does not return an unpublished projection'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 4,
      '30000000-0000-4000-8000-000000000006', 'Updated Writer Market', true)
  ),
  'applied', 'explicit newer republish restores visibility before logical deletion'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-writer-legacy')),
  1, 'public V2 detail returns the explicitly republished projection'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-private-payload', 1,
      '30000000-0000-4000-8000-000000000007') || '{"adminNote":"secret"}'::jsonb)$$,
  '22023', null, 'administrative and unknown payload fields are rejected'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2('{"id":"writer-incomplete"}'::jsonb)$$,
  '22023', null, 'incomplete projections are rejected'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-delete', 1,
      '30000000-0000-4000-8000-000000000008', 'Writer Market', true, statement_timestamp()))$$,
  '22023', null, 'permanent deletion cannot enter through the public projection writer'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-contact', 1,
      '30000000-0000-4000-8000-000000000009') || '{"phone":"+5521999999999"}'::jsonb)$$,
  '23514', null, 'the table constraint rejects unapproved contacts in the projection'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-category', 1,
      '30000000-0000-4000-8000-000000000010') || '{"category":"Empregos"}'::jsonb)$$,
  '23514', null, 'non-establishment categories are rejected by V2 constraints'
);
select is(
  (select count(*)::integer from public.public_establishment_catalog_v2
   where id = 'writer-invalid-category'),
  0, 'a rejected category leaves no projection behind'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-id', 1,
      '30000000-0000-4000-8000-000000000011') || '{"id":"bad/id"}'::jsonb)$$,
  '23514', null, 'Firestore-invalid document IDs are rejected'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-uuid', 1, 'not-a-uuid'))$$,
  '22023', null, 'invalid operation identifiers are rejected with a generic error'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-array', 1,
      '30000000-0000-4000-8000-000000000020') || '{"gallery_urls":"not-an-array"}'::jsonb)$$,
  '22023', null, 'projection arrays require JSON arrays of strings'
);
set local role catalog_writer_v2;
do $setup_invalid_image$
begin
  perform public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-image', 1,
      '30000000-0000-4000-8000-000000000024', 'Image constraint fixture')
  );
end;
$setup_invalid_image$;
reset role;
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-invalid-image', 2,
      '30000000-0000-4000-8000-000000000025', 'Image constraint fixture')
      || '{"image_url":"javascript:bad"}'::jsonb)$$,
  '23514', null, 'invalid image URL rejects a newer projection at the table constraint'
);
select is(
  (select catalog_version::integer from public.public_establishment_catalog_v2
   where id = 'writer-invalid-image'),
  1, 'failed image constraint update leaves the prior version intact'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-op-source', 1,
      '30000000-0000-4000-8000-000000000019', 'Writer Market', false)
  ),
  'applied', 'operation identifier source row is accepted'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-op-duplicate', 1,
      '30000000-0000-4000-8000-000000000019'))$$,
  '23514', null, 'operation identifier cannot be reused for another ID'
);

select is(
  public.apply_establishment_tombstone_v2(jsonb_build_object(
    'id', 'modelo-writer-legacy', 'catalog_version', 5,
    'outbox_operation_id', '30000000-0000-4000-8000-000000000012',
    'deleted_at', '2026-10-20T12:00:00Z'
  )),
  'applied', 'logical deletion writes a versioned tombstone'
);
select is(
  (select count(*)::integer from public.catalog_tombstones_v2
   where id = 'modelo-writer-legacy' and catalog_version = 5),
  1, 'logical deletion stores the tombstone metadata'
);
select ok(
  (select deleted_at = '2026-10-20T12:00:00Z'::timestamptz
      and catalog_version = 5
      and outbox_operation_id = '30000000-0000-4000-8000-000000000012'
   from public.public_establishment_catalog_v2 where id = 'modelo-writer-legacy'),
  'logical deletion atomically hides and versions an existing row'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-writer-legacy')),
  0, 'public V2 detail hides a logically deleted projection'
);
select is(
  public.apply_establishment_tombstone_v2(jsonb_build_object(
    'id', 'modelo-writer-legacy', 'catalog_version', 5,
    'outbox_operation_id', '30000000-0000-4000-8000-000000000012',
    'deleted_at', '2026-10-20T12:00:00Z'
  )),
  'replayed', 'exact tombstone replay is idempotent'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('modelo-writer-legacy', 6,
      '30000000-0000-4000-8000-000000000013'))$$,
  '23514', null, 'projection cannot resurrect a tombstoned ID'
);
select throws_ok(
  $$select public.apply_establishment_tombstone_v2(jsonb_build_object(
    'id', 'modelo-writer-legacy', 'catalog_version', 6,
    'outbox_operation_id', '30000000-0000-4000-8000-000000000014',
    'deleted_at', '2026-10-20T12:01:00Z'))$$,
  '23514', null, 'permanent tombstone cannot be replaced by a later operation'
);
select is(
  public.apply_establishment_tombstone_v2(jsonb_build_object(
    'id', 'writer-deleted-before-publish', 'catalog_version', 1,
    'outbox_operation_id', '30000000-0000-4000-8000-000000000015',
    'deleted_at', '2026-10-20T12:02:00Z'
  )),
  'applied', 'a deletion tombstone can precede the first catalog projection'
);
select throws_ok(
  $$select public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-deleted-before-publish', 2,
      '30000000-0000-4000-8000-000000000016'))$$,
  '23514', null, 'a tombstone for an absent row prevents later resurrection'
);
select is(
  public.apply_establishment_projection_v2(
    pg_temp.writer_projection('writer-stale-delete', 2,
      '30000000-0000-4000-8000-000000000022', 'Writer Market', false)
  ),
  'applied', 'versioned row is available for stale tombstone validation'
);
select throws_ok(
  $$select public.apply_establishment_tombstone_v2(jsonb_build_object(
    'id', 'writer-stale-delete', 'catalog_version', 1,
    'outbox_operation_id', '30000000-0000-4000-8000-000000000023',
    'deleted_at', '2026-10-20T12:03:00Z'))$$,
  '23514', null, 'older tombstone versions cannot delete newer projections'
);
select throws_ok(
  $$select public.apply_establishment_tombstone_v2(
    '{"id":"writer-tombstone-extra","catalog_version":1,"outbox_operation_id":"30000000-0000-4000-8000-000000000017","deleted_at":"2026-10-20T12:00:00Z","ownerEmail":"private"}'::jsonb)$$,
  '22023', null, 'tombstone writer rejects fields outside its four-key contract'
);

insert into public.public_search_establishments
  (id, name, summary, category, subcategory, image_url, published, active)
values ('pilot-writer-v1-fixture', 'V1 writer compatibility', 'writer compatibility fixture',
  'Comércio', '', '', true, true);
select is(
  (select count(*)::integer from public.search_public_establishments('writer', 'all', 20, null)),
  1, 'V1 public search remains callable with its existing contract'
);
select ok(
  to_regprocedure('public.get_public_establishment(text)') is not null
  and to_regprocedure('public.search_public_establishments(text,text,integer,text)') is not null,
  'V1 public RPC signatures remain unchanged'
);
select ok(
  to_regprocedure('public.search_public_establishments_v2(text,text,integer,text)') is not null
  and to_regprocedure('public.list_public_establishments_v2(text,integer,text)') is not null
  and to_regprocedure('public.get_public_establishment_v2(text)') is not null,
  'all V2 public RPC signatures remain available'
);
select is(
  (select count(*)::integer
   from public.search_public_establishments_v2('Updated Writer', 'all', 20, null)
   where id = 'modelo-writer-legacy'),
  0, 'V2 public search excludes the permanently tombstoned legacy ID'
);
select is(
  (select count(*)::integer
   from public.list_public_establishments_v2('all', 20, null)
   where id = 'modelo-writer-legacy'),
  0, 'V2 public paginated listing excludes the permanently tombstoned legacy ID'
);

select * from finish();
rollback;
