---
name: flutter-widget-tester
description: Use when adding or running focused Flutter widget tests for rendering, navigation, interaction, or loading, empty, and error states.
---

# Flutter Widget Tester

Use when validating a Flutter widget or screen without relying only on screenshots or a live device.

- Inspect nearby tests, widget constructors, dependency seams, and existing fakes before adding coverage. Reuse project conventions and avoid duplicate test infrastructure.
- Cover observable behavior: initial/loading state, populated and empty results, recoverable errors and retry, user interaction, navigation, responsive constraints, and semantics as applicable.
- Use deterministic fakes; do not connect to Firebase or start Emulator/MEmu for a widget test unless specifically authorized and genuinely required.
- Avoid tests that mirror implementation details or assert only static wording when interaction can be exercised.
- Run the narrow test first, then related tests and `flutter analyze --no-pub` if the change warrants it. Distinguish passed, failed, skipped, and not-run tests.
- Inspect test cleanup and fixture effects before running suites. Never clear app data or persistent Emulator data as a test shortcut.

For a functional bug, combine this skill with `superpowers:systematic-debugging`; for a new behavior, use `superpowers:test-driven-development`.
