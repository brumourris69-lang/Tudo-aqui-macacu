---
name: mobile-release
description: Use when preparing Android/iOS release builds, signing, versioning, store submission, staged rollout, rollback, or release readiness; not for ordinary debug builds.
---

# Mobile Release Engineering

- Confirm the target flavor, application/bundle ID, signing configuration, version, build mode, and distribution channel before producing artifacts.
- Protect keystores, provisioning profiles, passwords, API credentials, and store access; never echo them or add them to Git.
- Separate debug, local-pilot, staging, and production configuration. Verify the artifact's identity and backend endpoints before installation or distribution.
- Use reproducible build commands and record toolchain versions, artifact location, and checksum where useful.
- Validate migrations, permissions, privacy disclosures, accessibility, crash reporting, and rollback/roll-forward plans relevant to the release.
- Do not publish, upload, submit, or change a rollout without explicit authorization, even when a build succeeds.
