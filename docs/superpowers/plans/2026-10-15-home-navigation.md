# Home + Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernize the existing Home and primary navigation while preserving current destinations, configurable sections, security gates, and local workspace changes.

**Architecture:** Keep `CityShell`, its `IndexedStack`, `HomeView`, `HomePageConfig`, and existing search/directory routes. Make targeted responsive and state-feedback changes in `lib/redesigned_app.dart`, add only optional seams needed for deterministic widget tests, and reuse `TourismHomeView` for the Home tourism shortcut.

**Tech Stack:** Flutter/Dart, Material 3, existing Firestore/public-content repositories, Flutter widget tests and `flutter analyze --no-pub`.

**Spec:** `docs/superpowers/specs/2026-10-15-home-navigation-design.md`

## Global Constraints

- Preserve `CityShell`'s five destinations: Início, Explorar, Utilidades, Favoritos and Perfil.
- Preserve `IndexedStack`, current category destinations, `UniversalSearchPage`, Home section order/visibility/title/limit configuration and explicit draft/publication behavior.
- Do not change Firestore Rules, Cloud Functions, production gates, `SecureBackend.productionAuthorized`, allowlists or transport configuration.
- Do not access Firebase real, start Firebase Emulator or MEmu, run migrations, install dependencies, deploy, commit, push or discard local changes.
- Do not add municipal facts, fallback content, external queries or per-card data requests.
- Run Flutter checks with `--no-pub`.

## Review Focus

- Widths 320/360/393/430 px and text scaling 1.0/1.5/1.8 do not overflow or make category names inaccessible — Task 1 responsive widgets.
- Initial Home config failure, refresh failure and successful recovery show the right state while retaining prior data — Task 2 stream tests.
- Home editor load failure never permits saving/publishing uninitialized defaults and retry restores editing — Task 2 editor tests.
- Bottom tab selection, system back and pending-edit guard preserve existing screen state and navigation destinations — Task 3 shell tests.
- Tourism category shortcuts resolve using loaded content and return without an empty category or unsafe direct Firestore read — Task 4 Tourism tests.

---

### Task 1: Responsive Home categories and compact hero

**Files:**
- Modify: `lib/redesigned_app.dart` (WelcomeHero, CategoryTile, ExploreView and Home category section only)
- Modify: `lib/features/home/models/home_page_config.dart` only if a named primary-category projection is needed while retaining all existing editor values
- Test: `test/home_page_config_test.dart`
- Test: `test/home_navigation_test.dart` (create)

**Interfaces:**
- Consumes: existing `HomePageConfig`, `homeCatalog`, `openDirectory`, `CategoryTile`, `WelcomeHero` and `UniversalSearchPage`.
- Produces: compact hero with an optional profile callback, responsive Explore grid (2 columns below 420 logical px; 3 columns at 420 px and above), legible category tiles, and primary Home categories with stable existing route objects.

- [ ] **Step 1: Write failing widget tests** for primary category labels/destination data, grid layout at 320/360/393/430 px with text scale 1.8, hero/profile action and accessibility labels.
- [ ] **Step 2: Run `flutter test --no-pub test/home_navigation_test.dart test/home_page_config_test.dart`**; confirm failures describe missing responsive/profile behavior.
- [ ] **Step 3: Implement minimal responsive category presentation and compact hero** without changing routes, category keys, search transport or admin configuration format.
- [ ] **Step 4: Rerun the two test files** and confirm all pass with no Flutter exceptions.

### Task 2: Home configuration, section and editor loading/error/retry states

**Files:**
- Modify: `lib/redesigned_app.dart` (HomeView configuration subscription, HomeEditor load/save state, AdCarousel and EventCard retry controls only)
- Test: `test/home_loading_retry_test.dart` (create)
- Test: `test/home_title_edit_pilot_test.dart` only if the existing Home edit guard integration needs regression coverage

**Interfaces:**
- Consumes: existing `HomePageConfig`, Firestore `home_pages/published`/`draft` contracts, admin authorization, `watchPublicContent` and current section widgets.
- Produces: optional stream factories for test injection, explicit initial loading/error/retry feedback, stale Home data retained on update error, retryable ad/event errors, and HomeEditor save/publish disabled until configuration loads successfully.

