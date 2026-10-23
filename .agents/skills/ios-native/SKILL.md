---
name: ios-native
description: Use when Flutter work crosses into iOS projects, Swift, Xcode, entitlements, signing, lifecycle, permissions, notifications, or Apple platform APIs.
---

# iOS Native Integration

- Inspect the existing `ios/` target, deployment target, plugins, entitlements, and generated project settings before editing.
- Keep platform-specific behavior behind the narrowest Flutter plugin or platform-channel boundary already used by the app.
- Treat signing identities, provisioning profiles, push credentials, and App Store Connect access as sensitive; never print or commit them.
- Explain when a change requires macOS/Xcode validation. A Windows build or static inspection is not proof that an iOS target compiles or runs.
- Test lifecycle, permission denial, background/foreground transitions, and supported OS versions relevant to the change.
- Do not change bundle identifiers, signing, release configuration, or external Apple services without explicit task scope.
