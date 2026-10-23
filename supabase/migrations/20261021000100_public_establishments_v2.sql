-- Public catalog V2 is additive. V1 tables, functions, grants and fixtures stay intact.
-- Firestore remains canonical; this table is a future public projection only.

create or replace function public.catalog_firestore_id_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select value is not null
    and octet_length(value) between 1 and 1500
    and value not in ('.', '..')
    and position('/' in value) = 0
    -- Firestore reserves __.*__, except Datastore-import IDs exposed as __idN__.
    and (left(value, 2) <> '__' or right(value, 2) <> '__'
      or value ~ '^__id[0-9]+__$');
$function$;

create or replace function public.catalog_https_url_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select value is not null and char_length(value) <= 2048
    and value ~ '^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]{1,5})?([/?#][^[:space:]]*)?$';
$function$;

create or replace function public.catalog_map_url_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select public.catalog_https_url_valid_v2(value)
    or (value is not null and char_length(value) <= 2048
      and value ~ '^geo:-?[0-9]+(\.[0-9]+)?,-?[0-9]+(\.[0-9]+)?(\?[^[:space:]]*)?$');
$function$;

create or replace function public.catalog_phone_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select value is null or (
    char_length(value) <= 64
    and value ~ '^\+?[0-9][0-9 ()().-]{4,30}$'
    and char_length(regexp_replace(value, '[^0-9]', '', 'g')) between 8 and 15
  );
$function$;

create or replace function public.catalog_whatsapp_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select value is null or public.catalog_phone_valid_v2(value)
    or (char_length(value) <= 2048 and value ~ '^https://wa\.me/[0-9]{8,15}/?$');
$function$;

create or replace function public.catalog_instagram_valid_v2(value text)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select value is null or (
    char_length(value) <= 2048
    and (value ~ '^@?[A-Za-z0-9._]{1,30}$'
      or value ~ '^https://(www\.)?instagram\.com/[A-Za-z0-9._]{1,30}/?$')
  );
$function$;

create or replace function public.catalog_text_array_valid_v2(
  items text[], max_items integer, max_item_chars integer
)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select items is not null and max_items > 0 and max_item_chars > 0
    and cardinality(items) <= max_items
    and not exists (
      select 1 from unnest(items) as values(item)
      where item is null or char_length(item) > max_item_chars
        or item ~ '[[:cntrl:]]'
    );
$function$;

create or replace function public.catalog_https_array_valid_v2(items text[], max_items integer)
returns boolean language sql immutable parallel safe set search_path = ''
as $function$
  select items is not null and max_items > 0 and cardinality(items) <= max_items
    and not exists (
      select 1 from unnest(items) as values(item)
      where item is null or not public.catalog_https_url_valid_v2(item)
    );
$function$;

create or replace function public.catalog_search_text_v2(
  p_name text, p_summary text, p_category text, p_subcategory text,
  p_location text, p_services text[], p_products text[],
  p_additional_info text, p_promotion_title text, p_promotion_description text
)
returns text language sql immutable parallel safe set search_path = ''
as $function$
  select public.search_pilot_unaccent(lower(concat_ws(' ',
    coalesce(p_name, ''), coalesce(p_summary, ''), coalesce(p_category, ''),
    coalesce(p_subcategory, ''), coalesce(p_location, ''),
    coalesce(array_to_string(p_services, ' '), ''),
    coalesce(array_to_string(p_products, ' '), ''),
    coalesce(p_additional_info, ''), coalesce(p_promotion_title, ''),
    coalesce(p_promotion_description, '')
  )));
$function$;

