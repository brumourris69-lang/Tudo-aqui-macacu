---
name: flutter-ui-builder
description: Use when building or refining Flutter screens, navigation, responsive layouts, or reusable widgets in Tudo Aqui Macacu.
---

# Flutter UI Builder

Use for Flutter screens, navigation, responsive layouts, accessibility, spacing, and reusable visual components in this app.

- Read `AGENTS.md` and inspect the relevant screen, models, routes, and tests before changing code. Preserve unrelated local changes.
- Before changing behavior or creating a new design, use `superpowers:brainstorming`; treat a design the user has already approved as authorization within that scope. Use `superpowers:test-driven-development` for behavior changes.
- Reuse the existing shell, widgets, and theme. `lib/core/theme/app_colors.dart` defines the current palette; inspect `AppColors` and the current typography before styling. Keep the blue, orange, white, and light-neutral identity. Do not invent a replacement design system.
- Check small screens, larger text, semantics, tap targets, loading/empty/error states, and navigation state where relevant.
- Keep changes local to the requested feature. Do not add packages without authorization.
- Run focused Flutter tests and `flutter analyze --no-pub` when relevant. Report visual claims only after inspecting an actual rendered screen.

For visual verification in MEmu, use `memu-visual-tester`. For widget-level rendering and interactions, use `flutter-widget-tester`.
