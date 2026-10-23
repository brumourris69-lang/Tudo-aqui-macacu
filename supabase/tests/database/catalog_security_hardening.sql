begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(48);

insert into public.public_search_establishments
  (id, name, summary, category, subcategory, image_url, published, active,
   expires_at, deleted_at)
values
  ('pilot-et03-current', 'Estabelecimento atual etapa três',
   'marcadorcatalogoetapa tres', 'Comércio', '', '', true, true, null, null),
  ('pilot-et03-expired', 'Estabelecimento expirado etapa três',
   'marcadorcatalogoetapa tres', 'Comércio', '', '', true, true,
   transaction_timestamp() - interval '1 second', null),
  ('pilot-et03-deleted', 'Estabelecimento excluido etapa três',
   'marcadorcatalogoetapa tres', 'Comércio', '', '', true, true, null,
   transaction_timestamp()),
  ('pilot-et03-unpublished', 'Estabelecimento nao publicado etapa tres',
   'marcadorcatalogoetapa tres', 'Comércio', '', '', false, true, null, null),
  ('pilot-et03-inactive', 'Estabelecimento inativo etapa três',
   'marcadorcatalogoetapa tres', 'Comércio', '', '', true, false, null, null);

insert into public.public_search_establishments
  (id, name, summary, category, subcategory, image_url, published, active)
select 'pilot-et03-page-' || lpad(n::text, 2, '0'),
  'Registro de paginação etapa três', 'marcadorpaginacaoetapa',
  'Comércio', '', '', true, true
from generate_series(1, 21) as n;

select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.public_search_establishments'::regclass),
  'catalog table keeps row-level security enabled'
);
select ok(
  (select relforcerowsecurity from pg_class
   where oid = 'public.public_search_establishments'::regclass),
  'catalog table keeps row-level security forced'
);
select ok(
  not exists (
    select 1 from pg_policy
    where polrelid = 'public.public_search_establishments'::regclass
  ),
  'no table policy remains that could re-open direct catalog access'
);
select ok(
  not has_table_privilege('anon', 'public.public_search_establishments', 'select'),
  'anon has no direct table read grant'
);
select ok(
  not has_table_privilege('authenticated', 'public.public_search_establishments', 'select'),
  'authenticated has no direct table read grant'
);
select ok(
  not has_table_privilege('anon', 'public.public_search_establishments', 'insert')
  and not has_table_privilege('anon', 'public.public_search_establishments', 'update')
  and not has_table_privilege('anon', 'public.public_search_establishments', 'delete'),
  'anon has no direct write grants'
);
select ok(
  not has_table_privilege('authenticated', 'public.public_search_establishments', 'insert')
  and not has_table_privilege('authenticated', 'public.public_search_establishments', 'update')
  and not has_table_privilege('authenticated', 'public.public_search_establishments', 'delete'),
  'authenticated has no direct write grants'
);
select ok(
  not has_column_privilege('anon', 'public.public_search_establishments', 'published', 'select')
  and not has_column_privilege('anon', 'public.public_search_establishments', 'active', 'select')
  and not has_column_privilege('anon', 'public.public_search_establishments', 'expires_at', 'select')
  and not has_column_privilege('anon', 'public.public_search_establishments', 'deleted_at', 'select'),
  'anon cannot read publication, activity, expiry or deletion controls'
);
select ok(
  not has_column_privilege('authenticated', 'public.public_search_establishments', 'id', 'select')
  and not has_column_privilege('authenticated', 'public.public_search_establishments', 'name', 'select'),
  'authenticated cannot read catalog columns directly'
);

