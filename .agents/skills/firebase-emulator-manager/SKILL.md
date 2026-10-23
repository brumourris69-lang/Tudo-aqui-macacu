---
name: firebase-emulator-manager
description: Use when inspecting or running the Tudo Aqui Macacu Firebase Emulator Suite for authorized local development and integration tests.
---

# Firebase Emulator Manager

Use for local Auth, Firestore, or Functions Emulator setup, connectivity, fixtures, and MEmu-to-Emulator troubleshooting.

- Read `AGENTS.md`; distinguish `demo-universal-search` from Firebase `tudo-aqui-macacu` before any Firebase command.
- Use `firebase.search-emulator.json` and pass `--project demo-universal-search` explicitly. Confirm configured rules, loopback hosts, ports, VPN/isolation controls, and current listeners before starting services.
- Treat every existing process and persistent export as preexisting. Identify owners; never stop, reuse, overwrite, or clean them without task-specific authorization. Do not import/export unless the approved local script explicitly requires a verified existing demo snapshot.
- Prefer the repository's guarded `tools/start-search-local-demo.bat` / `tools/start-search-local-demo.ps1` flow over ad hoc commands. Inspect scripts first when they may write fixtures, import/export, or clean data.
- If isolation cannot be proven, stop before Firebase access. Never fall back to a real project or remote endpoint.
- For MEmu, use existing ADB reverse/forward helpers and loopback endpoints only. Do not change firewall or global settings without authorization.
- Report project, config, services, endpoints, process ownership, data effects, and cleanup performed. Stop only processes started by the current authorized run.
