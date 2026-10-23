begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(52);

select ok(
  exists (select 1 from pg_roles where rolname = 'catalog_writer_v2'
    and not rolcanlogin and not rolsuper and not rolcreatedb and not rolcreaterole
    and not rolinherit and not rolreplication and not rolbypassrls and rolconnlimit = 2),
  'runtime writer role is initially non-login, non-admin, non-inheriting and connection-limited'
);
select ok(
  exists (select 1 from pg_roles where rolname = 'catalog_writer_v2_owner'
    and not rolcanlogin and not rolsuper and not rolcreatedb and not rolcreaterole
    and not rolinherit and not rolreplication and not rolbypassrls),
  'SECURITY DEFINER owner is a separate non-login, non-admin, non-bypass role'
);
select ok(
  exists (select 1 from pg_roles where rolname = 'catalog_writer_v2_login'
    and rolcanlogin and rolinherit and not rolsuper and not rolcreatedb and not rolcreaterole
    and not rolreplication and not rolbypassrls and rolconnlimit = 2),
  'dedicated connection role can log in but has no administrative or bypass attributes'
);
select ok(
  pg_catalog.pg_has_role('catalog_writer_v2_login', 'catalog_writer_v2', 'MEMBER')
  and not pg_catalog.pg_has_role('catalog_writer_v2_login', 'catalog_writer_v2_owner', 'MEMBER')
  and not pg_catalog.pg_has_role('catalog_writer_v2_login', 'service_role', 'MEMBER'),
  'LOGIN inherits only the executor group and cannot assume owner or service_role'
);
select ok(
  (select rolconfig @> array['search_path=""', 'statement_timeout=8s', 'lock_timeout=3s',
    'idle_in_transaction_session_timeout=10s'] from pg_roles where rolname = 'catalog_writer_v2_login'),
  'LOGIN role has an empty search path and bounded timeouts'
);
select ok(
  has_database_privilege('catalog_writer_v2_login', current_database(), 'CONNECT'),
  'dedicated LOGIN can connect to the current database'
);
select ok(not pg_catalog.pg_has_role('catalog_writer_v2', 'catalog_writer_v2_owner', 'MEMBER'),
  'runtime role cannot assume the function-owner identity');
