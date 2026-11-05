---
name: premium-ui
description: Use when shaping Tudo Aqui Macacu mobile visuals, brand consistency, business cards, premium actions, accessibility, or visual review.
---

# Premium UI

- Reuse `AppBrand`, `AppTheme`, `AppColors`, Poppins, and existing shared widgets. The identity is blue and orange; do not create a parallel theme.
- Inspect the approved visual spec at `docs/superpowers/specs/2026-11-01-visual-identity-design.md` and the target widget before editing.
- The Home featured-business showcase is enabled only at its `BusinessCard` builder in `lib/redesigned_app.dart`; its card and width behavior are in `lib/features/businesses/widgets/business_card.dart` and `published_business_strip.dart`.
- Establishment detail actions are separate: `lib/features/businesses/widgets/business_action_button.dart` and `lib/features/businesses/screens/business_profile.dart`. Preserve their callbacks, validation, and approved compact 3D presentation when working elsewhere.
- Check 320/360/412 dp, enlarged text, missing images, touch targets, semantics, and overflow. Use deterministic widget previews; describe them as widget captures, not device screenshots.
- Preserve Admin controls, drafts, publication state, navigation, and Firestore data. Do not change app behavior outside the requested screen.
- Relevant tests: `test/business_card_test.dart`, `test/business_profile_test.dart`, `test/home_visual_review_test.dart`, and `test/public_areas_visual_review_test.dart`.
