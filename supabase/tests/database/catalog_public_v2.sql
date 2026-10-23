begin;

create extension if not exists pgtap with schema extensions;
set local search_path = extensions, public;
select plan(93);

insert into public.public_establishment_catalog_v2 (
  id, name, summary, category, content_kind, category_group, subcategory,
  location, public_contact_approved, published, active,
  catalog_version, outbox_operation_id
)
select
  'v2-category-' || lpad(category_order::text, 2, '0'),
  'CatalogToken Fixture ' || lpad(category_order::text, 2, '0') || ' ' || category,
  'catalogtoken descrição pública para a matriz v2',
  category,
  case when category in (
    'Empregos', 'Turismo', 'Notícias', 'Eventos', 'Promoções', 'Serviços úteis'
  ) then 'other_content' else 'establishment' end,
  case
    when category in (
      'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
      'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia'
    ) then 'commerce'
    when category in ('Serviços', 'Profissionais') then 'services'
    else 'other'
  end,
  'Teste',
  'Cachoeiras de Macacu',
  false,
  true,
  true,
  1,
  ('00000000-0000-4000-8000-' || lpad(category_order::text, 12, '0'))::uuid
from (values
  (1, 'Comércio'), (2, 'Onde comer?'), (3, 'Serviços'), (4, 'Profissionais'),
  (5, 'Empregos'), (6, 'Turismo'), (7, 'Notícias'), (8, 'Eventos'),
  (9, 'Saúde'), (10, 'Imóveis'), (11, 'Veículos'), (12, 'Pets'),
  (13, 'Beleza'), (14, 'Academias'), (15, 'Educação'), (16, 'Hospedagem'),
  (17, 'Promoções'), (18, 'Serviços úteis'), (19, 'Tecnologia')
) as categories(category_order, category);

insert into public.public_establishment_catalog_v2 (
  id, name, summary, category, content_kind, category_group, subcategory,
  location, public_contact_approved, phone, whatsapp, instagram, published,
  active, catalog_version, outbox_operation_id
)
values
  ('modelo-legacy-7', 'Legacy model ID', E'Descrição v2\nLinha dois', 'Serviços',
   'establishment', 'services', 'Eletricista', 'Centro', true,
   '+55 (22) 99999-0000', '5522999990000', '@legacy.profile',
   true, true, 1, '10000000-0000-4000-8000-000000000001'),
  ('aBcDeFgHiJkLmNoPqRsT', 'Firestore auto ID', 'Descrição v2', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, true, 1, '10000000-0000-4000-8000-000000000002'),
  ('__id42__', 'Datastore imported ID', 'Descrição v2', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, true, 1, '10000000-0000-4000-8000-000000000003'),
  ('id with spaces', 'Firestore legal ID with spaces', 'Descrição v2', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, true, 1, '10000000-0000-4000-8000-000000000004'),
  ('Macacu-Á', 'Firestore UTF-8 ID', 'Descrição v2', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, true, 1, '10000000-0000-4000-8000-000000000005'),
  ('v2-hidden-unpublished', 'Oculto unpublished', 'fixture', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   false, true, 1, '10000000-0000-4000-8000-000000000006'),
  ('v2-hidden-inactive', 'Oculto inactive', 'fixture', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, false, 1, '10000000-0000-4000-8000-000000000007'),
  ('v2-hidden-expired', 'Oculto expired', 'fixture', 'Comércio',
   'establishment', 'commerce', '', null, false, null, null, null,
   true, true, 1, '10000000-0000-4000-8000-000000000008');

update public.public_establishment_catalog_v2
set expires_at = statement_timestamp() - interval '1 second',
    catalog_version = 2,
    outbox_operation_id = '10000000-0000-4000-8000-000000000011'
where id = 'v2-hidden-expired';

insert into public.public_establishment_catalog_v2 (
  id, name, summary, category, content_kind, category_group,
  published, active, catalog_version, outbox_operation_id
)
values ('v2-soft-delete', 'Tombstone fixture', 'fixture', 'Comércio',
  'establishment', 'commerce', true, true, 1,
  '10000000-0000-4000-8000-000000000009');

update public.public_establishment_catalog_v2
set deleted_at = statement_timestamp(),
    catalog_version = 2,
    outbox_operation_id = '10000000-0000-4000-8000-000000000010'
