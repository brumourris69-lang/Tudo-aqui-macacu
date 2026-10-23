---
name: firebase-security-auditor
description: Use when reviewing local Firebase Rules, Functions, authorization, App Check, or data projections for privacy and access-control risks.
---

# Firebase Security Auditor

Use for requested security reviews of the Tudo Aqui Macacu Firebase client or backend.

- Keep the review local by default. Read `AGENTS.md`, record Git status, and inspect only relevant Rules, Functions, repositories, and tests.
- Separate confirmed behavior from inference. Trace overlapping Firestore matches, Auth claims plus central authorization, App Check, quotas, visibility checks, and explicit public projections.
- Treat unknown fields and legacy values as unapproved for public output. Check for direct Firestore fallbacks, private job data, arbitrary URLs, and demo/production gate crossover.
- Do not query production data, change Rules or Functions, alter users/App Check, publish, or run active security tests without explicit task-specific authorization.
- Prefer unit tests and static inspection. Use only a disposable demo Emulator when separately authorized; verify project, config, loopback ports, fixtures, and cleanup first.
- Do not include secrets, tokens, contact values, or private document contents in reports. State concrete impact, evidence, severity, and the smallest safe next step.
