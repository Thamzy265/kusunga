# 0003. Distribute the Mac app directly (notarised), keep the App Sandbox on

Date: 2026-11-04

## Status

Accepted (PM, 2026-11-04)

## Context

From M1.3 Kusunga pastes into other apps by posting a Cmd+V key event, and from M1.5 it watches typed keys for snippet shortcuts. macOS controls these with three separate privacy permissions:

- PostEvent (posting key events, `CGEvent.post`), shown to users under Privacy & Security > Accessibility;
- ListenEvent (a system-wide event tap), shown under Input Monitoring;
- Accessibility (reading or controlling other apps' UI).

Apple Developer Technical Support says PostEvent and ListenEvent work inside the App Sandbox, and Accessibility does not (Apple Developer Forums thread 820594, March 2026). The same thread shows a sandboxed clipboard manager rejected twice by App Review under guideline 2.4.5 for posting Cmd+V, with no resolution as of September 2026. Sandboxed Mac App Store clipboard managers often make the user press Cmd+V themselves.

Kusunga does not need the Accessibility permission itself: password fields turn on macOS "secure input", which already stops event taps from seeing keys (M1.5).

Our data lives in the sandbox container `~/Library/Containers/com.wnasoni.kusunga/`. Turning the sandbox off would move it and need a data migration.

Options considered:

- A: Direct download, notarised with Developer ID (needs the Apple Developer account, decision D5), App Sandbox kept on, Hardened Runtime on. Mac App Store later, if ever.
- B: Mac App Store, sandboxed. Paste and typed shortcuts are at risk in App Review; Kusunga may have to make users press Cmd+V.
- C: Direct download with the App Sandbox off. Same features as A, weaker protection if Kusunga is ever exploited, and a data move now.

## Decision

We will use option A. Kusunga is distributed as a notarised direct download. The App Sandbox stays on, and Kusunga asks only for PostEvent (M1.3) and ListenEvent (M1.5), never the Accessibility API permission.

## Consequences

- Easier: automatic paste and typed shortcuts without App Review risk; the data folder stays where it is; the sandbox still limits damage if Kusunga is ever exploited.
- Harder: we handle updates ourselves (an updater is a later item); users download from our website, not the App Store; the M1.9 beta needs the Apple Developer account.
- If we later want the Mac App Store, we must test whether App Review accepts posting Cmd+V. If not, the store build falls back to "Copied — press ⌘V" and keeps the rest.
- Every build that posts or listens to events must keep working inside the sandbox; a CI test checks the entitlements file still has `com.apple.security.app-sandbox`.

## Build facts (M1.9b, 2026-11-21)

- The minimum supported version is macOS 12.0 (`MACOSX_DEPLOYMENT_TARGET`, forced by Xcode 27.2 in M1.3). State it in the release notes.
- The beta is Apple silicon only (`ARCHS = arm64` for release and profile, PM decision D3 A, 2026-11-19). Intel Macs run macOS 26 or older and are not built for.
- Hardened Runtime is on for release and profile builds (`ENABLE_HARDENED_RUNTIME = YES` in `macos/Runner/Configs/Release.xcconfig`). Debug builds do not use it. The release entitlements file has no Hardened Runtime exceptions.
- `tool/mac_release_guards.sh binary` fails (exit 1) a release whose bundle contains `KusungaAcceptSyntheticKeys`. `tool/mac_release_guards.sh xcconfig` is an allow-list for `Local.xcconfig.example`: outside whole-line `//` comments (CR, LF and CRLF all end a line) it may set only `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY` and `PROVISIONING_PROFILE_SPECIFIER` (each with optional `[sdk=...]`/`[config=...]` conditions), and a `-D` token anywhere (not after a letter, digit or underscore) fails. Any other key, `#include` or continuation line fails (exit 1). A missing, unreadable or unscannable file exits 2. The guard does not follow `#include`, which is why it fails on one. The build `.xcconfig` files are not run through it; a test checks them for conditions.
