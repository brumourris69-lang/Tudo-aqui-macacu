# Supabase Search Pilot Design

## Goal

Validate whether a hosted Supabase backend can serve the existing public Global Search experience in the real Tudo Aqui Macacu Flutter application, using only fictitious records. Measure practical query latency, response size, and the amount of work required before deciding whether a broader backend migration is justified.

This is a search-only proof of concept. It does not migrate or replace Firebase Authentication, administration, jobs, tourism, utilities, notifications, storage, or any other module. The current Firebase project and the original application checkout remain untouched.

## Current repository context

- `UniversalSearchRepository` and `BusinessSearchRequest` already define a transport-independent search contract, including query validation, filters, a result limit of 20, and cursor validation.
- `SearchResult` is an explicit public display model. It discards unrecognized fields and constrains result types and navigation destinations.
- The current local implementation calls the Firebase Functions Emulator. The normal `main()` initializes the configured Firebase app, so a pilot must not reuse the normal application ID or silently fall through to the production bootstrap.
- `http` is already a Flutter dependency; no additional client package is needed for an RPC-only read pilot.

## Proposed approach

Create a separate debug-only Android pilot flavor with a distinct application ID and a fail-closed Supabase configuration. Its entrypoint must verify the expected pilot flavor and non-production Supabase project identity before enabling the search route. It must not initialize Firebase against the production project. Search requests use a small adapter implementing `UniversalSearchRepository`, backed by the existing `http` dependency and Supabase PostgREST RPC. The existing search widgets and `SearchResult` decoder remain the UI and contract boundary.

The first pilot covers public establishment search and opening a public detail for the same fictitious record. The hosted project contains a small, explicitly fictitious seed dataset. Results use the existing establishment `SearchResult` contract; pagination and filters are honored. A second bounded RPC resolves a detail by ID from the same Supabase dataset. The pilot must never route a Supabase result into a Firebase-backed business lookup.

The original Firebase-backed flavor, `searchLocal`, the normal app, and all existing production gates remain unchanged. No Firebase production endpoint or data is used by the pilot.

## Supabase data and search contract

- Create a narrow `public_search_establishments` table containing only fictitious public fields needed by the existing result and detail experience: stable ID, display name, summary, category, subcategory, approved HTTPS image URL (empty for seed data), plus publication/active flags. Do not copy private or unknown fields into this pilot table.
- Add a GIN expression index over the approved searchable text fields; do not store or return a search-vector column.
- Expose bounded Postgres RPCs `search_public_establishments(p_query, p_category, p_page_size, p_cursor_id)` and `get_public_establishment(p_id)`. Search enforces the existing client constraints: normalized query terms, maximum 80 characters, one to four terms, each 2–24 characters, page size 1–20, stable keyset pagination, and a fixed result projection. Detail accepts only a validated stable ID and returns the same approved public fields. The `p_` argument names avoid collisions with named output columns and are the exact JSON keys sent to PostgREST.
- Enable Row Level Security and grant the anonymous API role only the required `SELECT` columns and RPC execution. RLS policies expose only published and active pilot rows. The table contains no private columns, and RPC responses are explicit columns, never row JSON. No service-role key is present in Flutter.
- Use separate remote project configuration and local untracked secrets. Project URL and publishable/anon key are treated as client-visible values; service-role credentials stay in a local secure environment and are never bundled, logged, or committed.

## Isolation and failure behavior

- A dedicated debug flavor and unique Android application ID prevent installation over the normal app or `searchLocal`.
- Missing, malformed, or production-matching pilot configuration fails closed before search is enabled. There is no Firebase fallback and no implicit switch to another backend.
- Search requests are HTTPS to the explicitly configured Supabase project. Only the publishable/anon key is sent as the API key; no administrator credential is sent by the client.
- Errors are converted to bounded user-facing states. Logs may include operation class, status code, and duration only; they must not contain query text, response bodies, keys, or user data.
- The pilot uses no real business records, user accounts, or production data. The hosted Free project may pause after inactivity and is not a production availability commitment.

## Validation and success criteria

1. Unit tests for request validation, RPC encoding, response decoding, cursor handling, detail lookup, non-2xx responses, timeouts, and the absence of Firebase fallback.
2. SQL checks for RLS and grants: anonymous can execute the bounded RPCs and sees only published/active fictitious rows; table access is limited to approved public columns; malformed IDs and excessive page sizes are rejected.
3. Integration test against the isolated hosted Supabase project using only the approved seed fixtures.
4. Build the dedicated pilot debug APK, verify its application ID and configured Supabase project identity, and install it alongside existing app variants without clearing their data.
5. In the actual Flutter search UI, run representative valid searches, filters, and pagination; record sanitized latency and response-size measurements. Do not claim a cost advantage without comparing these observations and expected monthly volume against Firestore reads and egress.
6. Preserve all existing Git changes and report the final status. Do not commit or push as part of the pilot unless separately authorized.

## Non-goals

- Full Firebase-to-Supabase migration.
- Importing or copying real Firebase data.
- Changing Firebase Rules, Functions, Auth, App Check, production gates, or existing app flavors.
- Adding administrator, write, upload, job-private, or notification endpoints to Supabase.
- Treating a successful search pilot as approval to launch on Supabase.

## Decisions requiring review before implementation

- Approve the search-only scope and dedicated debug flavor.
- Approve creating one hosted Supabase Free project containing fictitious seed data. No billing upgrade is in scope.
- Approve using the existing `http` package for the RPC adapter, avoiding a new Flutter dependency.
- Approve stopping before any paid plan, production-data import, production app ID change, or full backend migration.
