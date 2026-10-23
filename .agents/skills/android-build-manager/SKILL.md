---
name: android-build-manager
description: Use when building or verifying a Tudo Aqui Macacu Android debug APK for searchLocal or an explicitly configured local flavor.
---

# Android Build Manager

Use when preparing a local Android debug build, verifying its flavor/package, or installing an already-authorized build on MEmu.

- Read `AGENTS.md`; inspect Gradle flavor gates, Dart defines, package IDs, and build scripts before choosing a command.
- Prefer existing project scripts and `--no-pub`; do not install tools or dependencies. Never build a production-connected APK unless separately authorized.
- For `searchLocal`, verify the explicit demo project/configuration and isolation gate, then build with the repository's guarded launcher. Confirm the APK with `tools/test-search-local-apk.ps1` and inspect its actual package/flavor before reporting success.
- Build commands do not authorize installation. Install/update on MEmu only when the current request explicitly authorizes it; preserve existing app data and never clear storage.
- Do not start or stop MEmu or Firebase services unless explicitly authorized. Keep processes started by others intact.
- Report the exact artifact path, package/flavor, build mode, validation result, and any local-service dependency. Do not call a searchLocal APK suitable for public distribution.