where id = 'v2-soft-delete';

select ok(
  (select count(*) = 19 from public.public_establishment_catalog_v2
   where id like 'v2-category-%'),
  'the complete nineteen-category Admin taxonomy is representable'
);
select ok(
  (select count(*) = 13 from public.public_establishment_catalog_v2
   where id like 'v2-category-%' and content_kind = 'establishment'),
  'thirteen commerce/service categories are classified as establishments'
);
select ok(
  (select count(*) = 6 from public.public_establishment_catalog_v2
   where id like 'v2-category-%' and content_kind = 'other_content'),
  'six non-business categories remain classified as other content'
);
select ok(
  (select count(*) = 0 from public.search_public_establishments_v2(
    'CatalogToken', 'all', 40, null
  ) where category in ('Empregos', 'Turismo', 'Notícias', 'Eventos', 'Promoções', 'Serviços úteis')),
  'establishment search does not return non-business content categories'
);
select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'all', 40, null
  )),
  13,
  'all-category search returns only the thirteen business categories'
);
select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'commerce', 40, null
  )),
  11,
  'commerce grouping matches the existing Flutter search policy'
);
select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'services', 40, null
  )),
  2,
  'services grouping matches the existing Flutter search policy'
);
select throws_ok(
  $$select * from public.search_public_establishments_v2('CatalogToken', 'other', 10, null)$$,
  '22023', null, 'other content is not a public establishment search group'
);

select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-legacy-7')),
  1,
  'importer-style legacy ID is preserved by detail lookup'
);
select is(
  (select summary from public.get_public_establishment_v2('modelo-legacy-7')),
  E'Descrição v2\nLinha dois',
  'multiline public descriptions preserve their line breaks'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('aBcDeFgHiJkLmNoPqRsT')),
  1,
  'Firestore auto-generated ID is preserved by detail lookup'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('__id42__')),
  1,
  'Datastore-import ID exception is preserved'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('id with spaces')),
  1,
  'valid Firestore IDs are not restricted by whitespace or an artificial regex'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('Macacu-Á')),
  1,
  'valid UTF-8 Firestore IDs are preserved exactly'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-category-05')),
  0,
  'detail RPC does not treat a job category as an establishment'
);
select throws_ok(
  $$select * from public.get_public_establishment_v2('bad/id')$$,
  '22023', null, 'IDs containing path separators are rejected'
);
select throws_ok(
  $$select * from public.get_public_establishment_v2('.')$$,
  '22023', null, 'the reserved single-period ID is rejected'
);
select throws_ok(
  $$select * from public.get_public_establishment_v2('__private__')$$,
  '22023', null, 'reserved Firestore IDs are rejected'
);
select throws_ok(
  $$select * from public.get_public_establishment_v2(E'__private\n__')$$,
  '22023', null, 'reserved Firestore IDs remain rejected when their body contains a newline'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, catalog_version, outbox_operation_id)
    values (repeat('é', 751), 'too long ID', 'Comércio', 'establishment', 'commerce',
      1, '20000000-0000-4000-8000-000000000001')$$,
  '23514', null, 'IDs beyond the Firestore UTF-8 byte limit are rejected'
);

select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, catalog_version, outbox_operation_id)
    values ('v2-invalid-category-map', 'bad map', 'Empregos', 'establishment', 'commerce',
      1, '20000000-0000-4000-8000-000000000002')$$,
  '23514', null, 'content categories cannot be mislabeled as establishments'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, public_contact_approved, phone,
     catalog_version, outbox_operation_id)
    values ('v2-contact-unapproved', 'contact', 'Comércio', 'establishment', 'commerce',
      false, '+55 (22) 99999-0000', 1, '20000000-0000-4000-8000-000000000003')$$,
  '23514', null, 'unapproved contacts cannot be stored in the public projection'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, public_contact_approved, phone,
     catalog_version, outbox_operation_id)
    values ('v2-contact-invalid', 'contact', 'Comércio', 'establishment', 'commerce',
      true, 'call me at 123', 1, '20000000-0000-4000-8000-000000000004')$$,
  '23514', null, 'malformed phone contacts are rejected even when approved'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, image_url,
     catalog_version, outbox_operation_id)
    values ('v2-image-invalid', 'image', 'Comércio', 'establishment', 'commerce',
      'javascript:alert(1)', 1, '20000000-0000-4000-8000-000000000005')$$,
  '23514', null, 'non-HTTPS image URLs are rejected'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, services,
     catalog_version, outbox_operation_id)
    values ('v2-services-invalid', 'services', 'Comércio', 'establishment', 'commerce',
      array_fill('x'::text, array[41]), 1, '20000000-0000-4000-8000-000000000006')$$,
  '23514', null, 'service arrays are bounded'
);

