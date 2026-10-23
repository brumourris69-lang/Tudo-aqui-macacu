# Supabase Search Pilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an isolated Android debug app that exercises the existing public establishment search UI against a hosted Supabase Free project seeded only with fictitious records.

**Architecture:** Add a `supabasePilotDebug`-only app ID and separate Dart entrypoint that starts the existing `UniversalSearchPage` with injected Supabase search/detail transports; it must never initialize or fall back to Firebase. Store only a narrow public search table and expose bounded, explicit-column RPCs protected by RLS and anonymous-role grants.

**Tech Stack:** Flutter/Dart, existing `http` package and `UniversalSearchRepository` contract, Android Gradle Kotlin DSL, Supabase Postgres/PostgREST RPC, Supabase CLI, Node built-in test runner.

**Spec:** `docs/superpowers/specs/2026-10-19-supabase-search-pilot-design.md`

## Global Constraints

- Scope is public establishment search and detail only; no other module is migrated.
- Use one separate hosted Supabase Free project with fictitious seed records only; do not enable paid billing.
- Keep Firebase production, `searchLocal`, staging, Rules, Functions, Auth, App Check, and production gates unchanged.
- Do not put a service-role key, database password, or other administrative credential in Flutter or tracked files.
- Use the existing `http` dependency; do not add a Flutter package.
- Missing, malformed, or mismatched pilot configuration must fail closed, with no Firebase fallback.
- Build only the debug pilot variant with a unique application ID; preserve existing app variants and data.
- Search and detail responses use explicit public columns; unknown/private fields are never copied or returned.
- Apply migrations only after verifying the linked project reference is the newly created pilot and its plan is Free.

## Review Focus

1. Missing or malformed URL, key, project ref, or a production-matching project must block startup before network use — pin with `supabase_search_pilot_config_test.dart` and bootstrap tests.
2. Query boundary values (empty, over 80 characters, 0/5 terms, and terms shorter than 2 or longer than 24) must be rejected before RPC — pin with repository tests.
3. Replayed, malformed, or cross-query/category cursors must not skip, duplicate, or broaden results — pin with cursor tests and the hosted smoke test.
4. Non-2xx, timeout, malformed JSON, or unavailable project must show bounded error UI and never invoke Firebase — pin with fake HTTP and bootstrap/UI tests.
5. Unpublished/inactive rows and unapproved columns must remain inaccessible through both RPCs and direct REST access — pin with SQL policy/grant checks and anonymous-role hosted integration tests.

---

### Task 1: Prepare the isolated hosted pilot project and CLI

**Files:**
- No repository files changed in this task.

**Interfaces:**
- Produces: verified Free-tier Supabase project reference and HTTPS API URL, held only in local untracked configuration; no production or Firebase project identifiers are accepted.

- [x] Owner authenticated the official Supabase CLI; verified project `tudo-aqui-macacu-search-pilot` (`zzxvcunuwbhglzzklsrl`), region `sa-east-1`, Free plan, Healthy status, and Nano compute. Local ignored config contains only project ref, URL, and client-visible publishable key.
- [x] Confirmed the project was empty before migration and linked the CLI only to this exact project. CLI link metadata remains ignored under `supabase/.temp/`.

**Validation:** Confirm the dashboard shows the Free plan and the project reference matches the local file; no database objects or app config are written yet.

