# Firebase Public Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use coordinated specialist agents for the backend and Flutter tasks, with one writer per file set; QA reviews after both tasks. No commits in this task.

**Goal:** Serve bounded public projections and selected details for establishments, routes, utilities, and jobs while preserving all production gates.

**Architecture:** Add per-collection projection policies shared by listing and safe details; register one gated callable for non-job public details and reuse the route projection in the demo tourism resolver. Flutter details use an injectable safe repository; public business detail no longer reads a full Firestore document. Rules, indexes, and production activation remain untouched.

**Tech Stack:** Node.js 22, Firebase Admin/Functions existing dependencies, Flutter/Dart, Node test runner, Flutter test/analyze.

**Spec:** `docs/superpowers/specs/2026-10-15-firebase-public-content-design.md`

## Global Constraints

- Never access Firebase real, run migration, start Emulator or MEmu, or install dependencies.
- Do not edit Firestore Rules, indexes, `SecureBackend.productionAuthorized`, production gates, or deployment configuration.
- Keep `getPublicJob` demo-only and `job_private` inaccessible to public handlers.
- Preserve all pre-existing tracked and untracked work; no commit, push, reset, stash, or cleanup.
- Unknown fields are omitted; utilities with only legacy `link` are unavailable publicly.

## Review Focus

- Legacy business contact values without approval must not leak; test absent/default approval and explicit approval.
- Malformed/credentialed or non-HTTPS external destinations must be omitted; test each destination class.
- Unpublished, inactive, expired, and deleted source documents must resolve as unavailable.
- Normal Flutter must fail before network invocation while demo uses isolated transport.
- Callable registration must not add production exports unless the existing secure backend gate is explicitly enabled in a future separately authorized deployment.

---

### Task 1: Backend projection policies and safe detail callable

**Files:**
- Create: `functions/public_content_projection.js`
- Modify: `functions/public_content.js`
- Modify: `functions/business_search.js`
- Modify: `functions/business_search_functions.js`
- Test: `functions/test/content_visibility.test.js`
- Test: `functions/test/business_search.test.js`

**Interfaces:**
- `projectPublic(data, isTimestamp, collection)` returns a plain allowlisted object or `null` for an invalid public utility destination.
- `registerPublicContent({admin,onCall,HttpsError})` exports `listPublicContent` and `getPublicContentDetail` only through the existing secure backend registration gate.
- Detail input is exactly `{collection,id}` and accepts only `establishments`, `routes`, and `utilities`.

- [ ] Add failing tests for per-collection field allowlists, contacts requiring `publicContactApproved`, typed destination validation, detail Auth/App Check/quota/visibility, and no jobs/private collection reads.
- [ ] Run the targeted Node tests and confirm expected failures.
- [ ] Implement shared projection helpers and callable, retaining existing pagination and error sanitization.
- [ ] Route `getSearchTourismSpot` through the routes projection without changing its demo-only registration.
- [ ] Run targeted tests, then `npm test` and `npm run check` with Node 22; verify no Rules/index/gate changes.

### Task 2: Flutter safe business detail transport and explicit admin consent

**Files:**
- Create: `lib/core/content/public_content_detail_repository.dart`
- Modify: `lib/core/content/secure_backend.dart`
- Modify: `lib/features/search/repositories/local_universal_search_repository.dart`
- Modify: `lib/features/businesses/repositories/business_repository.dart`
- Modify: `lib/redesigned_app.dart`
- Test: `test/public_content_detail_repository_test.dart`
- Test: `test/business_profile_test.dart` or a focused repository test file.
- Test: `test/content_editor_persistence_test.dart`
- Test: `test/user_operations_test.dart`

**Interfaces:**
- `PublicContentDetailRepository.resolve({required String collection, required String id}) -> Future<Map<String,dynamic>?>` validates the envelope and calls only `getPublicContentDetail`.
- `BusinessRepository.getPublicBusiness(id)` decodes the returned allowlisted map via `Business.fromData`; its list stream remains on `watchPublicContent`.
- `ContentEditor` stores `publicContactApproved` only for establishments, default false for new/legacy documents.

- [ ] Add failing tests proving valid detail decoding, unavailable detail, no direct Firestore get, and the demo transport's allowed callable.
- [ ] Extend the normal-transport test to prove `getPublicContentDetail` fails at the existing gate before Firebase Functions access.
- [ ] Add a failing editor persistence test proving the approval flag defaults off and is stored only for establishments.
- [ ] Run the focused Flutter tests and observe expected failures.
- [ ] Implement the injectable repository and replace the public business detail read; do not change Admin direct reads.
- [ ] Add the explicit opt-in control and persist it without deleting contact values when disabled.
- [ ] Run focused Flutter tests and `flutter analyze --no-pub`.

### Task 3: QA review and rollout documentation

**Files:**
- Review all changed backend and Flutter files.
- Modify only if a specific test defect or in-scope issue is assigned to QA as sole writer.
- Verify: `docs/superpowers/specs/2026-10-15-firebase-public-content-design.md` and this plan.

**Interfaces:**
- QA consumes the implemented callable contract and repository API from Tasks 1–2.

- [ ] Review the exact allowlists and sentinel tests against the approved spec.
- [ ] Review no-fallback and production-gate behavior.
- [ ] Run Node and Flutter test/analyze commands after integration; do not start services.
- [ ] Review `git diff --check` and confirm Rules/indexes/gates are unchanged by this task.
- [ ] Record deployment/rollback and legacy-client limitations in the final report; no deployment work is authorized.