create table public.public_establishment_catalog_v2 (
  id text primary key check (public.catalog_firestore_id_valid_v2(id)),
  name text not null check (
    char_length(btrim(name)) between 1 and 140 and name !~ '[[:cntrl:]]'
  ),
  summary text not null default '' check (
    char_length(summary) <= 3000
  ),
  category text not null check (category in (
    'Comércio', 'Onde comer?', 'Serviços', 'Profissionais', 'Empregos',
    'Turismo', 'Notícias', 'Eventos', 'Saúde', 'Imóveis', 'Veículos',
    'Pets', 'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Promoções',
    'Serviços úteis', 'Tecnologia'
  )),
  content_kind text not null check (content_kind in ('establishment', 'other_content')),
  category_group text not null check (category_group in ('commerce', 'services', 'other')),
  subcategory text not null default '' check (
    char_length(subcategory) <= 120 and subcategory !~ '[[:cntrl:]]'
  ),
  location text check (
    location is null or (char_length(location) <= 240 and location !~ '[[:cntrl:]]')
  ),
  artwork smallint not null default 0 check (artwork between 0 and 18),
  image_url text not null default ''
    check (image_url = '' or public.catalog_https_url_valid_v2(image_url)),
  logo_url text not null default ''
    check (logo_url = '' or public.catalog_https_url_valid_v2(logo_url)),
  gallery_urls text[] not null default '{}'::text[]
    check (public.catalog_https_array_valid_v2(gallery_urls, 20)),
  featured boolean not null default false,
  is_open boolean not null default true,
  maps_url text not null default ''
    check (maps_url = '' or public.catalog_map_url_valid_v2(maps_url)),
  hours text not null default '' check (
    char_length(hours) <= 500
  ),
  services text[] not null default '{}'::text[]
    check (public.catalog_text_array_valid_v2(services, 40, 160)),
  products text[] not null default '{}'::text[]
    check (public.catalog_text_array_valid_v2(products, 40, 160)),
  additional_info text not null default '' check (
    char_length(additional_info) <= 3000
  ),
  promotion_title text not null default '' check (
    char_length(promotion_title) <= 180 and promotion_title !~ '[[:cntrl:]]'
  ),
  promotion_description text not null default '' check (
    char_length(promotion_description) <= 1000
  ),
  public_contact_approved boolean not null default false,
  phone text check (public.catalog_phone_valid_v2(phone)),
  whatsapp text check (public.catalog_whatsapp_valid_v2(whatsapp)),
  instagram text check (public.catalog_instagram_valid_v2(instagram)),
  published boolean not null default false,
  active boolean not null default true,
  expires_at timestamptz,
  deleted_at timestamptz,
  catalog_version bigint not null check (catalog_version > 0),
  outbox_operation_id uuid not null unique,
  search_document text not null default '',
  check (
    (category in (
      'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
      'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia'
    ) and content_kind = 'establishment' and category_group = 'commerce')
    or (category in ('Serviços', 'Profissionais')
      and content_kind = 'establishment' and category_group = 'services')
    or (category in (
      'Empregos', 'Turismo', 'Notícias', 'Eventos', 'Promoções', 'Serviços úteis'
    ) and content_kind = 'other_content' and category_group = 'other')
  ),
  check (public_contact_approved or (phone is null and whatsapp is null and instagram is null))
);

create table public.catalog_tombstones_v2 (
  id text primary key check (public.catalog_firestore_id_valid_v2(id)),
  catalog_version bigint not null check (catalog_version > 0),
  outbox_operation_id uuid not null unique,
  tombstoned_at timestamptz not null
);

create or replace function public.catalog_prepare_establishment_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  tombstone public.catalog_tombstones_v2%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.id, 0));
  select * into tombstone from public.catalog_tombstones_v2 t
  where t.id = new.id for update;

  if found then
    if tg_op <> 'UPDATE' then
      raise exception using errcode = '23514', message = 'catalog row is tombstoned';
    end if;
    if new.deleted_at is null
      or new.catalog_version <> tombstone.catalog_version
      or new.outbox_operation_id <> tombstone.outbox_operation_id
      or new.deleted_at <> tombstone.tombstoned_at then
      raise exception using errcode = '23514', message = 'catalog row is tombstoned';
    end if;
    if old.catalog_version = new.catalog_version
      and old.outbox_operation_id = new.outbox_operation_id
      and (pg_catalog.to_jsonb(new) - 'search_document') =
          (pg_catalog.to_jsonb(old) - 'search_document') then
      return null;
    end if;
    if old.catalog_version >= new.catalog_version then
      raise exception using errcode = '23514', message = 'catalog row is tombstoned';
    end if;
  elsif tg_op = 'UPDATE' then
    if new.id <> old.id then
      raise exception using errcode = '23514', message = 'catalog identity is immutable';
    end if;
    if old.deleted_at is not null then
      raise exception using errcode = '23514', message = 'deleted catalog row is immutable';
    end if;
    if old.catalog_version = new.catalog_version
      and old.outbox_operation_id = new.outbox_operation_id
      and (pg_catalog.to_jsonb(new) - 'search_document') =
          (pg_catalog.to_jsonb(old) - 'search_document') then
      return null;
    end if;
    if new.catalog_version <= old.catalog_version
      or new.outbox_operation_id = old.outbox_operation_id then
      raise exception using errcode = '23514', message = 'catalog version must advance';
    end if;
  end if;

  new.search_document := public.catalog_search_text_v2(
    new.name, new.summary, new.category, new.subcategory, new.location,
    new.services, new.products, new.additional_info,
    new.promotion_title, new.promotion_description
  );
  return new;