select is(
  (select phone from public.get_public_establishment_v2('modelo-legacy-7')),
  '+55 (22) 99999-0000',
  'approved and valid phone is included in the public detail projection'
);
select is(
  (select whatsapp from public.get_public_establishment_v2('modelo-legacy-7')),
  '5522999990000',
  'approved and valid WhatsApp is included in the public detail projection'
);
select is(
  (select instagram from public.get_public_establishment_v2('modelo-legacy-7')),
  '@legacy.profile',
  'approved and valid Instagram is included in the public detail projection'
);
select ok(
  (select phone is null and whatsapp is null and instagram is null
   from public.get_public_establishment_v2('aBcDeFgHiJkLmNoPqRsT')),
  'unapproved contact values are absent from the public projection'
);

select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'all', 1, null
  )),
  1,
  'search page size is applied'
);
select ok(
  (select bool_and(has_more) from public.search_public_establishments_v2(
    'CatalogToken', 'all', 1, null
  )),
  'search first page signals additional matches'
);
select is(
  (select id from public.search_public_establishments_v2(
    'CatalogToken', 'all', 1, null
  )),
  'v2-category-01',
  'search uses deterministic original-ID ordering'
);
select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'all', 1, 'v2-category-01'
  )),
  1,
  'search cursor fetches the following bounded page'
);
select isnt(
  (select id from public.search_public_establishments_v2(
    'CatalogToken', 'all', 1, 'v2-category-01'
  )),
  'v2-category-01',
  'search cursor does not repeat its previous page'
);
select is(
  (select count(*)::integer from public.list_public_establishments_v2('all', 1, null)),
  1,
  'list RPC applies the page bound'
);
select ok(
  (select bool_and(has_more) from public.list_public_establishments_v2('all', 1, null)),
  'list RPC indicates another page'
);
select is(
  (select count(*)::integer from public.list_public_establishments_v2(
    'all', 1, (select id from public.list_public_establishments_v2('all', 1, null))
  )),
  1,
  'name/ID keyset cursor returns the next list page'
);
select throws_ok(
  $$select * from public.search_public_establishments_v2('CatalogToken', 'all', 41, null)$$,
  '22023', null, 'search pages above forty are rejected'
);
select throws_ok(
  $$select * from public.list_public_establishments_v2('all', 0, null)$$,
  '22023', null, 'empty list pages are rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments_v2('ab', 'all', 10, null)$$,
  '22023', null, 'two-character terms are rejected to keep trigram search selective'
);
select throws_ok(
  $$select * from public.search_public_establishments_v2('CatalogToken', 'all', 10, 'bad/id')$$,
  '22023', null, 'malformed search cursor IDs are rejected'
);
select throws_ok(
  $$select * from public.search_public_establishments_v2(
    'differentquery', 'all', 10, 'v2-category-01'
  )$$,
  '22023', null, 'search cursor must match the current query'
);
select throws_ok(
  $$select * from public.list_public_establishments_v2('commerce', 10, 'v2-category-03')$$,
  '22023', null, 'list cursor must belong to the selected category group'
);

