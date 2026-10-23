-- Prepare (but do not cut over) the restricted V2 writer identity. The current
-- consumer still calls PostgREST as service_role, so this migration preserves
-- that compatibility. Legacy EXECUTE revocation is a separately gated manual
-- operation outside supabase/migrations, after the replacement is proven.

create role catalog_writer_v2
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls
  connection limit 2;
alter role catalog_writer_v2 set search_path = '';
alter role catalog_writer_v2 set statement_timeout = '8s';
alter role catalog_writer_v2 set lock_timeout = '3s';
alter role catalog_writer_v2 set idle_in_transaction_session_timeout = '10s';

-- A dedicated login identity has no password in migration history. Provision
-- its password out-of-band only after the concrete driver and pooler are tested.
-- INHERIT makes only the executor role's two EXECUTE grants available by default.
create role catalog_writer_v2_login
  login inherit nosuperuser nocreatedb nocreaterole noreplication nobypassrls
  connection limit 2 password null;
alter role catalog_writer_v2_login set search_path = '';
alter role catalog_writer_v2_login set statement_timeout = '8s';
alter role catalog_writer_v2_login set lock_timeout = '3s';
alter role catalog_writer_v2_login set idle_in_transaction_session_timeout = '10s';

create role catalog_writer_v2_owner
  nologin nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls;
alter role catalog_writer_v2_owner set search_path = '';
alter role catalog_writer_v2_owner set statement_timeout = '8s';
alter role catalog_writer_v2_owner set lock_timeout = '3s';

-- On managed PostgreSQL 16+, the migration role's automatic ADMIN membership
-- in a role it created does not necessarily include SET. Grant it temporarily
-- so ownership can be transferred, then revoke it immediately below.
grant catalog_writer_v2_owner to postgres with set true;

grant usage on schema public to catalog_writer_v2;
grant usage on schema public to catalog_writer_v2_login;
grant usage on schema public to catalog_writer_v2_owner;
grant catalog_writer_v2 to catalog_writer_v2_login;
grant connect on database postgres to catalog_writer_v2_login;

-- Fail closed if the exposed schema inherits CREATE from PUBLIC. Revoking it
-- globally would be a broader project change and is deliberately not attempted.
do $guard_public_schema$
begin
  if has_schema_privilege('catalog_writer_v2', 'public', 'CREATE')
    or has_schema_privilege('catalog_writer_v2_owner', 'public', 'CREATE') then
    raise exception 'public schema CREATE is inherited; review grants before provisioning catalog writer';
  end if;
end;
$guard_public_schema$;

grant select, insert, update on table public.public_establishment_catalog_v2
  to catalog_writer_v2_owner;
grant select, insert on table public.catalog_tombstones_v2
  to catalog_writer_v2_owner;
-- The tombstone writer uses SELECT ... FOR UPDATE to serialize replays. UPDATE
-- is required by PostgreSQL for that lock mode; the immutable trigger rejects
-- any actual tombstone mutation, and the role cannot log in.
grant update on table public.catalog_tombstones_v2 to catalog_writer_v2_owner;

create policy catalog_writer_v2_owner_projection_select
  on public.public_establishment_catalog_v2
  for select to catalog_writer_v2_owner using (true);
create policy catalog_writer_v2_owner_projection_insert
  on public.public_establishment_catalog_v2
  for insert to catalog_writer_v2_owner with check (true);
create policy catalog_writer_v2_owner_projection_update
  on public.public_establishment_catalog_v2
  for update to catalog_writer_v2_owner using (true) with check (true);
create policy catalog_writer_v2_owner_tombstone_select
  on public.catalog_tombstones_v2
  for select to catalog_writer_v2_owner using (true);
create policy catalog_writer_v2_owner_tombstone_insert
  on public.catalog_tombstones_v2
  for insert to catalog_writer_v2_owner with check (true);
create policy catalog_writer_v2_owner_tombstone_update
  on public.catalog_tombstones_v2
  for update to catalog_writer_v2_owner using (true) with check (true);

-- CHECK constraints execute these validators as the definer role.
grant execute on function public.catalog_firestore_id_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_https_url_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_map_url_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_phone_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_whatsapp_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_instagram_valid_v2(text) to catalog_writer_v2_owner;
grant execute on function public.catalog_text_array_valid_v2(text[], integer, integer)
  to catalog_writer_v2_owner;
grant execute on function public.catalog_https_array_valid_v2(text[], integer)
  to catalog_writer_v2_owner;

-- PostgreSQL requires CREATE on the containing schema to transfer ownership.
-- Remove it immediately after the transfer; the non-login owner needs only USAGE.
grant create on schema public to catalog_writer_v2_owner;
alter function public.apply_establishment_projection_v2(jsonb)
  owner to catalog_writer_v2_owner;
alter function public.apply_establishment_tombstone_v2(jsonb)
  owner to catalog_writer_v2_owner;
revoke create on schema public from catalog_writer_v2_owner;

-- Ownership has moved, so perform subsequent function configuration and ACL
-- changes as the new owner. The migration role is only temporarily allowed to
-- SET ROLE for this block.
set role catalog_writer_v2_owner;

alter function public.apply_establishment_projection_v2(jsonb)
  set statement_timeout = '8s';
alter function public.apply_establishment_projection_v2(jsonb)
  set lock_timeout = '3s';
alter function public.apply_establishment_tombstone_v2(jsonb)
  set statement_timeout = '8s';
alter function public.apply_establishment_tombstone_v2(jsonb)
  set lock_timeout = '3s';

-- Restrict the two functions to the dedicated executor while retaining the
-- existing service_role grant during the compatibility phase. The operational
-- cutover script revokes service_role only after the replacement is live.
revoke all on function public.apply_establishment_projection_v2(jsonb)
  from public, anon, authenticated, catalog_writer_v2, catalog_writer_v2_login;
revoke all on function public.apply_establishment_tombstone_v2(jsonb)
  from public, anon, authenticated, catalog_writer_v2, catalog_writer_v2_login;
grant execute on function public.apply_establishment_projection_v2(jsonb)
  to catalog_writer_v2;
grant execute on function public.apply_establishment_tombstone_v2(jsonb)
  to catalog_writer_v2;
reset role;
revoke catalog_writer_v2_owner from postgres;

-- The executor role must never gain table privileges through this migration.
revoke all on table public.public_establishment_catalog_v2, public.catalog_tombstones_v2
  from catalog_writer_v2;

comment on role catalog_writer_v2 is
  'NOLOGIN executor role for only the two private catalog V2 writer RPCs.';
comment on role catalog_writer_v2_login is
  'Dedicated LOGIN identity inheriting only catalog_writer_v2; set its password out-of-band after driver validation.';
comment on role catalog_writer_v2_owner is
  'Non-login SECURITY DEFINER owner with narrowly scoped RLS-backed catalog table access.';