end;
$function$;

create or replace function public.catalog_prepare_tombstone_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
declare
  existing public.catalog_tombstones_v2%rowtype;
  current_row public.public_establishment_catalog_v2%rowtype;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.id, 0));
  select * into existing from public.catalog_tombstones_v2 t
  where t.id = new.id for update;
  if found then
    if existing.catalog_version = new.catalog_version
      and existing.outbox_operation_id = new.outbox_operation_id
      and existing.tombstoned_at = new.tombstoned_at then
      return null;
    end if;
    raise exception using errcode = '23514', message = 'catalog tombstone is immutable';
  end if;

  select * into current_row from public.public_establishment_catalog_v2 c
  where c.id = new.id for update;
  if found and (
    new.catalog_version < current_row.catalog_version
    or (new.catalog_version = current_row.catalog_version and (
      current_row.deleted_at is null
      or current_row.deleted_at <> new.tombstoned_at
      or current_row.outbox_operation_id <> new.outbox_operation_id
    ))
  ) then
    raise exception using errcode = '23514', message = 'stale catalog tombstone';
  end if;
  return new;
end;
$function$;

create or replace function public.catalog_finish_establishment_write_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  if new.deleted_at is not null then
    insert into public.catalog_tombstones_v2
      (id, catalog_version, outbox_operation_id, tombstoned_at)
    values (new.id, new.catalog_version, new.outbox_operation_id, new.deleted_at);
  end if;
  return new;
end;
$function$;

create or replace function public.catalog_finish_tombstone_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  update public.public_establishment_catalog_v2 c
  set catalog_version = new.catalog_version,
      outbox_operation_id = new.outbox_operation_id,
      deleted_at = new.tombstoned_at
  where c.id = new.id and c.catalog_version < new.catalog_version;
  return new;
end;
$function$;

create or replace function public.catalog_prevent_physical_delete_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode = '23514', message = 'catalog rows require versioned tombstones';
end;
$function$;

create or replace function public.catalog_tombstone_immutable_v2()
returns trigger language plpgsql security definer set search_path = ''
as $function$
begin
  raise exception using errcode = '23514', message = 'catalog tombstones are immutable';
end;
$function$;

create trigger public_establishment_catalog_v2_prepare
before insert or update on public.public_establishment_catalog_v2
for each row execute function public.catalog_prepare_establishment_v2();

create trigger public_establishment_catalog_v2_no_delete
before delete on public.public_establishment_catalog_v2
for each row execute function public.catalog_prevent_physical_delete_v2();

create trigger public_establishment_catalog_v2_tombstone
after insert or update of deleted_at on public.public_establishment_catalog_v2
for each row when (new.deleted_at is not null)
execute function public.catalog_finish_establishment_write_v2();

create trigger catalog_tombstones_v2_prepare
before insert on public.catalog_tombstones_v2
for each row execute function public.catalog_prepare_tombstone_v2();

create trigger catalog_tombstones_v2_finish
after insert on public.catalog_tombstones_v2
for each row execute function public.catalog_finish_tombstone_v2();