select ok(
  (select rolconfig @> array['search_path=""', 'statement_timeout=8s', 'lock_timeout=3s',
    'idle_in_transaction_session_timeout=10s'] from pg_roles where rolname = 'catalog_writer_v2'),
  'runtime role has an empty search path and bounded timeouts'
);
select ok(
  (select rolconfig @> array['search_path=""', 'statement_timeout=8s', 'lock_timeout=3s']
   from pg_roles where rolname = 'catalog_writer_v2_owner'),
  'function owner has an empty search path and bounded timeouts'
);
select ok(
  has_function_privilege('catalog_writer_v2', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE'),
  'runtime role can execute the allowlisted projection writer'
);
select ok(
  has_function_privilege('catalog_writer_v2', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'runtime role can execute the allowlisted tombstone writer'
);
select ok(
  has_function_privilege('service_role', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and has_function_privilege('service_role', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'legacy service_role remains compatible until the separately gated cutover'
);
select ok(
  has_function_privilege('catalog_writer_v2_login', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_login', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'LOGIN inherits EXECUTE on both approved writer RPCs'
);
select ok(
  not has_function_privilege('anon', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'),
  'public client roles cannot invoke private writers'
);
select ok(
  not exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid in (
      'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
      'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
    ) and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ), 'PUBLIC cannot invoke either private writer');
select is(
  (select count(*)::text from pg_proc p
   where p.oid in (
     'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
     'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
   ) and p.prosecdef and pg_catalog.pg_get_userbyid(p.proowner) = 'catalog_writer_v2_owner'),
  '2', 'both SECURITY DEFINER writers run as the restricted function owner'
);
select ok(
  (select count(*) = 2 from pg_proc p where p.oid in (
    'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
    'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
  ) and p.proconfig @> array['search_path=""']),
  'both writers retain an empty search_path'
);
select ok(
  (select count(*) = 2 from pg_proc p where p.oid in (
    'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
    'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
  ) and p.proconfig @> array['statement_timeout=8s', 'lock_timeout=3s']),
  'both writers enforce statement and lock timeouts'
);
select ok(
  has_table_privilege('catalog_writer_v2_owner', 'public.public_establishment_catalog_v2', 'SELECT')
  and has_table_privilege('catalog_writer_v2_owner', 'public.public_establishment_catalog_v2', 'INSERT')
  and has_table_privilege('catalog_writer_v2_owner', 'public.public_establishment_catalog_v2', 'UPDATE')
  and not has_table_privilege('catalog_writer_v2_owner', 'public.public_establishment_catalog_v2', 'DELETE')
  and not has_table_privilege('catalog_writer_v2_owner', 'public.public_establishment_catalog_v2', 'TRUNCATE'),
  'function owner has only projection read/insert/update table grants'
);
select ok(
  has_table_privilege('catalog_writer_v2_owner', 'public.catalog_tombstones_v2', 'SELECT')
  and has_table_privilege('catalog_writer_v2_owner', 'public.catalog_tombstones_v2', 'INSERT')
  and has_table_privilege('catalog_writer_v2_owner', 'public.catalog_tombstones_v2', 'UPDATE')
  and not has_table_privilege('catalog_writer_v2_owner', 'public.catalog_tombstones_v2', 'DELETE')
  and not has_table_privilege('catalog_writer_v2_owner', 'public.catalog_tombstones_v2', 'TRUNCATE'),
  'function owner has only tombstone read/insert plus row-lock update privilege'
);
select ok(
  not has_table_privilege('catalog_writer_v2', 'public.public_establishment_catalog_v2', 'SELECT')
  and not has_table_privilege('catalog_writer_v2', 'public.public_establishment_catalog_v2', 'INSERT')
  and not has_table_privilege('catalog_writer_v2', 'public.public_establishment_catalog_v2', 'UPDATE')
  and not has_table_privilege('catalog_writer_v2', 'public.public_establishment_catalog_v2', 'DELETE')
  and not has_table_privilege('catalog_writer_v2', 'public.catalog_tombstones_v2', 'SELECT')
  and not has_table_privilege('catalog_writer_v2', 'public.catalog_tombstones_v2', 'INSERT')
  and not has_table_privilege('catalog_writer_v2', 'public.catalog_tombstones_v2', 'UPDATE')
  and not has_table_privilege('catalog_writer_v2', 'public.catalog_tombstones_v2', 'DELETE'),
  'runtime role has no direct table privileges'
);
select ok(
  not has_table_privilege('catalog_writer_v2_login', 'public.public_establishment_catalog_v2', 'SELECT')
  and not has_table_privilege('catalog_writer_v2_login', 'public.public_establishment_catalog_v2', 'INSERT')
  and not has_table_privilege('catalog_writer_v2_login', 'public.public_establishment_catalog_v2', 'UPDATE')
  and not has_table_privilege('catalog_writer_v2_login', 'public.catalog_tombstones_v2', 'SELECT')
  and not has_table_privilege('catalog_writer_v2_login', 'public.catalog_tombstones_v2', 'INSERT')
  and not has_table_privilege('catalog_writer_v2_login', 'public.catalog_tombstones_v2', 'UPDATE'),
  'LOGIN has no direct catalog table privileges, including inherited privileges'
);
select ok(
  not exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname not in ('information_schema', 'extensions')
      and n.nspname not like 'pg\_%' escape '\'
      and c.relkind in ('r', 'p', 'v', 'm', 'f')
      and (
        pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'SELECT')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'INSERT')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'UPDATE')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'DELETE')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'TRUNCATE')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'REFERENCES')
        or pg_catalog.has_table_privilege('catalog_writer_v2_login', c.oid, 'TRIGGER')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'SELECT')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'INSERT')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'UPDATE')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'DELETE')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'TRUNCATE')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'REFERENCES')
        or pg_catalog.has_table_privilege('catalog_writer_v2', c.oid, 'TRIGGER')
        or (
          c.oid not in (
            'public.public_establishment_catalog_v2'::regclass,
            'public.catalog_tombstones_v2'::regclass
          ) and (
            pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'SELECT')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'INSERT')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'UPDATE')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'DELETE')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'TRUNCATE')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'REFERENCES')
            or pg_catalog.has_table_privilege('catalog_writer_v2_owner', c.oid, 'TRIGGER')
          )
        )
      )
  ), 'writer identities have no grants on unrelated application tables'
);
select ok(
  (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.public_establishment_catalog_v2'::regclass)
  and (select relrowsecurity and relforcerowsecurity
   from pg_class where oid = 'public.catalog_tombstones_v2'::regclass),
  'both catalog tables retain ENABLE and FORCE ROW LEVEL SECURITY'
);
select ok(
  (select count(*) = 3 from pg_policies where schemaname = 'public'
    and tablename = 'public_establishment_catalog_v2' and policyname like 'catalog_writer_v2_owner_projection_%')
  and (select count(*) = 3 from pg_policies where schemaname = 'public'
    and tablename = 'catalog_tombstones_v2' and policyname like 'catalog_writer_v2_owner_tombstone_%'),
  'owner RLS policies cover only the operations needed by both writers'
);
select ok(
  has_function_privilege('catalog_writer_v2_owner', 'public.catalog_firestore_id_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_https_url_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_map_url_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_phone_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_whatsapp_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_instagram_valid_v2(text)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_text_array_valid_v2(text[],integer,integer)', 'EXECUTE')
  and has_function_privilege('catalog_writer_v2_owner', 'public.catalog_https_array_valid_v2(text[],integer)', 'EXECUTE'),
  'function owner can evaluate the V2 table constraints'
);
select ok(
  not has_function_privilege('catalog_writer_v2', 'public.catalog_firestore_id_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_https_url_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_map_url_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_phone_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_whatsapp_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_instagram_valid_v2(text)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_text_array_valid_v2(text[],integer,integer)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.catalog_https_array_valid_v2(text[],integer)', 'EXECUTE'),
  'runtime role cannot invoke internal catalog validators'
);
select ok(
  not has_function_privilege('catalog_writer_v2', 'public.begin_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.read_catalog_reconciliation_page_v2(uuid,text,integer)', 'EXECUTE')
  and not has_function_privilege('catalog_writer_v2', 'public.dispose_catalog_reconciliation_snapshot_v2(uuid)', 'EXECUTE'),
  'runtime role cannot execute private reconciliation operations'
);
select ok(
  not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('catalog_writer_v2', p.oid, 'EXECUTE')
      and p.oid not in (
        'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
        'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
      )
  ), 'the two catalog writers are the only public SECURITY DEFINER functions executable by the executor role'
);
select ok(
  (select count(*) = 2 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and has_function_privilege('catalog_writer_v2_login', p.oid, 'EXECUTE')
     and p.oid in (
       'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
       'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
     ))
  and not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and has_function_privilege('catalog_writer_v2_login', p.oid, 'EXECUTE')
      and p.oid not in (
        'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
        'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
      )
  ), 'LOGIN inherits only the two intended SECURITY DEFINER writer functions'
);
select ok(
  has_schema_privilege('catalog_writer_v2', 'public', 'USAGE')
  and not has_schema_privilege('catalog_writer_v2', 'public', 'CREATE')
  and has_schema_privilege('catalog_writer_v2_owner', 'public', 'USAGE')
  and not has_schema_privilege('catalog_writer_v2_owner', 'public', 'CREATE'),
  'runtime and owner roles cannot create objects in the exposed schema'
);
select ok(
  not pg_catalog.pg_has_role('catalog_writer_v2', 'service_role', 'MEMBER')
  and not pg_catalog.pg_has_role('catalog_writer_v2_owner', 'service_role', 'MEMBER')
  and not pg_catalog.pg_has_role('catalog_writer_v2', 'catalog_writer_v2_owner', 'MEMBER'),
  'restricted identities have no privileged role memberships'
);

