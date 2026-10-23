---
name: safe-refactoring
description: Use when restructuring existing code without intending to change behavior, reducing duplication, improving boundaries, or preparing a migration with compatibility constraints.
---

# Safe Refactoring

- Record the current behavior and inspect the dirty Git state before edits; preserve unrelated work.
- Establish focused regression coverage before moving logic. Keep refactoring steps small and behavior-preserving.
- Avoid mixing cleanup with feature changes or schema/API changes unless the task requires them.
- Search all call sites, platform variants, tests, scripts, and persisted contracts before changing names or boundaries.
- Run the focused tests and relevant static analysis after each meaningful step, then inspect the complete diff.
- If behavior must change to make the design safe, stop calling it a pure refactor and state the behavior change explicitly.
