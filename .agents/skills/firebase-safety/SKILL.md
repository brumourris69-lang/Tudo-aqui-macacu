---
name: firebase-safety
description: Use when changing or reviewing Firebase Auth, Firestore Rules, Admin authorization, App Check, or Emulator isolation for Tudo Aqui Macacu.
---

# Firebase Safety

- Read `AGENTS.md` and verify Git status before touching Firebase code or configuration.
- Keep Beta Spark, shared hosted projects, and SparkLocal Emulators separate. SparkLocal requires the explicit `demo-universal-search` project and `firebase.search-emulator.json`; confirm loopback ports and isolation before Firebase commands.
- Never infer the target from an alias, default project, cached login, app flavor, or previous conversation. Do not access hosted Firebase without task-specific authorization; do not deploy or change billing/IAM implicitly.
- Client Admin visibility is not authorization. Trace the versioned claims and `/admin_authorizations/{uid}` check through Rules and `lib/core/auth/admin_authorization.dart`.
- Preserve public projections and draft/publication boundaries. Do not weaken Rules to make a client test pass. Treat Admin SDK checks as separate from client Rules evaluation.
- Prefer static inspection and deterministic tests. Before Emulator runs, inspect scripts and fixture cleanup; do not stop existing processes or alter persistent Emulator data without authorization.
- Relevant references: `firestore.rules`, `firestore.beta.rules`, `docs/content_visibility_local.md`, `docs/beta-spark-readonly.md`, `tools/start-search-local-demo.ps1`, and `test/`.
