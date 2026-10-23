-- Keep the catalog private to database roles. Public reads remain available
-- only through the bounded, explicit-projection RPCs below.
alter table public.public_search_establishments
  add column if not exists expires_at timestamptz,
  add column if not exists deleted_at timestamptz;

comment on column public.public_search_establishments.expires_at is
  'Null means no expiration; expired rows are excluded from public RPCs.';
comment on column public.public_search_establishments.deleted_at is
  'Soft deletion timestamp; non-null rows are excluded from public RPCs.';

alter table public.public_search_establishments enable row level security;
alter table public.public_search_establishments force row level security;
drop policy if exists public_search_establishments_anon_read
  on public.public_search_establishments;

revoke all on table public.public_search_establishments
  from public, anon, authenticated;
revoke select (
  id, name, summary, category, subcategory, image_url,
  published, active, expires_at, deleted_at
) on table public.public_search_establishments
  from public, anon, authenticated;

create or replace function public.search_public_establishments(
  p_query text,
  p_category text default 'all',
  p_page_size integer default 20,
  p_cursor_id text default null
)
returns table (
  id text,
  name text,
  summary text,
  category text,
  subcategory text,
  image_url text,
  has_more boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  normalized_query text;
  terms text[];
  cursor_rank real;
begin
  if p_query is null or length(p_query) > 80 then
    raise exception using errcode = '22023', message = 'invalid search query';
  end if;
  if p_page_size is null or p_page_size not between 1 and 20 then
    raise exception using errcode = '22023', message = 'invalid page size';
  end if;
  if p_category is null or p_category not in ('all', 'commerce', 'services') then
    raise exception using errcode = '22023', message = 'invalid category';
  end if;

  normalized_query := trim(regexp_replace(
    public.search_pilot_unaccent(lower(btrim(p_query))), '[^a-z0-9]+', ' ', 'g'
  ));
  terms := regexp_split_to_array(normalized_query, '\s+');
  if normalized_query = '' or array_length(terms, 1) not between 1 and 4
     or exists (
       select 1 from unnest(terms) as term
       where length(term) not between 2 and 24
     ) then
    raise exception using errcode = '22023', message = 'invalid search terms';
  end if;

  if p_cursor_id is not null and (
    length(p_cursor_id) > 65 or p_cursor_id !~ '^pilot-[a-z0-9-]{1,60}$'
  ) then
    raise exception using errcode = '22023', message = 'invalid cursor';
  end if;

  if p_cursor_id is not null then
    select extensions.similarity(
      public.search_pilot_unaccent(
        public.search_pilot_document_text(e.name, e.summary, e.category, e.subcategory)
      ),
      normalized_query
    ) into cursor_rank
    from public.public_search_establishments e
    where e.id = p_cursor_id
      and e.published = true and e.active = true
      and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and (p_category = 'all'
        or (p_category = 'commerce' and e.category in (
          'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
          'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia'
        ))
        or (p_category = 'services' and e.category in ('Serviços', 'Profissionais')))
      and not exists (
        select 1 from unnest(terms) as term
        where public.search_pilot_unaccent(
          public.search_pilot_document_text(e.name, e.summary, e.category, e.subcategory)
        ) not like '%' || term || '%'
      );
    if cursor_rank is null then
      raise exception using errcode = '22023', message = 'invalid cursor';
    end if;
  end if;

  return query
  with eligible as (
    select e.id, e.name, e.summary, e.category, e.subcategory, e.image_url,
      extensions.similarity(
        public.search_pilot_unaccent(
          public.search_pilot_document_text(e.name, e.summary, e.category, e.subcategory)
        ),
        normalized_query
      ) as rank_value
    from public.public_search_establishments e
    where e.published = true and e.active = true
      and e.deleted_at is null
      and (e.expires_at is null or e.expires_at > statement_timestamp())
      and (p_category = 'all'
        or (p_category = 'commerce' and e.category in (
          'Comércio', 'Onde comer?', 'Saúde', 'Imóveis', 'Veículos', 'Pets',
          'Beleza', 'Academias', 'Educação', 'Hospedagem', 'Tecnologia'
        ))
        or (p_category = 'services' and e.category in ('Serviços', 'Profissionais')))
      and not exists (
        select 1 from unnest(terms) as term
        where public.search_pilot_unaccent(
          public.search_pilot_document_text(e.name, e.summary, e.category, e.subcategory)
        ) not like '%' || term || '%'
      )
  ), page_candidates as (
    select e.*
    from eligible e
    where p_cursor_id is null or e.rank_value < cursor_rank
      or (e.rank_value = cursor_rank and e.id > p_cursor_id)
    order by e.rank_value desc, e.id asc
    limit p_page_size + 1
  ), page_meta as (
    select count(*) > p_page_size as more from page_candidates
  )
  select p.id, p.name, p.summary, p.category, p.subcategory, p.image_url,
    m.more
  from page_candidates p cross join page_meta m
  order by p.rank_value desc, p.id asc
  limit p_page_size;
end;
$function$;

create or replace function public.get_public_establishment(p_id text)
returns table (
  id text,
  name text,
  summary text,
  category text,
  subcategory text,
  image_url text
)
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_id is null or length(p_id) > 65 or p_id !~ '^pilot-[a-z0-9-]{1,60}$' then
    raise exception using errcode = '22023', message = 'invalid establishment id';
  end if;
  return query
  select e.id, e.name, e.summary, e.category, e.subcategory, e.image_url
  from public.public_search_establishments e
  where e.id = p_id
    and e.published = true and e.active = true
    and e.deleted_at is null
    and (e.expires_at is null or e.expires_at > statement_timestamp());
end;
$function$;

-- SECURITY DEFINER ownership and access are explicit, never inherited from
-- ambient migration defaults. Bodies contain no dynamic SQL and set an empty
-- search_path; every non-system object above is schema-qualified.
alter function public.search_public_establishments(text, text, integer, text)
  owner to postgres;
alter function public.get_public_establishment(text) owner to postgres;

revoke all on function public.search_public_establishments(text, text, integer, text)
  from public, anon, authenticated;
revoke all on function public.get_public_establishment(text)
  from public, anon, authenticated;
revoke all on function public.search_pilot_unaccent(text)
  from public, anon, authenticated;
revoke all on function public.search_pilot_document_text(text, text, text, text)
  from public, anon, authenticated;

grant execute on function public.search_public_establishments(text, text, integer, text)
  to anon;
grant execute on function public.get_public_establishment(text)
  to anon;
