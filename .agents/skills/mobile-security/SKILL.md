---
name: mobile-security
description: Use for mobile security reviews or changes involving authentication, authorization, local storage, platform permissions, deep links, WebViews, network trust, secrets, or sensitive data; not for routine UI work.
---

# Mobile Security

- Start from attacker-controlled inputs and trust boundaries across Flutter, native code, backend, and device storage.
- Never place privileged backend keys, service credentials, or signing secrets in the app bundle or logs.
- Treat client-side checks as UX only; enforce authorization on the trusted server or database policy.
- Review secure storage, token lifetime, logout/session recovery, transport, deep-link validation, exported Android components, iOS entitlements, and backup behavior as relevant.
- Prefer narrow changes and negative tests proving unauthorized access is denied. Do not run active tests against hosted services without explicit scope.
- Report severity, exploit preconditions, evidence, and residual risk; do not claim a product is secure solely because static checks pass.
