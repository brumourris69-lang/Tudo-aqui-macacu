# Staging Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route public app reads through the already allowlisted secure contracts in an isolated Android `stagingDebug` flavor, with staging-only Firebase Functions registration and production/demo gates unchanged.

**Architecture:** Add an explicit staging identity/ready gate on Flutter and a separate staging backend gate. Reuse `listPublicContent` and `getPublicContentDetail`; add staging-only `getPublicJob` using the existing visibility and allowlisted projection. Android staging requires its own verified Google Services file and package id; with no remote staging project configured, startup/build fail closed.

**Tech Stack:** Flutter/Dart, Android Gradle Kotlin DSL, Firebase Auth/App Check/Functions, Node.js Functions tests.

**Spec:** `docs/superpowers/specs/2026-10-15-security-containment-staging-design.md`

## Global Constraints

- Do not access or modify the real Firebase project, deploy, migrate, create a remote project, install dependencies, or start Emulator/MEmu.
- Keep `SecureBackend.productionAuthorized == false`, the production allowlist, and `SECURE_BACKEND_ENABLED` behavior unchanged.
- Keep `searchLocal` demo-only and never use it as a staging fallback.
- Staging requires an explicit expected project id matching native Firebase config and runtime Firebase identity; reject demo and production ids and all Emulator hosts.
- Public data uses explicit collection projections and current visibility checks; no public direct-Firestore fallback.
- Preserve existing untracked files and the Rules candidate/harnesses.
- No commit or push.

## Review Focus

- Missing or mismatched staging config must fail before network calls (Dart identity tests and Gradle configuration guard).
- Staging opt-in must not register endpoints in demo or production (Node environment-gate table tests).
- Staging must not inherit demo callable transport or synthetic App Check (Dart transport policy tests).
- Job detail must not expose private, unapproved, or unknown fields (Node projection tests).
- Existing normal and searchLocal behavior must remain unchanged (existing tests plus explicit regression checks).

---

### Task 1: Staging identity and Flutter transport

**Files:**
- Create: `lib/core/config/staging_environment.dart`
- Modify: `lib/core/content/secure_backend.dart`
- Modify: `lib/core/auth/app_auth.dart`
- Modify: `lib/core/auth/app_check_setup.dart`
- Modify: `lib/features/jobs/repositories/public_job_details_repository.dart`
- Test: `test/staging_environment_test.dart`
- Test: `test/staging_backend_test.dart`
- Test: `test/public_job_details_repository_test.dart`

**Interfaces:**
- `StagingEnvironment.enabled` is true only for Flutter flavor `staging`.
- `StagingEnvironment.validateIdentity(...)` checks flavor, no LocalSearch overlap, exact expected/runtime project match, and the fixed staging Android package.
- `StagingEnvironment.markReady(...)` is called only after native Firebase identity validation; `requireReady()` fails otherwise.
- A staging transport allowlist is separate from the unchanged production allowlist and contains only public listing/detail/job callables.

- [ ] Add failing identity, fail-closed transport, Auth/App Check gate tests.
- [ ] Run targeted Flutter tests and observe expected failures.
- [ ] Implement the staging identity and transport paths; preserve normal/searchLocal paths.
- [ ] Run targeted tests; assert normal `getPublicJob` remains rejected before network access.
- [ ] Run relevant existing repository/auth/App Check tests.

### Task 2: Functions staging gate and public job callable

**Files:**
- Create: `functions/secure_staging_environment.js`
- Modify: `functions/public_content.js`
- Modify: `functions/index.js`
- Test: `functions/secure_staging_environment.test.js`
- Test: `functions/public_content.test.js` (or the existing focused public-content test file)
- Modify: `functions/package.json` only if required to include syntax checks for new files.

**Interfaces:**
- `stagingBackendAllowed({ env, adminProjectId })` requires explicit staging opt-in, a separately supplied expected staging id matching both runtime project identities, rejects production/demo ids, and rejects every Emulator host/flag.
- Staging registers only `listPublicContent`, `getPublicContentDetail`, and `getPublicJob`; the default production registrar and demo registrar remain unchanged.
- `getPublicJob` uses Auth, enforced App Check, a per-user quota, visibility revalidation, and the strict jobs projection; it never reads `job_private`.

- [ ] Add failing Node tests for positive/negative staging gate combinations and endpoint registration/projection.
- [ ] Run focused tests and observe expected failures.
- [ ] Implement an independently gated staging registration and staging-only job detail callable.
- [ ] Run focused and full Node tests, then `npm run check` using the existing runtime only.

### Task 3: Android `stagingDebug` flavor and visible environment marker

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Create: `lib/core/widgets/staging_environment_banner.dart`
- Modify: `lib/main.dart`
- Test: `test/staging_flavor_contract_test.dart`
- Test: `test/staging_environment_banner_test.dart`

**Interfaces:**
- Staging variants are created only for explicit staging build requests; only `stagingDebug` is enabled.
- `android/app/src/staging/google-services.json` and an externally supplied `STAGING_FIREBASE_PROJECT_ID` are required; configuration must match the fixed `.staging` application id and may not reuse root/production config.
- The launcher label and in-app banner identify the staging build.
- Staging startup validates flavor, native package and Firebase project before Auth/backend use; failures show a controlled error and never fall back to normal/demo.

- [ ] Add failing static/widget tests for variant/config guard, package/project identity, and test-environment banner.
- [ ] Run the targeted tests and observe expected failures.
- [ ] Implement the isolated Gradle flavor, label, runtime checks, and banner; disable staging non-debug variants.
- [ ] Run targeted tests and available static checks; do not build an APK because staging credentials/config are intentionally absent.

### Task 4: Cross-environment verification and audit

**Files:**
- Modify: relevant Node/Dart tests only if integration regressions are found.

**Interfaces:**
- Existing demo and normal behavior remain covered independently from staging.

- [ ] Run Flutter analyze and relevant normal/searchLocal/staging-policy tests without services.
- [ ] Run the full Node unit suite and syntax checks.
- [ ] Run `git diff --check`; review all changed files and confirm pre-existing untracked artifacts remain untouched.
- [ ] Record skipped Emulator/device tests and the external staging setup required before real-device validation.