- [ ] **Step 1: Write failing tests** for Home config loading, initial failure plus retry, refresh failure retaining prior display, successful recovery, configured order/visibility/limits in rendered sections, editor load failure blocking draft/publication, retry restoring editing, AdCarousel error versus empty fallback, and EventCard retry.
- [ ] **Step 2: Run `flutter test --no-pub test/home_loading_retry_test.dart`**; verify failures are the expected state/interaction assertions.
- [ ] **Step 3: Implement a single replaceable Home config stream and safe editor load state**; retry must resubscribe, old snapshots must not overwrite current data, and failed loading must not enable writes.
- [ ] **Step 4: Add retry only to existing AdCarousel and EventCard streams**; keep their public data contracts and render already loaded items during refresh errors.
- [ ] **Step 5: Rerun loading/retry tests plus `test/home_page_config_test.dart`, `test/home_title_edit_pilot_test.dart` and `test/home_agenda_card_test.dart`.**

### Task 3: Main navigation, profile shortcut and back behavior

**Files:**
- Modify: `lib/redesigned_app.dart` (CityShell and WelcomeHero callbacks only)
- Test: `test/home_navigation_test.dart`

**Interfaces:**
- Consumes: existing five pages and `IndexedStack`; Home leave guard remains `HomeTitleEditPilot.requestExit()`.
- Produces: hero profile action selects the existing Profile tab; Android/system back from a non-Home tab returns to Home; leaving a dirty Home editor remains guarded; tab state is retained.

- [ ] **Step 1: Add failing tests** for all five destination labels/selection, profile shortcut, state retention after tab switching, system-back-to-Home and dirty-editor refusal to change tabs.
- [ ] **Step 2: Run `flutter test --no-pub test/home_navigation_test.dart`** and confirm the new navigation assertions fail before implementation.
- [ ] **Step 3: Implement the smallest CityShell changes**; use optional widget/callback seams only when required to avoid Firebase in widget tests, and keep production page construction unchanged by default.
- [ ] **Step 4: Rerun `test/home_navigation_test.dart` and `test/home_title_edit_pilot_test.dart`.**

### Task 4: Tourism shortcut uses the loaded category data

**Files:**
- Modify: `lib/redesigned_app.dart` (Home tourism callback and TourismHomeView initial-category behavior only)
- Test: `test/home_tourism_navigation_test.dart` (create)
- Test: `test/home_tourism_carousel_test.dart`

**Interfaces:**
- Consumes: existing `HomeTourismCarousel`, `TourismHomeView`, `TourismCategoryView`, `watchPublicContent('routes')`, category config and retry UI.
- Produces: an optional `initialCategoryKey` on `TourismHomeView` that shows the selected category using the already-loaded `spots` list; direct Home tap returns to Home with one back action.

- [ ] **Step 1: Write failing tests** for tapping each supported Home tourism category with loaded fake routes, category-filtered visible cards, unavailable/loading states, and returning directly to Home.
- [ ] **Step 2: Run `flutter test --no-pub test/home_tourism_navigation_test.dart`** and verify the empty-list regression is reproduced.
- [ ] **Step 3: Implement `initialCategoryKey` in `TourismHomeView`** without adding a Firestore read or touching backend/Rules/gates.
- [ ] **Step 4: Rerun `test/home_tourism_navigation_test.dart` and `test/home_tourism_carousel_test.dart`.**

### Task 5: Final regression and static checks

**Files:**
- Review: `lib/redesigned_app.dart`, `lib/features/home/models/home_page_config.dart` and the Home/navigation tests above

**Interfaces:**
- Consumes: all implemented Home/navigation behavior.
- Produces: verified local delivery with no unrelated file or dependency changes.

- [ ] **Step 1: Run relevant existing tests**: `test/home_page_config_test.dart`, `test/home_title_edit_pilot_test.dart`, `test/home_agenda_card_test.dart`, `test/home_tourism_carousel_test.dart`, plus new Home/navigation test files.
- [ ] **Step 2: Run `flutter analyze --no-pub`.** Expected: `No issues found!`.
- [ ] **Step 3: Run `git diff --check` and inspect scoped diff/Git status**, confirming pre-existing changes and manifests remain preserved.
