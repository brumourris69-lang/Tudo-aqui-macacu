# Hybrid Administrative Establishments Implementation Plan

> **For agentic workers:** This plan is executed in the current session using the native single-writer workflow; no parallel edits are used.

**Goal:** Add a local Supabase Edge Function that authorizes Firebase administrators and atomically writes canonical Firestore establishment changes with reconciliation events.

**Architecture:** A Deno entrypoint wires a testable JavaScript handler to a Firebase Secure Token JWK resolver and a Firestore REST transaction adapter. The function verifies the Firebase bearer token itself, reads `admin_authorizations/{uid}` inside the same transaction as the source/outbox writes, and never calls Supabase SQL or writes the public projection in this step.

**Tech Stack:** Supabase Edge Functions (Deno), JavaScript ES modules, WebCrypto, Firestore REST API, Node built-in test runner.

**Spec:** User request “TUDO AQUI MACACU — ARQUITETURA HÍBRIDA | ETAPA 05”.

## Global Constraints

- Fixed Firebase project: `tudo-aqui-macacu`.
- Operations: `create`, `update`, `unpublish`; no physical deletion.
- No hosted Firebase/Supabase calls, deployment, dependency installation, Flutter/Rules/migration changes, or data changes during this task.
- Keep Supabase gateway JWT verification disabled only for this function; verify Firebase tokens in the handler.
- Keep canonical Firestore writes and `catalog_outbox` event in one Firestore transaction.

## Review Focus

- Firebase token from another project or anonymous provider must fail before Firestore access — handler/auth tests.
- Missing, pending, disabled, revoked, malformed, or unavailable Admin authorization must fail closed — handler tests.
- Replayed request IDs and concurrent stale versions must not duplicate or overwrite a mutation — transaction tests.
- Unknown/private content fields must not enter the public projection — validation/projection tests.
- Firestore REST failures must be sanitized and must not expose service credentials or response bodies — REST adapter tests.

---

### Task 1: Pin handler and projection contracts

**Files:**
- Create: `supabase/functions/_shared/admin_establishments.test.mjs`
- Create: `supabase/functions/_shared/admin_establishments.mjs`

**Interfaces:** handler receives injected identity verifier, Admin authorizer, transaction store, project ID, and UUID generator. Store transaction exposes `get`, `create`, and conditional `update` operations.

- [x] Tests written and run red before implementation.
- [x] Implement request validation, authorization, replay handling, canonical mutations, outbox creation, and explicit projection.
- [x] Verify tests green.

### Task 2: Pin secure remote adapters

**Files:**
- Create: `supabase/functions/_shared/firebase_signing_keys.mjs`
- Create: `supabase/functions/_shared/firebase_signing_keys.test.mjs`
- Create: `supabase/functions/_shared/firebase_firestore_rest.mjs`
- Create: `supabase/functions/_shared/firebase_firestore_rest.test.mjs`

- [x] Test JWK cache and malformed/unavailable key responses.
- [x] Test service-account token exchange with injected fetch and no logging.
- [x] Test Firestore transaction reads and one atomic commit with create/update preconditions.
- [x] Implement adapters and verify tests green.

### Task 3: Add the isolated Edge Function configuration and entrypoint

**Files:**
- Create: `supabase/functions/manage-establishments/index.ts`
- Modify: `supabase/config.toml`

- [x] Configure only `manage-establishments` with `verify_jwt = false`.
- [x] Wire Deno environment secrets to the tested modules; fail closed if absent or for the wrong project.
- [x] Confirm no Supabase service-role key, Firebase service-account credential, or external project ID is committed.

### Task 4: Record integration audit and deployment prerequisites

**Files:**
- Create: `docs/superpowers/specs/2026-10-20-hybrid-admin-establishments-backend.md`

- [x] Document current catalog/editor/importer contracts, Cloud Functions still in use, direct-write bypasses, schema ID/category mismatch, token gateway behavior, secrets/IAM prerequisites, and future Flutter work.

### Task 5: Verify local scope

- [x] Run all handler/adapter/shared-auth Node tests (42 passed) and the local pilot harness; `node --check` and `git diff --check` pass. One hosted test is skipped with remote credentials unset.
- [x] Confirm no hosted service request, migration, emulator, or install occurred. The temporary Supabase CLI is available, but Deno is absent and Docker Engine is stopped, so Edge runtime verification remains pending.
- [x] Compare the local Git inventory against the start-of-task inventory; the 123-path baseline and four deleted TOMLs remain preserved, with only this task's files added/modified.
