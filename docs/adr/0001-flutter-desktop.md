# ADR 0001: Flutter desktop for the app

- Status: accepted
- Date: 2026-11-03
- Decided by: PM (decision D1 in `docs/PLAN.md`)
- Superseded in part by: ADR 0008 (2026-11-24) for the Flutter / Dart version, now Flutter 3.50.1 / Dart 3.14.0. The choice of Flutter desktop stands; the versions named below are as of this ADR.

## Context

Kusunga starts on Mac and Windows, then follows on iOS and Android (M4). Clipboard capture, global shortcuts and paste need OS-level code; the rest of the UI does not.

## Options considered

- A: Flutter desktop UI plus small native code for clipboard, hotkeys and paste.
- B: Tauri (Rust core with a web UI).
- C: Fully native (Swift on Mac, C# on Windows).

## Decision

Option A. One UI codebase that the mobile apps can reuse in M4; native code only where the OS requires it.

## Consequences

- The UI is Dart/Flutter. Clipboard, hotkey and paste code will be native plugins (later items).
- Mac and Windows packaging and signing follow Flutter's tooling (signing is decision D5, M1.9).
- Option B would have given a smaller binary but no mobile reuse; option C two UI codebases per platform pair.
- Tray / menu-bar icon uses the `tray_manager` package (0.5.3; newer versions need a newer Dart SDK than 3.12.2).