create trigger catalog_tombstones_v2_immutable
before update or delete on public.catalog_tombstones_v2
for each row execute function public.catalog_tombstone_immutable_v2();

alter table public.public_establishment_catalog_v2 enable row level security;
alter table public.public_establishment_catalog_v2 force row level security;
alter table public.catalog_tombstones_v2 enable row level security;
alter table public.catalog_tombstones_v2 force row level security;
revoke all on table public.public_establishment_catalog_v2 from public, anon, authenticated;
revoke all on table public.catalog_tombstones_v2 from public, anon, authenticated;

create index public_establishment_catalog_v2_search_gin
  on public.public_establishment_catalog_v2 using gin (search_document extensions.gin_trgm_ops)
  where content_kind = 'establishment'
    and published = true and active = true and deleted_at is null;
create index public_establishment_catalog_v2_visible_name_idx
  on public.public_establishment_catalog_v2 (category_group, name collate "C", id collate "C")
  where content_kind = 'establishment' and published and active and deleted_at is null;
create index public_establishment_catalog_v2_list_name_idx
  on public.public_establishment_catalog_v2 (name collate "C", id collate "C")
  where content_kind = 'establishment' and published and active and deleted_at is null;
create index public_establishment_catalog_v2_expiry_idx
  on public.public_establishment_catalog_v2 (expires_at, id collate "C")
  where content_kind = 'establishment' and published and active
    and deleted_at is null and expires_at is not null;

create or replace function public.search_public_establishments_v2(
  p_query text, p_category_group text default 'all',
  p_page_size integer default 20, p_cursor_id text default null
)
returns table (
  id text, name text, summary text, category text, subcategory text,
  location text, artwork smallint, image_url text, logo_url text,
  gallery_urls text[], featured boolean, is_open boolean, maps_url text,
  hours text, services text[], products text[], additional_info text,
  promotion_title text, promotion_description text, phone text,
  whatsapp text, instagram text, has_more boolean
)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  normalized_query text;
  terms text[];
begin
  if p_query is null or char_length(p_query) > 80
    or p_page_size is null or p_page_size not between 1 and 40
    or p_category_group is null or p_category_group not in ('all', 'commerce', 'services')
    or (p_cursor_id is not null and not public.catalog_firestore_id_valid_v2(p_cursor_id)) then
    raise exception using errcode = '22023', message = 'invalid catalog search';
  end if;

  normalized_query := trim(regexp_replace(
    public.search_pilot_unaccent(lower(btrim(p_query))), '[^a-z0-9]+', ' ', 'g'
  ));
  terms := regexp_split_to_array(normalized_query, '\s+');
  if normalized_query = '' or array_length(terms, 1) not between 1 and 4
    or exists (select 1 from unnest(terms) as values(term)
      where char_length(term) not between 3 and 24) then
    raise exception using errcode = '22023', message = 'invalid catalog search terms';
  end if;

  if p_cursor_id is not null and not exists (
    select 1 from public.public_establishment_catalog_v2 e
    where e.id = p_cursor_id and e.content_kind = 'establishment'
      and (p_category_group = 'all' or e.category_group = p_category_group)
      and e.published and e.active and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and e.search_document like '%' || terms[1] || '%'
      and (cardinality(terms) < 2 or e.search_document like '%' || terms[2] || '%')
      and (cardinality(terms) < 3 or e.search_document like '%' || terms[3] || '%')
      and (cardinality(terms) < 4 or e.search_document like '%' || terms[4] || '%')
  ) then
    raise exception using errcode = '22023', message = 'invalid catalog search cursor';
  end if;

  return query
  with candidates as (
    select e.* from public.public_establishment_catalog_v2 e
    where e.content_kind = 'establishment'
      and (p_category_group = 'all' or e.category_group = p_category_group)
      and e.published and e.active and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and e.search_document like '%' || terms[1] || '%'
      and (cardinality(terms) < 2 or e.search_document like '%' || terms[2] || '%')
      and (cardinality(terms) < 3 or e.search_document like '%' || terms[3] || '%')
      and (cardinality(terms) < 4 or e.search_document like '%' || terms[4] || '%')
      and (p_cursor_id is null or e.id collate "C" > p_cursor_id collate "C")
    order by e.id collate "C" limit p_page_size + 1
  ), page as (
    select c.*, count(*) over () > p_page_size as page_has_more
    from candidates c order by c.id collate "C" limit p_page_size
  )
  select p.id, p.name, p.summary, p.category, p.subcategory,
    p.location, p.artwork, p.image_url, p.logo_url, p.gallery_urls,
    p.featured, p.is_open, p.maps_url, p.hours, p.services, p.products,
    p.additional_info, p.promotion_title, p.promotion_description,
    case when p.public_contact_approved then p.phone else null end,
    case when p.public_contact_approved then p.whatsapp else null end,
    case when p.public_contact_approved then p.instagram else null end,
    p.page_has_more
  from page p order by p.id collate "C";