select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'Oculto', 'all', 40, null
  )),
  0,
  'unpublished, inactive and expired fixtures are excluded from search'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-hidden-unpublished')),
  0,
  'detail excludes unpublished rows'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-hidden-inactive')),
  0,
  'detail excludes inactive rows'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-hidden-expired')),
  0,
  'detail excludes expired rows'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-soft-delete')),
  0,
  'detail excludes logically deleted rows'
);
select is(
  (select count(*)::integer from public.catalog_tombstones_v2
   where id = 'v2-soft-delete' and catalog_version = 2),
  1,
  'logical deletion creates a versioned tombstone'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, catalog_version, outbox_operation_id)
    values ('v2-soft-delete', 'resurrected old', 'Comércio', 'establishment', 'commerce',
      1, '30000000-0000-4000-8000-000000000001')$$,
  '23514', null, 'old events cannot resurrect a tombstoned ID'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, catalog_version, outbox_operation_id)
    values ('v2-soft-delete', 'resurrected new', 'Comércio', 'establishment', 'commerce',
      99, '30000000-0000-4000-8000-000000000002')$$,
  '23514', null, 'newer events cannot revive a logically deleted ID'
);
select lives_ok(
  $$insert into public.catalog_tombstones_v2
    (id, catalog_version, outbox_operation_id, tombstoned_at)
    select id, catalog_version, outbox_operation_id, tombstoned_at
    from public.catalog_tombstones_v2 where id = 'v2-soft-delete'$$,
  'an exact tombstone replay is idempotent'
);
select is(
  (select count(*)::integer from public.catalog_tombstones_v2 where id = 'v2-soft-delete'),
  1,
  'tombstone replay does not duplicate its marker'
);
select throws_ok(
  $$delete from public.public_establishment_catalog_v2 where id = 'v2-category-01'$$,
  '23514', null, 'projection rows cannot be physically deleted outside tombstone flow'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('v2-category-01')),
  1,
  'a rejected physical delete leaves the canonical projection row intact'
);
select throws_ok(
  $$delete from public.catalog_tombstones_v2 where id = 'v2-soft-delete'$$,
  '23514', null, 'versioned tombstones are immutable and cannot be removed'
);
select throws_ok(
  $$update public.public_establishment_catalog_v2
    set catalog_version = 1,
        outbox_operation_id = '30000000-0000-4000-8000-000000000003'
    where id = 'modelo-legacy-7'$$,
  '23514', null, 'catalog versions cannot stay the same'
);
select lives_ok(
  $$update public.public_establishment_catalog_v2
    set catalog_version = 4, outbox_operation_id = '30000000-0000-4000-8000-000000000004'
    where id = 'modelo-legacy-7'$$,
  'version jumps are allowed while monotonicity remains strict'
);
select lives_ok(
  $$update public.public_establishment_catalog_v2
    set catalog_version = 4, outbox_operation_id = '30000000-0000-4000-8000-000000000004'
    where id = 'modelo-legacy-7'$$,
  'an exact version and operation replay is idempotent'
);
select is(
  (select catalog_version::integer from public.public_establishment_catalog_v2
   where id = 'modelo-legacy-7'),
  4,
  'an exact replay does not change the projection version'
);
select throws_ok(
  $$update public.public_establishment_catalog_v2
    set name = 'tampered replay' where id = 'modelo-legacy-7'$$,
  '23514', null, 'a conflicting payload cannot reuse a prior version and operation ID'
);
select throws_ok(
  $$update public.catalog_tombstones_v2
    set catalog_version = 99 where id = 'v2-soft-delete'$$,
  '23514', null, 'versioned tombstones cannot be edited'
);
select lives_ok(
  $$update public.public_establishment_catalog_v2
    set published = false, catalog_version = 5,
        outbox_operation_id = '30000000-0000-4000-8000-000000000005'
    where id = 'modelo-legacy-7'$$,
  'unpublishing is a reversible versioned state, distinct from tombstoning'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-legacy-7')),
  0,
  'unpublished record is not public'
);
select lives_ok(
  $$update public.public_establishment_catalog_v2
    set published = true, catalog_version = 6,
        outbox_operation_id = '30000000-0000-4000-8000-000000000006'
    where id = 'modelo-legacy-7'$$,
  'a newer version can republish a row that was only unpublished'
);
select is(
  (select count(*)::integer from public.get_public_establishment_v2('modelo-legacy-7')),
  1,
  'republished row becomes public after version advancement'
);

