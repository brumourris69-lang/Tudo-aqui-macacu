-- Manual cutover only. This file is outside supabase/migrations so applying
-- preparation migrations cannot revoke the current consumer's service_role.
-- Run only after the replacement consumer has passed end-to-end PostgreSQL and
-- Firestore tests, its LOGIN secret is provisioned out-of-band, and no other
-- writer depends on service_role. This file does not provision or read secrets.
begin;

do $preconditions$
begin
  if not exists (
    select 1 from pg_catalog.pg_roles
    where rolname = 'catalog_writer_v2_login'
      and rolcanlogin and rolinherit and not rolsuper and not rolcreatedb
      and not rolcreaterole and not rolreplication and not rolbypassrls
      and rolconnlimit = 2
  ) then
    raise exception 'restricted LOGIN role is absent or has unsafe attributes';
  end if;

  if not pg_catalog.pg_has_role('catalog_writer_v2_login', 'catalog_writer_v2', 'MEMBER')
    or pg_catalog.pg_has_role('catalog_writer_v2_login', 'catalog_writer_v2_owner', 'MEMBER')
    or pg_catalog.pg_has_role('catalog_writer_v2_login', 'service_role', 'MEMBER') then
    raise exception 'restricted LOGIN memberships do not match the approved executor';
  end if;

  if not pg_catalog.has_database_privilege(
      'catalog_writer_v2_login', pg_catalog.current_database(), 'CONNECT'
    ) then
    raise exception 'restricted LOGIN cannot connect to the current database';
  end if;

  if not pg_catalog.has_function_privilege(
      'catalog_writer_v2_login',
      'public.apply_establishment_projection_v2(jsonb)',
      'EXECUTE'
    ) or not pg_catalog.has_function_privilege(
      'catalog_writer_v2_login',
      'public.apply_establishment_tombstone_v2(jsonb)',
      'EXECUTE'
    ) then
    raise exception 'restricted LOGIN does not inherit both approved writer RPCs';
  end if;

  if pg_catalog.has_schema_privilege('catalog_writer_v2_login', 'public', 'CREATE')
    or pg_catalog.has_schema_privilege('catalog_writer_v2', 'public', 'CREATE')
    or pg_catalog.has_schema_privilege('catalog_writer_v2_owner', 'public', 'CREATE') then
    raise exception 'restricted identities can create objects in public';
  end if;

  if exists (
    select 1 from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname <> 'information_schema' and n.nspname not like 'pg\_%' escape '\'
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
  ) then
    raise exception 'writer identities have table privileges outside the allowlisted catalog objects';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
      and pg_catalog.has_function_privilege('catalog_writer_v2_login', p.oid, 'EXECUTE')
      and p.oid not in (
        'public.apply_establishment_projection_v2(jsonb)'::regprocedure,
        'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
      )
  ) then
    raise exception 'restricted LOGIN can execute an unrelated public SECURITY DEFINER function';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.apply_establishment_projection_v2(jsonb)'::regprocedure
      and p.prosecdef and pg_catalog.pg_get_userbyid(p.proowner) = 'catalog_writer_v2_owner'
      and p.proconfig @> array['search_path=""']
  ) or not exists (
    select 1 from pg_catalog.pg_proc p
    where p.oid = 'public.apply_establishment_tombstone_v2(jsonb)'::regprocedure
      and p.prosecdef and pg_catalog.pg_get_userbyid(p.proowner) = 'catalog_writer_v2_owner'
      and p.proconfig @> array['search_path=""']
  ) then
    raise exception 'writer SECURITY DEFINER ownership or search_path is unsafe';
  end if;
end;
$preconditions$;

revoke all on function public.apply_establishment_projection_v2(jsonb) from service_role;
revoke all on function public.apply_establishment_tombstone_v2(jsonb) from service_role;

do $postconditions$
begin
  if pg_catalog.has_function_privilege(
      'service_role', 'public.apply_establishment_projection_v2(jsonb)', 'EXECUTE'
    ) or pg_catalog.has_function_privilege(
      'service_role', 'public.apply_establishment_tombstone_v2(jsonb)', 'EXECUTE'
    ) then
    raise exception 'legacy service_role writer access remains after cutover';
  end if;
end;
$postconditions$;

commit;