end;
$function$;

create or replace function public.list_public_establishments_v2(
  p_category_group text default 'all', p_page_size integer default 20,
  p_cursor_id text default null
)
returns table (
  id text, name text, summary text, category text, subcategory text,
  location text, artwork smallint, image_url text, logo_url text,
  gallery_urls text[], featured boolean, is_open boolean, maps_url text,
  hours text, services text[], products text[], additional_info text,
  promotion_title text, promotion_description text, phone text,
  whatsapp text, instagram text, has_more boolean
)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  cursor_name text;
begin
  if p_page_size is null or p_page_size not between 1 and 40
    or p_category_group is null or p_category_group not in ('all', 'commerce', 'services')
    or (p_cursor_id is not null and not public.catalog_firestore_id_valid_v2(p_cursor_id)) then
    raise exception using errcode = '22023', message = 'invalid catalog list';
  end if;

  if p_cursor_id is not null then
    select e.name into cursor_name
    from public.public_establishment_catalog_v2 e
    where e.id = p_cursor_id and e.content_kind = 'establishment'
      and (p_category_group = 'all' or e.category_group = p_category_group)
      and e.published and e.active and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp());
    if not found then
      raise exception using errcode = '22023', message = 'invalid catalog list cursor';
    end if;
  end if;

  return query
  with candidates as (
    select e.* from public.public_establishment_catalog_v2 e
    where e.content_kind = 'establishment'
      and (p_category_group = 'all' or e.category_group = p_category_group)
      and e.published and e.active and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and (p_cursor_id is null or
        (e.name collate "C", e.id collate "C") >
        (cursor_name collate "C", p_cursor_id collate "C"))
    order by e.name collate "C", e.id collate "C"
    limit p_page_size + 1
  ), page as (
    select c.*, count(*) over () > p_page_size as page_has_more
    from candidates c order by c.name collate "C", c.id collate "C"
    limit p_page_size
  )
  select p.id, p.name, p.summary, p.category, p.subcategory,
    p.location, p.artwork, p.image_url, p.logo_url, p.gallery_urls,
    p.featured, p.is_open, p.maps_url, p.hours, p.services, p.products,
    p.additional_info, p.promotion_title, p.promotion_description,
    case when p.public_contact_approved then p.phone else null end,
    case when p.public_contact_approved then p.whatsapp else null end,
    case when p.public_contact_approved then p.instagram else null end,
    p.page_has_more
  from page p order by p.name collate "C", p.id collate "C";
end;
$function$;

create or replace function public.get_public_establishment_v2(p_id text)
returns table (
  id text, name text, summary text, category text, subcategory text,
  location text, artwork smallint, image_url text, logo_url text,
  gallery_urls text[], featured boolean, is_open boolean, maps_url text,
  hours text, services text[], products text[], additional_info text,
  promotion_title text, promotion_description text,
  phone text, whatsapp text, instagram text
)
language plpgsql stable security definer set search_path = ''
as $function$
begin
  if not public.catalog_firestore_id_valid_v2(p_id) then
    raise exception using errcode = '22023', message = 'invalid catalog detail ID';
  end if;
  return query
  select e.id, e.name, e.summary, e.category, e.subcategory,
    e.location, e.artwork, e.image_url, e.logo_url, e.gallery_urls,
    e.featured, e.is_open, e.maps_url, e.hours, e.services, e.products,
    e.additional_info, e.promotion_title, e.promotion_description,
    case when e.public_contact_approved then e.phone else null end,
    case when e.public_contact_approved then e.whatsapp else null end,
    case when e.public_contact_approved then e.instagram else null end
  from public.public_establishment_catalog_v2 e
  where e.id = p_id and e.content_kind = 'establishment'
    and e.published and e.active and e.deleted_at is null
    and (e.expires_at is null or e.expires_at > statement_timestamp());