select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.public_establishment_catalog_v2'::regclass),
  'V2 catalog enables RLS'
);
select ok(
  (select relforcerowsecurity from pg_class
   where oid = 'public.public_establishment_catalog_v2'::regclass),
  'V2 catalog forces RLS'
);
select ok(
  (select relrowsecurity from pg_class
   where oid = 'public.catalog_tombstones_v2'::regclass)
  and (select relforcerowsecurity from pg_class
   where oid = 'public.catalog_tombstones_v2'::regclass),
  'tombstones enable and force RLS'
);
select is(
  (select count(*)::integer from pg_policy p
   where p.polrelid in (
     'public.public_establishment_catalog_v2'::regclass,
     'public.catalog_tombstones_v2'::regclass
   )
   and (
     0::oid = any(p.polroles)
     or (select oid from pg_roles where rolname = 'anon') = any(p.polroles)
     or (select oid from pg_roles where rolname = 'authenticated') = any(p.polroles)
   )),
  0,
  'no client-target policies exist on either V2 table'
);
select ok(
  not has_table_privilege('anon', 'public.public_establishment_catalog_v2', 'select')
  and not has_table_privilege('authenticated', 'public.public_establishment_catalog_v2', 'select'),
  'clients have no direct SELECT grant on the V2 catalog'
);
select ok(
  not has_table_privilege('anon', 'public.catalog_tombstones_v2', 'select')
  and not has_table_privilege('authenticated', 'public.catalog_tombstones_v2', 'select'),
  'clients cannot read versioned tombstones'
);
select ok(
  not has_table_privilege('anon', 'public.public_establishment_catalog_v2', 'insert')
  and not has_table_privilege('anon', 'public.public_establishment_catalog_v2', 'update')
  and not has_table_privilege('anon', 'public.public_establishment_catalog_v2', 'delete'),
  'anon has no direct V2 catalog writes'
);
select ok(
  not has_table_privilege('authenticated', 'public.catalog_tombstones_v2', 'insert')
  and not has_table_privilege('authenticated', 'public.catalog_tombstones_v2', 'update')
  and not has_table_privilege('authenticated', 'public.catalog_tombstones_v2', 'delete'),
  'authenticated has no direct tombstone writes'
);
select ok(
  not has_table_privilege('authenticated', 'public.public_establishment_catalog_v2', 'insert')
  and not has_table_privilege('authenticated', 'public.public_establishment_catalog_v2', 'update')
  and not has_table_privilege('authenticated', 'public.public_establishment_catalog_v2', 'delete'),
  'authenticated has no direct catalog writes'
);
select ok(
  to_regclass('public.public_establishment_catalog_v2_search_gin') is not null
  and to_regclass('public.public_establishment_catalog_v2_visible_name_idx') is not null
  and to_regclass('public.public_establishment_catalog_v2_list_name_idx') is not null
  and to_regclass('public.public_establishment_catalog_v2_expiry_idx') is not null,
  'search, public-list and expiry indexes are installed'
);
select ok(
  (select bool_and(prosecdef) from pg_proc where oid in (
    'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure,
    'public.list_public_establishments_v2(text,integer,text)'::regprocedure,
    'public.get_public_establishment_v2(text)'::regprocedure
  )),
  'all V2 public RPCs use SECURITY DEFINER'
);
select ok(
  (select bool_and(pg_get_userbyid(proowner) = 'postgres') from pg_proc where oid in (
    'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure,
    'public.list_public_establishments_v2(text,integer,text)'::regprocedure,
    'public.get_public_establishment_v2(text)'::regprocedure
  )),
  'all V2 public RPCs have the explicit postgres owner'
);
select ok(
  (select bool_and(coalesce(proconfig, '{}') @> array['search_path=""'])
   from pg_proc where oid in (
     'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure,
     'public.list_public_establishments_v2(text,integer,text)'::regprocedure,
     'public.get_public_establishment_v2(text)'::regprocedure
   )),
  'all V2 public RPCs pin an empty search_path'
);
select ok(
  not exists (
    select 1 from pg_proc p,
      lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
    where p.oid in (
      'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure,
      'public.list_public_establishments_v2(text,integer,text)'::regprocedure,
      'public.get_public_establishment_v2(text)'::regprocedure
    ) and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
  ),
  'PUBLIC has no execute grant on V2 RPCs'
);
select ok(
  pg_get_function_result(
    'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure
  ) = 'TABLE(id text, name text, summary text, category text, subcategory text, location text, '
      || 'artwork smallint, image_url text, logo_url text, gallery_urls text[], featured boolean, '
      || 'is_open boolean, maps_url text, hours text, services text[], products text[], '
      || 'additional_info text, promotion_title text, promotion_description text, phone text, '
      || 'whatsapp text, instagram text, has_more boolean)'
  and pg_get_function_result(
    'public.list_public_establishments_v2(text,integer,text)'::regprocedure
  ) = 'TABLE(id text, name text, summary text, category text, subcategory text, location text, '
      || 'artwork smallint, image_url text, logo_url text, gallery_urls text[], featured boolean, '
      || 'is_open boolean, maps_url text, hours text, services text[], products text[], '
      || 'additional_info text, promotion_title text, promotion_description text, phone text, '
      || 'whatsapp text, instagram text, has_more boolean)'
  and pg_get_function_result(
    'public.get_public_establishment_v2(text)'::regprocedure
  ) = 'TABLE(id text, name text, summary text, category text, subcategory text, location text, '
      || 'artwork smallint, image_url text, logo_url text, gallery_urls text[], featured boolean, '
      || 'is_open boolean, maps_url text, hours text, services text[], products text[], '
      || 'additional_info text, promotion_title text, promotion_description text, phone text, '
      || 'whatsapp text, instagram text)',
  'V2 RPCs expose only their explicit allowlisted response projections'
);
select ok(
  not exists (
    select 1 from unnest(array[
      'public.search_public_establishments_v2(text,text,integer,text)'::regprocedure,
      'public.list_public_establishments_v2(text,integer,text)'::regprocedure,
      'public.get_public_establishment_v2(text)'::regprocedure
    ]) as functions(oid)
    where position('EXECUTE ' in upper(pg_get_functiondef(oid))) > 0
  ),
  'V2 public RPCs contain no dynamic SQL execution'
);

