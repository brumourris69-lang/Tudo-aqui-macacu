-- Private, idempotent server-side writer for the V2 public projection.
-- Firestore remains canonical. Public V1/V2 RPCs and schemas are unchanged.

create or replace function public.apply_establishment_projection_v2(p_projection jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  allowed_keys constant text[] := array[
    'id', 'content_kind', 'category_group', 'name', 'summary', 'category',
    'subcategory', 'location', 'artwork', 'image_url', 'logo_url', 'gallery_urls',
    'featured', 'is_open', 'maps_url', 'hours', 'services', 'products',
    'additional_info', 'promotion_title', 'promotion_description',
    'public_contact_approved', 'phone', 'whatsapp', 'instagram', 'published',
    'active', 'expires_at', 'deleted_at', 'catalog_version', 'outbox_operation_id'
  ];
  incoming public.public_establishment_catalog_v2%rowtype;
  current_row public.public_establishment_catalog_v2%rowtype;
  has_current boolean;
begin
  if p_projection is null or pg_catalog.jsonb_typeof(p_projection) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid catalog projection';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_projection))
       <> pg_catalog.cardinality(allowed_keys)
    or not (p_projection ?& allowed_keys)
    or exists (
      select 1 from pg_catalog.jsonb_object_keys(p_projection) as supplied(key)
      where supplied.key <> all (allowed_keys)
    ) then
    raise exception using errcode = '22023', message = 'invalid catalog projection';
  end if;

  if pg_catalog.jsonb_typeof(p_projection -> 'id') <> 'string'
    or exists (
      select 1 from (values
        ('content_kind'), ('category_group'), ('name'), ('summary'), ('category'),
        ('subcategory'), ('image_url'), ('logo_url'), ('maps_url'), ('hours'),
        ('additional_info'), ('promotion_title'), ('promotion_description')
      ) as required_string(key)
      where pg_catalog.jsonb_typeof(p_projection -> required_string.key) <> 'string'
    )
    or exists (
      select 1 from (values
        ('location'), ('phone'), ('whatsapp'), ('instagram'), ('expires_at')
      ) as nullable_string(key)
      where pg_catalog.jsonb_typeof(p_projection -> nullable_string.key) not in ('string', 'null')
    )
    or exists (
      select 1 from (values
        ('gallery_urls'), ('services'), ('products')
      ) as required_array(key)
      where pg_catalog.jsonb_typeof(p_projection -> required_array.key) <> 'array'
    )
    or exists (
      select 1 from (values
        ('featured'), ('is_open'), ('public_contact_approved'), ('published'), ('active')
      ) as required_boolean(key)
      where pg_catalog.jsonb_typeof(p_projection -> required_boolean.key) <> 'boolean'
    )
    or exists (
      select 1 from (values ('gallery_urls'), ('services'), ('products')) as arrays(key)
      cross join lateral pg_catalog.jsonb_array_elements(
        case when pg_catalog.jsonb_typeof(p_projection -> arrays.key) = 'array'
          then p_projection -> arrays.key else '[]'::jsonb end
      ) as item(value)
      where pg_catalog.jsonb_typeof(item.value) <> 'string'
    )
    or pg_catalog.jsonb_typeof(p_projection -> 'artwork') <> 'number'
    or p_projection ->> 'artwork' !~ '^(0|[1-9][0-9]*)$'
    or pg_catalog.jsonb_typeof(p_projection -> 'catalog_version') <> 'number'
    or p_projection ->> 'catalog_version' !~ '^[1-9][0-9]*$'
    or pg_catalog.jsonb_typeof(p_projection -> 'outbox_operation_id') <> 'string'
    or p_projection ->> 'outbox_operation_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or pg_catalog.jsonb_typeof(p_projection -> 'deleted_at') <> 'null' then
    raise exception using errcode = '22023', message = 'invalid catalog projection';
  end if;

  begin
    incoming := pg_catalog.jsonb_populate_record(
      null::public.public_establishment_catalog_v2, p_projection
    );
  exception when others then
    raise exception using errcode = '22023', message = 'invalid catalog projection';
  end;

  if incoming.content_kind <> 'establishment' or incoming.deleted_at is not null then
    raise exception using errcode = '22023', message = 'invalid catalog projection';
  end if;

  -- The per-ID lock closes the absent-row race. The operation lock prevents a
  -- duplicated UUID from being accepted concurrently for two different IDs.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(incoming.id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    7302, pg_catalog.hashtext('catalog-op:' || incoming.outbox_operation_id::text)
  );

  if exists (
      select 1 from public.catalog_tombstones_v2 t where t.id = incoming.id
    ) then
    raise exception using errcode = '23514', message = 'catalog ID is permanently deleted';
  end if;

  select * into current_row
  from public.public_establishment_catalog_v2 c
  where c.id = incoming.id
  for update;
  has_current := found;

  if has_current then
    if incoming.catalog_version < current_row.catalog_version then
      raise exception using errcode = '23514', message = 'stale catalog version';
    end if;
    if incoming.catalog_version = current_row.catalog_version then
      if incoming.outbox_operation_id = current_row.outbox_operation_id
        and (pg_catalog.to_jsonb(incoming) - 'search_document') =
            (pg_catalog.to_jsonb(current_row) - 'search_document') then
        return 'replayed';
      end if;
      raise exception using errcode = '23514', message = 'catalog version conflict';
    end if;
  end if;

  if exists (
      select 1 from public.public_establishment_catalog_v2 c
      where c.outbox_operation_id = incoming.outbox_operation_id
        and c.id <> incoming.id
    ) or exists (
      select 1 from public.catalog_tombstones_v2 t
      where t.outbox_operation_id = incoming.outbox_operation_id
    ) then
    raise exception using errcode = '23514', message = 'catalog operation conflict';
  end if;

  if has_current then
    update public.public_establishment_catalog_v2 set
      name = incoming.name,
      summary = incoming.summary,
      category = incoming.category,
      content_kind = incoming.content_kind,
      category_group = incoming.category_group,
      subcategory = incoming.subcategory,
      location = incoming.location,
      artwork = incoming.artwork,
      image_url = incoming.image_url,
      logo_url = incoming.logo_url,
      gallery_urls = incoming.gallery_urls,
      featured = incoming.featured,
      is_open = incoming.is_open,
      maps_url = incoming.maps_url,
      hours = incoming.hours,
      services = incoming.services,
      products = incoming.products,
      additional_info = incoming.additional_info,
      promotion_title = incoming.promotion_title,
      promotion_description = incoming.promotion_description,
      public_contact_approved = incoming.public_contact_approved,
      phone = incoming.phone,
      whatsapp = incoming.whatsapp,
      instagram = incoming.instagram,
      published = incoming.published,
      active = incoming.active,
      expires_at = incoming.expires_at,
      deleted_at = null,
      catalog_version = incoming.catalog_version,
      outbox_operation_id = incoming.outbox_operation_id
    where id = incoming.id;
  else
    insert into public.public_establishment_catalog_v2 (
      id, name, summary, category, content_kind, category_group, subcategory,
      location, artwork, image_url, logo_url, gallery_urls, featured, is_open,
      maps_url, hours, services, products, additional_info, promotion_title,
      promotion_description, public_contact_approved, phone, whatsapp, instagram,
      published, active, expires_at, deleted_at, catalog_version, outbox_operation_id
    ) values (
      incoming.id, incoming.name, incoming.summary, incoming.category,
      incoming.content_kind, incoming.category_group, incoming.subcategory,
      incoming.location, incoming.artwork, incoming.image_url, incoming.logo_url,
      incoming.gallery_urls, incoming.featured, incoming.is_open, incoming.maps_url,
      incoming.hours, incoming.services, incoming.products, incoming.additional_info,
      incoming.promotion_title, incoming.promotion_description,
      incoming.public_contact_approved, incoming.phone, incoming.whatsapp,
      incoming.instagram, incoming.published, incoming.active, incoming.expires_at,
      null, incoming.catalog_version, incoming.outbox_operation_id
    );
  end if;

  return 'applied';
end;
$function$;

create or replace function public.apply_establishment_tombstone_v2(p_tombstone jsonb)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  allowed_keys constant text[] := array[
    'id', 'catalog_version', 'outbox_operation_id', 'deleted_at'
  ];
  entity_id text;
  catalog_version_value bigint;
  operation_id uuid;
  deleted_at timestamptz;
  current_tombstone public.catalog_tombstones_v2%rowtype;
  current_row public.public_establishment_catalog_v2%rowtype;
begin
  if p_tombstone is null or pg_catalog.jsonb_typeof(p_tombstone) <> 'object' then
    raise exception using errcode = '22023', message = 'invalid catalog tombstone';
  end if;

  if (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_tombstone))
       <> pg_catalog.cardinality(allowed_keys)
    or not (p_tombstone ?& allowed_keys)
    or exists (
      select 1 from pg_catalog.jsonb_object_keys(p_tombstone) as supplied(key)
      where supplied.key <> all (allowed_keys)
    )
    or pg_catalog.jsonb_typeof(p_tombstone -> 'id') <> 'string'
    or pg_catalog.jsonb_typeof(p_tombstone -> 'catalog_version') <> 'number'
    or p_tombstone ->> 'catalog_version' !~ '^[1-9][0-9]*$'
    or pg_catalog.jsonb_typeof(p_tombstone -> 'outbox_operation_id') <> 'string'
    or p_tombstone ->> 'outbox_operation_id' !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or pg_catalog.jsonb_typeof(p_tombstone -> 'deleted_at') <> 'string' then
    raise exception using errcode = '22023', message = 'invalid catalog tombstone';
  end if;

  begin
    entity_id := p_tombstone ->> 'id';
    catalog_version_value := (p_tombstone ->> 'catalog_version')::bigint;
    operation_id := (p_tombstone ->> 'outbox_operation_id')::uuid;
    deleted_at := (p_tombstone ->> 'deleted_at')::timestamptz;
  exception when others then
    raise exception using errcode = '22023', message = 'invalid catalog tombstone';
  end;

  if deleted_at is null then
    raise exception using errcode = '22023', message = 'invalid catalog tombstone';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(entity_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    7302, pg_catalog.hashtext('catalog-op:' || operation_id::text)
  );

  select * into current_tombstone
  from public.catalog_tombstones_v2 t
  where t.id = entity_id
  for update;

  if found then
    if current_tombstone.catalog_version = catalog_version_value
      and current_tombstone.outbox_operation_id = operation_id
      and current_tombstone.tombstoned_at = deleted_at then
      return 'replayed';
    end if;
    raise exception using errcode = '23514', message = 'catalog tombstone is immutable';
  end if;

  select * into current_row
  from public.public_establishment_catalog_v2 c
  where c.id = entity_id
  for update;

  if found and (current_row.deleted_at is not null or catalog_version_value <= current_row.catalog_version) then
    raise exception using errcode = '23514', message = 'stale or deleted catalog version';
  end if;

  if exists (
      select 1 from public.public_establishment_catalog_v2 c
      where c.outbox_operation_id = operation_id
    ) or exists (
      select 1 from public.catalog_tombstones_v2 t
      where t.outbox_operation_id = operation_id
    ) then
    raise exception using errcode = '23514', message = 'catalog operation conflict';
  end if;

  insert into public.catalog_tombstones_v2 (
    id, catalog_version, outbox_operation_id, tombstoned_at
  ) values (entity_id, catalog_version_value, operation_id, deleted_at);

  return 'applied';
end;
$function$;

alter function public.apply_establishment_projection_v2(jsonb) owner to postgres;
alter function public.apply_establishment_tombstone_v2(jsonb) owner to postgres;

revoke all on function public.apply_establishment_projection_v2(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.apply_establishment_tombstone_v2(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.apply_establishment_projection_v2(jsonb) to service_role;
grant execute on function public.apply_establishment_tombstone_v2(jsonb) to service_role;

-- The server invokes the narrowly granted SECURITY DEFINER writers; it must
-- not bypass their allowlists by writing these internal tables directly.
revoke all on table public.public_establishment_catalog_v2, public.catalog_tombstones_v2
  from service_role;

comment on function public.apply_establishment_projection_v2(jsonb) is
  'Server-only allowlisted and idempotent writer for the Firestore-derived V2 projection.';
comment on function public.apply_establishment_tombstone_v2(jsonb) is
  'Server-only immutable tombstone writer; only logical deletion uses this path.';