create function pg_temp.writer_role_projection(p_id text, p_version bigint, p_operation text)
returns jsonb language sql immutable set search_path = ''
as $function$
  select pg_catalog.jsonb_build_object(
    'id', p_id, 'content_kind', 'establishment', 'category_group', 'commerce',
    'name', 'Role Fixture', 'summary', 'Synthetic restricted role fixture',
    'category', 'Comércio', 'subcategory', 'Fixture', 'location', null,
    'artwork', 0, 'image_url', '', 'logo_url', '', 'gallery_urls', '[]'::jsonb,
    'featured', false, 'is_open', true, 'maps_url', '', 'hours', '',
    'services', '[]'::jsonb, 'products', '[]'::jsonb, 'additional_info', '',
    'promotion_title', '', 'promotion_description', '', 'public_contact_approved', false,
    'phone', null, 'whatsapp', null, 'instagram', null,
    'published', true, 'active', true, 'expires_at', null, 'deleted_at', null,
    'catalog_version', p_version, 'outbox_operation_id', p_operation
  );
$function$;
grant execute on function pg_temp.writer_role_projection(text, bigint, text)
  to catalog_writer_v2, catalog_writer_v2_login, service_role;

-- The grants below exist only inside this test transaction, so the restricted
-- role can emit TAP while permission probes run under SET ROLE. ROLLBACK below
-- removes the test-only access to pgTAP.
grant usage on schema extensions to catalog_writer_v2, catalog_writer_v2_login, catalog_writer_v2_owner, service_role;
set local role catalog_writer_v2_login;
select is(public.apply_establishment_projection_v2(
  pg_temp.writer_role_projection('modelo-role-login-v2', 1, '72000000-0000-4000-8000-000000000006')),
  'applied', 'LOGIN identity executes the projection through inherited executor permission');