end;
$function$;

alter function public.catalog_firestore_id_valid_v2(text) owner to postgres;
alter function public.catalog_https_url_valid_v2(text) owner to postgres;
alter function public.catalog_map_url_valid_v2(text) owner to postgres;
alter function public.catalog_phone_valid_v2(text) owner to postgres;
alter function public.catalog_whatsapp_valid_v2(text) owner to postgres;
alter function public.catalog_instagram_valid_v2(text) owner to postgres;
alter function public.catalog_text_array_valid_v2(text[], integer, integer) owner to postgres;
alter function public.catalog_https_array_valid_v2(text[], integer) owner to postgres;
alter function public.catalog_search_text_v2(text, text, text, text, text, text[], text[], text, text, text)
  owner to postgres;
alter function public.catalog_prepare_establishment_v2() owner to postgres;
alter function public.catalog_prepare_tombstone_v2() owner to postgres;
alter function public.catalog_finish_establishment_write_v2() owner to postgres;
alter function public.catalog_finish_tombstone_v2() owner to postgres;
alter function public.catalog_prevent_physical_delete_v2() owner to postgres;
alter function public.catalog_tombstone_immutable_v2() owner to postgres;
alter function public.search_public_establishments_v2(text, text, integer, text) owner to postgres;
alter function public.list_public_establishments_v2(text, integer, text) owner to postgres;
alter function public.get_public_establishment_v2(text) owner to postgres;

revoke all on function public.catalog_firestore_id_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_https_url_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_map_url_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_phone_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_whatsapp_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_instagram_valid_v2(text) from public, anon, authenticated;
revoke all on function public.catalog_text_array_valid_v2(text[], integer, integer) from public, anon, authenticated;
revoke all on function public.catalog_https_array_valid_v2(text[], integer) from public, anon, authenticated;
revoke all on function public.catalog_search_text_v2(text, text, text, text, text, text[], text[], text, text, text)
  from public, anon, authenticated;
revoke all on function public.catalog_prepare_establishment_v2() from public, anon, authenticated;
revoke all on function public.catalog_prepare_tombstone_v2() from public, anon, authenticated;
revoke all on function public.catalog_finish_establishment_write_v2() from public, anon, authenticated;
revoke all on function public.catalog_finish_tombstone_v2() from public, anon, authenticated;
revoke all on function public.catalog_prevent_physical_delete_v2() from public, anon, authenticated;
revoke all on function public.catalog_tombstone_immutable_v2() from public, anon, authenticated;

revoke all on function public.search_public_establishments_v2(text, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.list_public_establishments_v2(text, integer, text)
  from public, anon, authenticated;
revoke all on function public.get_public_establishment_v2(text)
  from public, anon, authenticated;
grant execute on function public.search_public_establishments_v2(text, text, integer, text) to anon;
grant execute on function public.list_public_establishments_v2(text, integer, text) to anon;
grant execute on function public.get_public_establishment_v2(text) to anon;

comment on table public.public_establishment_catalog_v2 is
  'Explicit public projection only. Firestore remains canonical; internal fields are never returned by public RPCs.';
comment on column public.public_establishment_catalog_v2.catalog_version is
  'Monotonic Firestore/outbox version. Updates must strictly advance it.';
comment on column public.public_establishment_catalog_v2.outbox_operation_id is
  'Internal operation UUID for future idempotent outbox reconciliation; never public.';
comment on table public.catalog_tombstones_v2 is
  'Permanent versioned logical-deletion markers; stale projection events cannot recreate a tombstoned ID.';
