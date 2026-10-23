-- Private, bounded destination snapshots for read-only catalog reconciliation.
-- This does not change the public V1/V2 RPCs or allow direct table access.
begin;

create table public.catalog_reconciliation_snapshots_v2 (
  snapshot_id uuid primary key,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  entity_count integer not null default 0 check (entity_count between 0 and 10000),
  payload_bytes bigint not null default 0 check (payload_bytes between 0 and 67108864),
  check (expires_at > created_at)
);

create index catalog_reconciliation_snapshots_v2_expiry_idx
  on public.catalog_reconciliation_snapshots_v2 (expires_at, snapshot_id);

create table public.catalog_reconciliation_snapshot_rows_v2 (
  snapshot_id uuid not null references public.catalog_reconciliation_snapshots_v2(snapshot_id) on delete cascade,
  entity_id text not null check (public.catalog_firestore_id_valid_v2(entity_id)),
  catalog_row jsonb,
  tombstone jsonb,
  primary key (snapshot_id, entity_id),
  check (catalog_row is not null or tombstone is not null),
  check (catalog_row is null or catalog_row ->> 'id' = entity_id),
  check (tombstone is null or tombstone ->> 'id' = entity_id)
);

create index catalog_reconciliation_snapshot_rows_v2_cursor_idx
  on public.catalog_reconciliation_snapshot_rows_v2 (snapshot_id, entity_id collate "C");

create index public_establishment_catalog_v2_reconciliation_ids_idx
  on public.public_establishment_catalog_v2 (id collate "C")
  where content_kind = 'establishment';

alter table public.catalog_reconciliation_snapshots_v2 enable row level security;
alter table public.catalog_reconciliation_snapshots_v2 force row level security;
alter table public.catalog_reconciliation_snapshot_rows_v2 enable row level security;
alter table public.catalog_reconciliation_snapshot_rows_v2 force row level security;
revoke all on table public.catalog_reconciliation_snapshots_v2,
  public.catalog_reconciliation_snapshot_rows_v2 from public, anon, authenticated, service_role;
alter table public.catalog_reconciliation_snapshots_v2 owner to postgres;
alter table public.catalog_reconciliation_snapshot_rows_v2 owner to postgres;