set local role anon;
select throws_ok(
  $$select * from public.public_establishment_catalog_v2$$,
  '42501', null, 'anon direct catalog SELECT is denied'
);
select throws_ok(
  $$select * from public.catalog_tombstones_v2$$,
  '42501', null, 'anon direct tombstone SELECT is denied'
);
select throws_ok(
  $$insert into public.public_establishment_catalog_v2
    (id, name, category, content_kind, category_group, catalog_version, outbox_operation_id)
    values ('anon-write', 'forbidden', 'Comércio', 'establishment', 'commerce',
      1, '40000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'anon direct projection write is denied'
);
select ok(
  has_function_privilege('anon',
    'public.search_public_establishments_v2(text,text,integer,text)', 'execute')
  and has_function_privilege('anon',
    'public.list_public_establishments_v2(text,integer,text)', 'execute')
  and has_function_privilege('anon', 'public.get_public_establishment_v2(text)', 'execute'),
  'anon can use the three bounded public RPCs'
);
select is(
  (select count(*)::integer from public.search_public_establishments_v2(
    'CatalogToken', 'all', 40, null
  )),
  13,
  'SECURITY DEFINER RPC returns its explicit public projection to anon'
);

reset role;
set local role authenticated;
select throws_ok(
  $$select * from public.public_establishment_catalog_v2$$,
  '42501', null, 'authenticated direct catalog SELECT is denied'
);
select throws_ok(
  $$select * from public.catalog_tombstones_v2$$,
  '42501', null, 'authenticated direct tombstone SELECT is denied'
);
select ok(
  not has_function_privilege('authenticated',
    'public.search_public_establishments_v2(text,text,integer,text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.list_public_establishments_v2(text,integer,text)', 'execute')
  and not has_function_privilege('authenticated',
    'public.get_public_establishment_v2(text)', 'execute'),
  'authenticated receives no RPC or table access beyond the public anon contract'
);

reset role;
select is(
  pg_get_function_result('public.search_public_establishments(text,text,integer,text)'::regprocedure),
  'TABLE(id text, name text, summary text, category text, subcategory text, image_url text, has_more boolean)',
  'V1 search response signature remains unchanged'
);
select is(
  pg_get_function_result('public.get_public_establishment(text)'::regprocedure),
  'TABLE(id text, name text, summary text, category text, subcategory text, image_url text)',
  'V1 detail response signature remains unchanged'
);
select ok(
  has_function_privilege('anon',
    'public.search_public_establishments(text,text,integer,text)', 'execute')
  and has_function_privilege('anon', 'public.get_public_establishment(text)', 'execute'),
  'V1 public RPC grants remain intact'
);

select * from finish();
rollback;
