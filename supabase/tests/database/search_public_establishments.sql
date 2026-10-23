begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(28);

insert into public.public_search_establishments
  (id, name, summary, category, subcategory, image_url, published, active)
values
  ('pilot-test-unpublished', 'Exemplo Oculto Publicado', 'fixture oculta', 'Comércio', '', '', false, true),
  ('pilot-test-inactive', 'Exemplo Oculto Inativo', 'fixture inativa', 'Serviços', '', '', true, false)
on conflict (id) do nothing;

select is(
  (select array_agg(column_name::text order by ordinal_position)
   from information_schema.columns
   where table_schema = 'public' and table_name = 'public_search_establishments'),
  array[
    'id', 'name', 'summary', 'category', 'subcategory', 'image_url',
    'published', 'active', 'expires_at', 'deleted_at'
  ]::text[],
  'table schema contains the approved pilot fields and lifecycle controls'
);
select is(
  (select provolatile::text from pg_proc
   where oid = 'public.search_pilot_document_text(text,text,text,text)'::regprocedure),
  'i',
  'document text helper is declared immutable for expression indexing'
);
select is(
  (select provolatile::text from pg_proc
   where oid = 'public.search_pilot_unaccent(text)'::regprocedure),
  'i',
  'accent normalization helper is declared immutable for expression indexing'
);

set local role anon;

select throws_ok(
  $$select count(*) from public.public_search_establishments$$,
  '42501', null, 'anonymous direct SELECT is denied'
);
select ok(
  not has_table_privilege('anon', 'public.public_search_establishments', 'select')
  and not has_table_privilege('authenticated', 'public.public_search_establishments', 'select')
  and not has_column_privilege('anon', 'public.public_search_establishments', 'id', 'select')
  and not has_column_privilege('authenticated', 'public.public_search_establishments', 'id', 'select'),
  'anonymous and authenticated roles have no direct table or column SELECT grants'
);
select ok(
  not has_column_privilege('anon', 'public.public_search_establishments', 'published', 'select')
  and not has_column_privilege('anon', 'public.public_search_establishments', 'active', 'select'),
  'anonymous role cannot read publication control columns directly'
);
select is(
  (select count(*)::integer from public.search_public_establishments('exemplo', 'all', 20, null)),
  3,
  'search returns all matching published and active fixtures'
);
select is(
  (select count(*)::integer from public.search_public_establishments('exemplo', 'commerce', 20, null)),
  2,
  'commerce filter follows the approved category allowlist'
);
select is(
  (select count(*)::integer from public.search_public_establishments('exemplo', 'services', 20, null)),
  1,
  'services filter follows the approved category allowlist'
);
select throws_ok(
  $$select * from public.search_public_establishments('exemplo', 'unsupported', 10, null)$$,
  '22023', null, 'unsupported category is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('exemplo', 'all', 0, null)$$,
  '22023', null, 'page size below one is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('exemplo', 'all', 21, null)$$,
  '22023', null, 'page size above twenty is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('', 'all', 10, null)$$,
  '22023', null, 'empty search query is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments(repeat('a', 81), 'all', 10, null)$$,
  '22023', null, 'search query longer than eighty characters is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('a b c d e', 'all', 10, null)$$,
  '22023', null, 'more than four search terms are rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('x', 'all', 10, null)$$,
  '22023', null, 'terms shorter than two characters are rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments(repeat('a', 25), 'all', 10, null)$$,
  '22023', null, 'terms longer than twenty-four characters are rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments('exemplo', 'all', 10, 'not-a-pilot-id')$$,
  '22023', null, 'malformed cursor is rejected'
);
select ok(
  (select bool_and(has_more) from public.search_public_establishments('exemplo', 'all', 1, null)),
  'first page indicates more results when another page exists'
);
select ok(
  (with first_page as (
    select id from public.search_public_establishments('exemplo', 'all', 1, null)
  ), second_page as (
    select id from public.search_public_establishments(
      'exemplo', 'all', 1, (select id from first_page)
    )
  ) select count(*) = 1 from second_page),
  'cursor continues with one result'
);
select ok(
  (with first_page as (
    select id from public.search_public_establishments('exemplo', 'all', 1, null)
  ), second_page as (
    select id from public.search_public_establishments(
      'exemplo', 'all', 1, (select id from first_page)
    )
  ) select not exists (select 1 from first_page join second_page using (id))),
  'cursor does not duplicate the previous result'
);
select throws_ok(
  $$select * from public.search_public_establishments(
    'oculto', 'all', 10, (select id from public.search_public_establishments('exemplo', 'all', 1, null))
  )$$,
  '22023', null, 'cursor from a different query is rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments(
    'exemplo', 'services', 10, (select id from public.search_public_establishments('exemplo', 'commerce', 1, null))
  )$$,
  '22023', null, 'cursor from a different category is rejected'
);
select is(
  (select count(*)::integer from public.search_public_establishments('oculto', 'all', 20, null)),
  0,
  'unpublished and inactive records are absent from search'
);
select is(
  (select count(*)::integer from public.get_public_establishment('pilot-test-unpublished')),
  0,
  'unpublished detail is unavailable'
);
select is(
  (select count(*)::integer from public.get_public_establishment('pilot-test-inactive')),
  0,
  'inactive detail is unavailable'
);
select is(
  (select count(*)::integer from public.get_public_establishment('pilot-cafe-exemplo')),
  1,
  'published detail is available by its stable ID'
);
select throws_ok(
  $$select * from public.get_public_establishment('invalid-id')$$,
  '22023', null, 'malformed detail ID is rejected'
);

reset role;
select * from finish();
rollback;
