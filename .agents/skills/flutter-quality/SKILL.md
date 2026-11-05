---
name: flutter-quality
description: Use for Flutter and Dart implementation, bug fixes, responsive behavior, and focused regression checks in Tudo Aqui Macacu.
---

# Flutter Quality

- Read `AGENTS.md` and inspect the feature, nearby tests, and Git status before editing. Preserve pre-existing local changes.
- Start broad code discovery with `tools/project-context.ps1 -Query <termo>` or `rg`; open the matching source and test before treating a search result as authoritative.
- `lib/redesigned_app.dart` still owns several Home and navigation flows; feature models and widgets live under `lib/features/`.
- Prefer targeted tests using local fakes. Do not use Firebase, Emulators, AVD, ASUS, or MEmu merely to validate widget logic.
- Run focused Flutter tests and `flutter analyze --no-pub` when requested or proportionate. State pass/fail/ignored counts separately; do not claim unrun device coverage.
- For detailed visual work, pair this skill with `flutter-ui-builder` and use `flutter-widget-tester` for widget-level rendering and callbacks.
- Relevant references: `docs/ARCHITECTURE.md`, `test/`, `lib/features/`, `lib/core/theme/`.