select ok(
  not pg_catalog.pg_has_role('catalog_writer_v2_login', 'catalog_writer_v2_owner', 'MEMBER'),
  'LOGIN has no membership that would permit SET ROLE to the SECURITY DEFINER owner'
);
select ok(
  not has_table_privilege('catalog_writer_v2_login', 'public.public_establishment_catalog_v2', 'SELECT')
  and not has_table_privilege('catalog_writer_v2_login', 'public.catalog_tombstones_v2', 'SELECT'),
  'LOGIN has no direct SELECT privilege despite inheriting writer RPC permission'
);
set local role catalog_writer_v2;
select is(public.apply_establishment_tombstone_v2(
  '{"id":"modelo-role-login-deleted","catalog_version":1,"outbox_operation_id":"72000000-0000-4000-8000-000000000007","deleted_at":"2026-10-22T12:00:00Z"}'::jsonb),
  'applied', 'member can SET ROLE to the non-login executor for the tombstone RPC');
reset role;
set local role service_role;
select is(public.apply_establishment_projection_v2(
  pg_temp.writer_role_projection('modelo-role-legacy-compat', 1, '72000000-0000-4000-8000-000000000008')),
  'applied', 'legacy service_role writer remains usable during phased preparation');
reset role;
set local role catalog_writer_v2;
select is(public.apply_establishment_projection_v2(
  pg_temp.writer_role_projection('modelo-role-v2', 1, '72000000-0000-4000-8000-000000000001')),
  'applied', 'restricted role applies an allowlisted projection');
select is(public.apply_establishment_projection_v2(
  pg_temp.writer_role_projection('modelo-role-v2', 1, '72000000-0000-4000-8000-000000000001')),
  'replayed', 'restricted role replays the same projection idempotently');
select is(public.apply_establishment_tombstone_v2(
  '{"id":"modelo-role-deleted","catalog_version":2,"outbox_operation_id":"72000000-0000-4000-8000-000000000002","deleted_at":"2026-10-22T12:00:00Z"}'::jsonb),
  'applied', 'restricted role applies a permanent tombstone');
select is(public.apply_establishment_tombstone_v2(
  '{"id":"modelo-role-deleted","catalog_version":2,"outbox_operation_id":"72000000-0000-4000-8000-000000000002","deleted_at":"2026-10-22T12:00:00Z"}'::jsonb),
  'replayed', 'restricted role replays the same tombstone idempotently');
select throws_ok($$select public.apply_establishment_projection_v2(
  pg_temp.writer_role_projection('modelo-role-deleted', 3, '72000000-0000-4000-8000-000000000003'))$$,
  '23514', null, 'tombstone rejects a later projection');
select throws_ok($$select public.apply_establishment_projection_v2('{}'::jsonb)$$,
  '22023', null, 'writer rejects malformed payload through its existing allowlist');
select throws_ok($$select count(*) from public.public_establishment_catalog_v2$$,
  '42501', null, 'runtime role is denied direct SELECT on the projection');
select throws_ok($$insert into public.public_establishment_catalog_v2
  (id,name,category,content_kind,category_group,catalog_version,outbox_operation_id)
  values ('forbidden','x','Comércio','establishment','commerce',1,'72000000-0000-4000-8000-000000000004')$$,
  '42501', null, 'runtime role is denied direct INSERT on the projection');
select throws_ok($$update public.public_establishment_catalog_v2 set name = 'x' where id = 'modelo-role-v2'$$,
  '42501', null, 'runtime role is denied direct UPDATE on the projection');
select throws_ok($$delete from public.public_establishment_catalog_v2 where id = 'modelo-role-v2'$$,
  '42501', null, 'runtime role is denied direct DELETE on the projection');
select throws_ok($$select count(*) from public.catalog_tombstones_v2$$,
  '42501', null, 'runtime role is denied direct SELECT on tombstones');
select throws_ok($$insert into public.catalog_tombstones_v2
  (id,catalog_version,outbox_operation_id,tombstoned_at)
  values ('forbidden',1,'72000000-0000-4000-8000-000000000005',statement_timestamp())$$,
  '42501', null, 'runtime role is denied direct INSERT on tombstones');
select throws_ok($$update public.catalog_tombstones_v2 set catalog_version = catalog_version + 1
  where id = 'modelo-role-deleted'$$,
  '42501', null, 'runtime role is denied direct UPDATE on tombstones');
select throws_ok($$delete from public.catalog_tombstones_v2 where id = 'modelo-role-deleted'$$,
  '42501', null, 'runtime role is denied direct DELETE on tombstones');
reset role;

set local role catalog_writer_v2_owner;
select throws_ok($$update public.catalog_tombstones_v2 set catalog_version = catalog_version + 1
  where id = 'modelo-role-deleted'$$,
  '23514', null, 'function owner row-lock privilege cannot mutate an immutable tombstone');
reset role;

select * from finish();
rollback;