create or replace function public.begin_catalog_reconciliation_snapshot_v2(p_snapshot_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '30s'
as $function$
declare
  existing public.catalog_reconciliation_snapshots_v2%rowtype;
  entity_total integer;
  byte_total bigint;
begin
  if p_snapshot_id is null then
    raise exception using errcode = '22023', message = 'invalid reconciliation snapshot';
  end if;

  -- Serialize capacity checks and retries for this ID; no caller-provided SQL is used.
  perform pg_catalog.pg_advisory_xact_lock(7303, pg_catalog.hashtext('catalog-reconciliation-capacity'));
  perform pg_catalog.pg_advisory_xact_lock(7303, pg_catalog.hashtext('catalog-reconciliation:' || p_snapshot_id::text));

  select * into existing from public.catalog_reconciliation_snapshots_v2 s
  where s.snapshot_id = p_snapshot_id for update;
  if found then
    if existing.expires_at <= statement_timestamp() then
      raise exception using errcode = '55000', message = 'reconciliation snapshot expired';
    end if;
    return pg_catalog.jsonb_build_object(
      'snapshot_id', existing.snapshot_id,
      'captured_at', existing.created_at,
      'expires_at', existing.expires_at,
      'entity_count', existing.entity_count,
      'payload_bytes', existing.payload_bytes,
      'replayed', true
    );
  end if;

  -- Bound orphan retention: remove at most one expired snapshot for each new scan.
  delete from public.catalog_reconciliation_snapshots_v2 s
  where s.snapshot_id = (
    select expired.snapshot_id
    from public.catalog_reconciliation_snapshots_v2 expired
    where expired.expires_at <= statement_timestamp()
    order by expired.expires_at, expired.snapshot_id
    limit 1 for update skip locked
  );

  if (select pg_catalog.count(*) from public.catalog_reconciliation_snapshots_v2 s
      where s.expires_at > statement_timestamp()) >= 4 then
    raise exception using errcode = '54000', message = 'reconciliation capacity exceeded';
  end if;

  insert into public.catalog_reconciliation_snapshots_v2 (snapshot_id, expires_at)
  values (p_snapshot_id, statement_timestamp() + interval '1 hour');

  with catalog_candidates as materialized (
    select e.id as entity_id
    from public.public_establishment_catalog_v2 e
    where e.content_kind = 'establishment'
    limit 10001
  ), tombstone_candidates as materialized (
    select t.id as entity_id
    from public.catalog_tombstones_v2 t
    limit 10001
  ), candidate_ids as materialized (
    select candidates.entity_id
    from (
      select c.entity_id from catalog_candidates c
      union
      select t.entity_id from tombstone_candidates t
    ) candidates
    order by candidates.entity_id collate "C"
    limit 10001
  )
  insert into public.catalog_reconciliation_snapshot_rows_v2 (
    snapshot_id, entity_id, catalog_row, tombstone
  )
  select p_snapshot_id, ids.entity_id,
    case when e.id is null then null else pg_catalog.jsonb_build_object(
      'id', e.id, 'content_kind', e.content_kind, 'category_group', e.category_group,
      'name', e.name, 'summary', e.summary, 'category', e.category,
      'subcategory', e.subcategory, 'location', e.location, 'artwork', e.artwork,
      'image_url', e.image_url, 'logo_url', e.logo_url, 'gallery_urls', e.gallery_urls,
      'featured', e.featured, 'is_open', e.is_open, 'maps_url', e.maps_url,
      'hours', e.hours, 'services', e.services, 'products', e.products,
      'additional_info', e.additional_info, 'promotion_title', e.promotion_title,
      'promotion_description', e.promotion_description,
      'public_contact_approved', e.public_contact_approved, 'phone', e.phone,
      'whatsapp', e.whatsapp, 'instagram', e.instagram, 'published', e.published,
      'active', e.active, 'expires_at', e.expires_at, 'deleted_at', e.deleted_at,
      'catalog_version', e.catalog_version, 'outbox_operation_id', e.outbox_operation_id
    ) end,
    case when t.id is null then null else pg_catalog.jsonb_build_object(
      'id', t.id, 'catalog_version', t.catalog_version,
      'outbox_operation_id', t.outbox_operation_id, 'tombstoned_at', t.tombstoned_at
    ) end
  from candidate_ids ids
  left join public.public_establishment_catalog_v2 e
    on e.id = ids.entity_id and e.content_kind = 'establishment'
  left join public.catalog_tombstones_v2 t on t.id = ids.entity_id;

  get diagnostics entity_total = row_count;
  if entity_total > 10000 then
    raise exception using errcode = '54000', message = 'reconciliation snapshot row limit exceeded';
  end if;

  select coalesce(pg_catalog.sum(
    pg_catalog.pg_column_size(coalesce(r.catalog_row, 'null'::jsonb))::bigint +
    pg_catalog.pg_column_size(coalesce(r.tombstone, 'null'::jsonb))::bigint
  ), 0) into byte_total
  from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = p_snapshot_id;
  if byte_total > 67108864 then
    raise exception using errcode = '54000', message = 'reconciliation snapshot byte limit exceeded';
  end if;

  update public.catalog_reconciliation_snapshots_v2 s
  set entity_count = entity_total, payload_bytes = byte_total
  where s.snapshot_id = p_snapshot_id
  returning * into existing;

  return pg_catalog.jsonb_build_object(
    'snapshot_id', existing.snapshot_id,
    'captured_at', existing.created_at,
    'expires_at', existing.expires_at,
    'entity_count', existing.entity_count,
    'payload_bytes', existing.payload_bytes,
    'replayed', false
  );
end;
$function$;

create or replace function public.read_catalog_reconciliation_page_v2(
  p_snapshot_id uuid, p_after_id text default null, p_page_size integer default 100
)
returns jsonb
language plpgsql security definer set search_path = '' set statement_timeout = '30s'
as $function$
declare
  snapshot public.catalog_reconciliation_snapshots_v2%rowtype;
  page_ids text[];
  page_catalog jsonb;
  page_tombstones jsonb;
  has_more boolean;
  next_id text;
begin
  if p_snapshot_id is null or p_page_size is null or p_page_size not between 1 and 200
    or (p_after_id is not null and not public.catalog_firestore_id_valid_v2(p_after_id)) then
    raise exception using errcode = '22023', message = 'invalid reconciliation page';
  end if;

  select * into snapshot from public.catalog_reconciliation_snapshots_v2 s
  where s.snapshot_id = p_snapshot_id for share;
  if not found or snapshot.expires_at <= statement_timestamp() then
    raise exception using errcode = '55000', message = 'reconciliation snapshot expired';
  end if;

  select coalesce(pg_catalog.array_agg(page.entity_id order by page.entity_id collate "C"), array[]::text[])
  into page_ids
  from (
    select r.entity_id
    from public.catalog_reconciliation_snapshot_rows_v2 r
    where r.snapshot_id = p_snapshot_id
      and (p_after_id is null or r.entity_id collate "C" > p_after_id collate "C")
    order by r.entity_id collate "C"
    limit p_page_size + 1
  ) page;

  has_more := pg_catalog.cardinality(page_ids) > p_page_size;
  if has_more then page_ids := page_ids[1:p_page_size]; end if;
  next_id := case when pg_catalog.cardinality(page_ids) = 0 then p_after_id
    else page_ids[pg_catalog.cardinality(page_ids)] end;

  select coalesce(pg_catalog.jsonb_agg(r.catalog_row order by r.entity_id collate "C"), '[]'::jsonb)
  into page_catalog
  from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = p_snapshot_id and r.entity_id = any(page_ids) and r.catalog_row is not null;

  select coalesce(pg_catalog.jsonb_agg(r.tombstone order by r.entity_id collate "C"), '[]'::jsonb)
  into page_tombstones
  from public.catalog_reconciliation_snapshot_rows_v2 r
  where r.snapshot_id = p_snapshot_id and r.entity_id = any(page_ids) and r.tombstone is not null;

  return pg_catalog.jsonb_build_object(
    'snapshot_id', snapshot.snapshot_id,
    'captured_at', snapshot.created_at,
    'expires_at', snapshot.expires_at,
    'next_cursor', next_id,
    'done', not has_more,
    'catalog_rows', page_catalog,
    'tombstones', page_tombstones
  );
end;
$function$;

create or replace function public.dispose_catalog_reconciliation_snapshot_v2(p_snapshot_id uuid)
returns boolean
language plpgsql security definer set search_path = '' set statement_timeout = '30s'
as $function$
begin
  if p_snapshot_id is null then
    raise exception using errcode = '22023', message = 'invalid reconciliation snapshot';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(7303, pg_catalog.hashtext('catalog-reconciliation:' || p_snapshot_id::text));
  delete from public.catalog_reconciliation_snapshots_v2 s where s.snapshot_id = p_snapshot_id;
  return found;
end;
$function$;

alter function public.begin_catalog_reconciliation_snapshot_v2(uuid) owner to postgres;
alter function public.read_catalog_reconciliation_page_v2(uuid, text, integer) owner to postgres;
alter function public.dispose_catalog_reconciliation_snapshot_v2(uuid) owner to postgres;

revoke all on function public.begin_catalog_reconciliation_snapshot_v2(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.read_catalog_reconciliation_page_v2(uuid, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.dispose_catalog_reconciliation_snapshot_v2(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.begin_catalog_reconciliation_snapshot_v2(uuid) to service_role;
grant execute on function public.read_catalog_reconciliation_page_v2(uuid, text, integer) to service_role;
grant execute on function public.dispose_catalog_reconciliation_snapshot_v2(uuid) to service_role;

comment on table public.catalog_reconciliation_snapshots_v2 is
  'Short-lived, service-only snapshot headers for read-only V2 reconciliation; maximum one-hour lifetime.';
comment on table public.catalog_reconciliation_snapshot_rows_v2 is
  'Explicitly projected private reconciliation snapshot rows; never exposed by direct table grants.';
comment on function public.begin_catalog_reconciliation_snapshot_v2(uuid) is
  'Materializes a bounded private destination snapshot; EXECUTE is restricted to service_role.';
comment on function public.read_catalog_reconciliation_page_v2(uuid, text, integer) is
  'Reads a deterministic page from a fixed private destination snapshot; EXECUTE is restricted to service_role.';
comment on function public.dispose_catalog_reconciliation_snapshot_v2(uuid) is
  'Deletes only the requested private reconciliation snapshot; EXECUTE is restricted to service_role.';

commit;
