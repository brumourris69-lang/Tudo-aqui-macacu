---
name: app-architecture
description: Use when evaluating Flutter app structure, state ownership, module boundaries, dependency direction, or an architectural migration; avoid for a small isolated widget change.
---

# App Architecture

Make architecture decisions from the existing code and product constraints, not from a preferred pattern.

- Trace the affected UI, state, domain, persistence, and backend paths before proposing a new abstraction.
- Prefer the project's current conventions. Compare at most two viable options when a meaningful trade-off exists.
- Keep data ownership and trust boundaries explicit; clients never become authoritative for privileged decisions.
- Describe migration, compatibility, failure behavior, and rollback for structural changes.
- Add an abstraction only when it reduces coupling or enables a concrete test; do not introduce a framework solely for pattern conformity.
- Verify the chosen boundary with focused tests and report what remains an architectural assumption.