select ok(
  not exists (
    select 1
    from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = 'public.search_public_establishments(text,text,integer,text)'::regprocedure
      and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute grant on search RPC'
);
select ok(
  not exists (
    select 1
    from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid = 'public.get_public_establishment(text)'::regprocedure
      and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute grant on detail RPC'
);
select ok(
  has_function_privilege('anon',
    'public.search_public_establishments(text,text,integer,text)', 'execute'),
  'anon retains execute access to search RPC'
);
select ok(
  has_function_privilege('anon', 'public.get_public_establishment(text)', 'execute'),
  'anon retains execute access to detail RPC'
);
select ok(
  not has_function_privilege('authenticated',
    'public.search_public_establishments(text,text,integer,text)', 'execute'),
  'authenticated does not receive an unapproved search RPC grant'
);
select ok(
  not has_function_privilege('authenticated',
    'public.get_public_establishment(text)', 'execute'),
  'authenticated does not receive an unapproved detail RPC grant'
);
select ok(
  not has_function_privilege('anon', 'public.search_pilot_unaccent(text)', 'execute')
  and not has_function_privilege('anon',
    'public.search_pilot_document_text(text,text,text,text)', 'execute'),
  'anon cannot execute internal catalog helper functions'
);
select ok(
  not has_function_privilege('authenticated', 'public.search_pilot_unaccent(text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.search_pilot_document_text(text,text,text,text)', 'execute'),
  'authenticated cannot execute internal catalog helper functions'
);

select ok(
  (select prosecdef from pg_proc
   where oid = 'public.search_public_establishments(text,text,integer,text)'::regprocedure),
  'search RPC uses SECURITY DEFINER'
);
select ok(
  (select prosecdef from pg_proc
   where oid = 'public.get_public_establishment(text)'::regprocedure),
  'detail RPC uses SECURITY DEFINER'
);
select is(
  (select pg_get_userbyid(proowner) from pg_proc
   where oid = 'public.search_public_establishments(text,text,integer,text)'::regprocedure),
  'postgres',
  'search RPC has the explicit postgres owner'
);
select is(
  (select pg_get_userbyid(proowner) from pg_proc
   where oid = 'public.get_public_establishment(text)'::regprocedure),
  'postgres',
  'detail RPC has the explicit postgres owner'
);
select ok(
  (select coalesce(proconfig, '{}') @> array['search_path=""']
   from pg_proc
   where oid = 'public.search_public_establishments(text,text,integer,text)'::regprocedure),
  'search RPC pins an empty search_path'
);
select ok(
  (select coalesce(proconfig, '{}') @> array['search_path=""']
   from pg_proc
   where oid = 'public.get_public_establishment(text)'::regprocedure),
  'detail RPC pins an empty search_path'
);
select is(
  pg_get_function_result(
    'public.search_public_establishments(text,text,integer,text)'::regprocedure
  ),
  'TABLE(id text, name text, summary text, category text, subcategory text, '
    || 'image_url text, has_more boolean)',
  'search RPC preserves the Flutter response projection'
);
select is(
  pg_get_function_result('public.get_public_establishment(text)'::regprocedure),
  'TABLE(id text, name text, summary text, category text, subcategory text, image_url text)',
  'detail RPC preserves the Flutter response projection'
);
select ok(
  position('EXECUTE ' in upper(pg_get_functiondef(
    'public.search_public_establishments(text,text,integer,text)'::regprocedure
  ))) = 0,
  'search RPC contains no dynamic SQL execution'
);
select ok(
  position('EXECUTE ' in upper(pg_get_functiondef(
    'public.get_public_establishment(text)'::regprocedure
  ))) = 0,
  'detail RPC contains no dynamic SQL execution'
);

set local role anon;
select throws_ok(
  $$select count(*) from public.public_search_establishments$$,
  '42501', null, 'anon direct table SELECT is denied'
);
select throws_ok(
  $$insert into public.public_search_establishments
    (id, name, category) values ('pilot-et03-forbidden', 'Forbidden', 'Comércio')$$,
  '42501', null, 'anon direct INSERT is denied'
);
select throws_ok(
  $$update public.public_search_establishments set name = 'Forbidden'$$,
  '42501', null, 'anon direct UPDATE is denied'
);
select throws_ok(
  $$delete from public.public_search_establishments$$,
  '42501', null, 'anon direct DELETE is denied'
);
select is(
  (select count(*)::integer
   from public.search_public_establishments('marcadorcatalogoetapa', 'all', 20, null)),
  1,
  'search excludes expired, deleted, unpublished and inactive records'
);
select is(
  (select count(*)::integer
   from public.get_public_establishment('pilot-et03-current')),
  1,
  'detail returns the currently published record by stable ID'
);
select is(
  (select count(*)::integer
   from public.get_public_establishment('pilot-et03-expired')),
  0,
  'detail excludes an expired record'
);
select is(
  (select count(*)::integer
   from public.get_public_establishment('pilot-et03-deleted')),
  0,
  'detail excludes a soft-deleted record'
);
select is(
  (select count(*)::integer
   from public.get_public_establishment('pilot-et03-unpublished')),
  0,
  'detail excludes an unpublished record'
);
select is(
  (select count(*)::integer
   from public.get_public_establishment('pilot-et03-inactive')),
  0,
  'detail excludes an inactive record'
);
select is(
  (select count(*)::integer
   from public.search_public_establishments('marcadorpaginacaoetapa', 'all', 2, null)),
  2,
  'search pagination respects the requested bounded page size'
);
select ok(
  (select bool_and(has_more)
   from public.search_public_establishments('marcadorpaginacaoetapa', 'all', 2, null)),
  'first bounded page signals more matching public records'
);
select is(
  (select count(*)::integer
   from public.search_public_establishments(
     'marcadorpaginacaoetapa', 'all', 2,
     (select id from public.search_public_establishments(
       'marcadorpaginacaoetapa', 'all', 2, null
     ) order by id desc limit 1)
   )),
  2,
  'validated cursor returns the next bounded page'
);
select ok(
  not exists (
    with first_page as (
      select id from public.search_public_establishments(
        'marcadorpaginacaoetapa', 'all', 2, null
      )
    ), second_page as (
      select id from public.search_public_establishments(
        'marcadorpaginacaoetapa', 'all', 2,
        (select id from first_page order by id desc limit 1)
      )
    )
    select 1 from first_page join second_page using (id)
  ),
  'cursor pagination does not repeat first-page results'
);
select throws_ok(
  $$select * from public.search_public_establishments(
    'marcadorpaginacaoetapa', 'all', 2, 'pilot-et03-no-such-row'
  )$$,
  '22023', null, 'cursor for a nonexistent row is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments(
    'differentquery', 'all', 2,
    (select id from public.search_public_establishments(
      'marcadorpaginacaoetapa', 'all', 2, null
    ) limit 1)
  )$$,
  '22023', null, 'cursor bound to another query is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments(
    'marcadorpaginacaoetapa', 'all', 21, null
  )$$,
  '22023', null, 'page size above the public maximum is rejected'
);

reset role;
set local role authenticated;
select throws_ok(
  $$select count(*) from public.public_search_establishments$$,
  '42501', null, 'authenticated direct table SELECT is denied'
);
select throws_ok(
  $$insert into public.public_search_establishments
    (id, name, category) values ('pilot-et03-auth-forbidden', 'Forbidden', 'Comércio')$$,
  '42501', null, 'authenticated direct INSERT is denied'
);
select throws_ok(
  $$update public.public_search_establishments set name = 'Forbidden'$$,
  '42501', null, 'authenticated direct UPDATE is denied'
);
select throws_ok(
  $$delete from public.public_search_establishments$$,
  '42501', null, 'authenticated direct DELETE is denied'
);

reset role;
select * from finish();
rollback;