### Task 2: Add the public-only search schema, RPCs, and fictitious fixtures

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/20261019000100_search_public_establishments.sql`
- Create: `supabase/tests/database/search_public_establishments.sql`
- Test: `tools/supabase_search_pilot.integration.test.mjs`

**Interfaces:**
- Produces RPC `search_public_establishments(p_query text, p_category text, p_page_size integer, p_cursor_id text)`, returning named public columns plus `has_more boolean`.
- Produces RPC `get_public_establishment(p_id text)`, returning the named public columns only, or no row when unavailable.
- The only searchable categories are `all`, `commerce`, and `services`; unsupported existing global-search filters are disabled in the pilot UI.
- Search cursor is the last establishment ID from the same normalized query/category; ordering is deterministic by rank then ID and the server revalidates that cursor against the same eligible result set.

- [x] Write database tests for published+active visibility, unpublished/inactive denial, explicit columns, query validation, each supported category, page size 1–20 boundaries, stable cursor order, cross-query/category cursor rejection, detail ID validation, and no private columns.
- [x] Executed all 28 pgTAP assertions against the hosted pilot in a rollback-wrapped transaction using `supabase db query`; standard `supabase test db --linked` remains unavailable because Docker/Podman is absent.
- [x] Add the narrow table and deterministic fictional seed rows in the migration; include only ID, name, summary, category, subcategory, image URL, and publication/activity flags.
- [x] Add an accent-insensitive GIN search index; validate bounded queries and page size; use stable keyset pagination and explicit output columns.
- [x] Enable RLS, grant the anonymous API role only approved SELECT columns and the two RPC executions, and ensure policies expose only published+active rows.
- [x] Add SQL tests proving direct table reads are row/column limited and RPC detail/search use explicit public fields, never row JSON.
- [x] Run the hosted Node integration suite and `git diff --check`; all 28 database assertions also pass. Standard local `supabase test db` remains unavailable without Docker.

**Validation:** SQL policy tests pass locally, or their Docker limitation is explicitly recorded; static review confirms the fixture table contains no real records and every RPC return column is enumerated.

### Task 3: Add a fail-closed debug flavor and independent entrypoint

**Files:**
- Modify: `android/app/build.gradle.kts`
- Create: `lib/core/config/supabase_search_pilot_config.dart`
- Create: `lib/main_supabase_pilot.dart`
- Test: `test/supabase_search_pilot_config_test.dart`
- Test: `test/supabase_search_pilot_bootstrap_test.dart`

**Interfaces:**
- Produces `SupabaseSearchPilotConfig.fromDefines({required bool debug, required String projectRef, required String url, required String anonKey})`, which validates the exact HTTPS host `<projectRef>.supabase.co`, project-ref syntax, debug-only execution, and non-production/non-demo identity.
- Produces Android flavor `supabasePilot` with application ID `br.com.tudoaquimacacu.tudo_aqui_macacu.supabasepilot`, debug variants only.
- Entry point reads `SUPABASE_PILOT_PROJECT_REF`, `SUPABASE_PILOT_URL`, and `SUPABASE_PILOT_ANON_KEY` defines and constructs only the search pilot; it does not call `Firebase.initializeApp()`.

- [x] Add config tests for missing/invalid values, non-HTTPS URL, URL/ref mismatch, known Firebase/demo IDs, and release mode; invalid config is rejected before transport creation.
- [x] Add bootstrap tests proving the pilot entrypoint does not initialize Firebase and fails closed before building search UI on invalid configuration.
- [x] Add a `supabasePilot` flavor with a unique suffix, mutually exclusive with `searchLocal` and `staging`; disable Google Services processing and all non-debug variants.
- [x] Implement the config parser with no fallback values and validate it before creating any transport.
- [x] Implement the standalone pilot root using the existing Tudo Aqui theme and `UniversalSearchPage`, injecting its repository and business detail resolver.
- [x] Run focused Flutter tests and Android Gradle task configuration checks without building release variants.

**Validation:** Invalid config displays a local blocked state and performs no network or Firebase initialization; existing normal/searchLocal/staging flavor configuration remains unchanged.

### Task 4: Implement the Supabase RPC repository and safe detail resolver

**Files:**
- Create: `lib/features/search/repositories/supabase_search_pilot_repository.dart`
- Modify: `lib/features/search/pages/universal_search_page.dart`
- Test: `test/supabase_search_pilot_repository_test.dart`
- Test: `test/supabase_search_pilot_page_test.dart`

**Interfaces:**
- `SupabaseSearchPilotRepository implements UniversalSearchRepository`, constructed with validated config and injectable `http.Client`.
- `Future<Business?> getPublicBusiness(String id)` resolves only through `get_public_establishment` and builds the existing `Business` model from approved columns.
- `UniversalSearchPage` gains an optional supported-filter set whose default preserves all existing filters; the pilot passes only all/commerce/services.

- [x] Write fake-client tests for RPC body/path/header shape (public anon key only), decode, filters, cursor, and details by ID.
- [x] Add invalid-ID/filter, server/transport, timeout, malformed/oversized-response, and public-field allowlist tests with no Firebase fallback.
- [x] Add page tests proving supported filters, unchanged default filters, and injected detail resolution.
- [x] Implement RPC calls over the existing `http` package, fixed RPC paths, explicit JSON projection decoding, timeout, and sanitized error mapping.
- [x] Derive the cursor from the last establishment ID only when `has_more` is true and bind it to `request.queryKey`.
- [x] Ensure the adapter has no Firebase dependency and detail resolution is injected.
- [x] Run focused Flutter tests and existing universal-search contract tests.

**Validation:** Fake tests demonstrate the existing universal-search contract and detail route work with the adapter, while all Firebase-backed defaults remain unchanged outside pilot injection.

### Task 5: Apply and verify the fictitious hosted Supabase dataset

**Files:**
- Modify: `supabase/migrations/20261019000100_search_public_establishments.sql` only if test findings require a reviewed fix.
- Test: `tools/supabase_search_pilot.integration.test.mjs`
- Local only: ignored `.env.supabase-pilot` or equivalent.

**Interfaces:**
- The migration is applied only to the verified pilot project from Task 1; the integration test uses the public anon key and HTTPS API URL only.

- [x] Link and dry-run only after exact project identity was verified; dry-run listed only the approved migration.
- [x] Applied the single migration and fictional seed once to the verified empty Free pilot project.
- [x] Hosted Node integration: 5 passed, 0 failed, 0 skipped; included RPC, cursor, invalid input, RLS, direct REST projection, and detail checks.
- [x] Verified remote migration, schema, RLS/grants, and aggregate fixture counts (5 fictional rows, 3 public and active).
- [x] Recorded one sanitized HTTP sample (search 200/762 ms/641 bytes/3 rows; detail 200/67 ms/198 bytes/1 row). This is a smoke sample, not a cost or capacity estimate.

**Validation:** All remote requests use the pilot project host, only fake rows exist, negative RLS/projection checks pass, and no service-role credential is used by the integration test.

### Task 6: Build and exercise the pilot APK in MEmu

**Files:**
- No production app files beyond Tasks 3–4; generated APK stays in ignored build output.
- Test: `test/supabase_search_pilot_page_test.dart` plus hosted integration evidence.

**Interfaces:**
- Build artifact: `build/app/outputs/flutter-apk/app-supabasePilot-debug.apk` (verify actual Gradle/Flutter artifact path before reporting).
- Build defines: `SUPABASE_PILOT_PROJECT_REF`, `SUPABASE_PILOT_URL`, `SUPABASE_PILOT_ANON_KEY`; the publishable/anon key is client-visible but never printed or committed.

- [x] Run focused Flutter pilot tests (19 passed), `flutter analyze --no-pub`, and `git diff --check` locally.
- [x] Build `supabasePilot` debug with the verified project identity and ignored local configuration; APK output is `build/app/outputs/flutter-apk/app-supabasepilot-debug.apk`.
- [x] Verify the APK package ID is `br.com.tudoaquimacacu.tudo_aqui_macacu.supabasepilot`; install with `adb install -r` to the existing MEmu instance, preserving other app variants and data.
- [x] Exercise hosted search and detail in MEmu using fictitious rows; Android Back returned to results. MEmu remains open on results.
- [x] Record build integrity and visual evidence outside the repository; no Firebase initialization/fallback is present in the pilot entrypoint.
- [x] Review local changes; original dirty and untracked work remains present. No commit or push.

## Execution ledger update — 2026-10-20

- All six tasks completed locally and against the owner-authorized isolated Supabase pilot project. Firebase production/demo, billing settings, and unrelated remote resources were not accessed or changed.
- Project identity is verified as `tudo-aqui-macacu-search-pilot` (`zzxvcunuwbhglzzklsrl`), region `sa-east-1`, Free plan. Only the public publishable key is used by the debug app and client integration test; no service-role key is in the app or repository.
- Applied only `20261019000100_search_public_establishments.sql`; remote fixture count is five fictitious rows, three eligible for public search. The integration test verified visible rows and projected columns.
- Database validation: 28/28 pgTAP assertions passed through a transaction that explicitly rolls back. The standard `supabase test db --linked` command is unavailable because Docker/Podman is not installed; no components were installed.
- Hosted Node integration: 5 passed, 0 failed, 0 skipped. Flutter pilot tests: 19 passed. `flutter analyze --no-pub` and `git diff --check` passed.
- APK build succeeded (Flutter 3.47.3/Dart 3.13.3); artifact SHA-256 is `748BC42123FD7C1F39653F47AF337BA2342405350762E1ADB973EDFA2A63FD82`, size 223,679,605 bytes, package `br.com.tudoaquimacacu.tudo_aqui_macacu.supabasepilot`.
- MEmu test succeeded for one search (`exemplo`), opening the fictional business detail, and returning to results. Evidence is stored outside the repository at `C:\Users\tiago\AppData\Local\TudoAquiMacacu\visual-tests\supabase-pilot-20261020-005029\`.
- The hosted project remains a Free Nano pilot, not production-ready. One smoke sample does not establish cost savings, capacity, uptime, or production security readiness. Signed opaque cursors, operational monitoring/backups, dataset refresh behavior, and broader production requirements remain future work.
- Existing Git changes were preserved. This task made only the pilot-specific `.gitignore` exclusion for `supabase/.temp/` and added direct anonymous REST visibility coverage to the Node integration test; no commit or push was made.

**Validation:** The distinct pilot APK searches and opens a fictitious establishment using only the hosted pilot; Firebase production and demo are not initialized or contacted, and all existing variants retain their behavior.

## Execution Handoff

This is a tightly coupled, six-task plan with cross-cutting environment-isolation risks. Native execution in one session is the recommended approach; use one writer for each task and a final independent review. No task authorizes using Firebase production, changing its configuration, or committing/pushing.

## Final Plan Review

- Spec coverage: schema/RLS/RPCs, app variant, config isolation, repository, detail route, hosted integration, device test, metrics, and Git preservation all have explicit tasks.
- Step scan: each checklist item maps to one implementation, test, setup, or verification action; no code behavior is left unspecified beyond routine implementation details.
- Type consistency: the repository implements the existing `UniversalSearchRepository`; the detail resolver is `Future<Business?>`; cursor behavior uses the existing `BusinessSearchCursor` and result contract.
- Review focus: all five failure classes above are tied to named unit, UI, SQL, or hosted integration tests.
- Proportion: tasks are sequenced by dependency; Docker is not installed by this plan, and a hosted test replaces local Supabase integration when Docker is unavailable.

## Local pgTAP completion — 2026-10-20

- Docker Desktop 29.8.2 was already installed. For this run only, `portBindingBehavior` was temporarily set to `default-local-port-binding`; the original `%APPDATA%/Docker/settings-store.json` was backed up and restored byte-for-byte (SHA-256 `8770858619DD036B702D6AD5BAE24A6AB1444EC437E6BA0FD9FAC0CAA1C36F25`). No firewall or project configuration was changed.
- Started only the local Supabase Postgres service for `tudo-aqui-macacu-search-pilot`; Docker published its port only on `127.0.0.1:54322` and `::1:54322`. The CLI was invoked with explicit `--local` and local workdir flags; no linked/hosted database command ran.
- Confirmed the local database initially had no pilot migration or public pilot table and no user-created relations. Applied only the pending local migration `20261019000100_search_public_establishments.sql` with `migration up --local` (no reset).
- `supabase test db --local supabase/tests/database/search_public_establishments.sql`: **28 passed, 0 failed**. The test file runs inside `BEGIN`/`ROLLBACK`; a post-test query confirmed 5 original fictional seed rows remain and 0 `pilot-test-*` fixtures remain.
- Stopped only the local project with `supabase stop --project-id tudo-aqui-macacu-search-pilot` (without `--no-backup` or `--all`). The named volume and downloaded images are retained; no containers remain and port 54322 is free. Docker Desktop is running with its original settings restored.
- This closes the previously pending local pgTAP validation gap. Hosted pilot and Android results remain as recorded above; this does not establish production readiness or cost/capacity characteristics.
