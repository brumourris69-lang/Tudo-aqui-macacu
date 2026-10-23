---
name: automated-qa
description: Use when planning or implementing a cross-layer regression strategy, integration test matrix, CI quality gate, or reproducible bug verification; use flutter-widget-tester for a single widget test.
---

# Automated QA

- Translate acceptance criteria into observable behavior and choose the lowest test layer that proves each invariant.
- Separate unit, widget, emulator, integration, and hosted checks; label mocks and simulations accurately.
- Include negative, boundary, retry, accessibility, and regression cases proportional to risk.
- Inspect test setup and cleanup before execution; isolate ports, projects, fixtures, and persistent data.
- Prefer deterministic fakes for logic and real local emulators for platform guarantees. Do not infer production behavior from mocks.
- Report exact commands, pass/fail counts, skipped tests, and environmental blockers; never hide failures behind a green process exit code.
