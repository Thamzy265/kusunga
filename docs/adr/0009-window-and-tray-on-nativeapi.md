# ADR 0009: Window and tray through nativeapi (window_manager 0.7, tray_manager 0.9)

- Status: accepted
- Date: 2026-11-24
- Decided by: PM, 2026-11-24 ("Approve, all A"; deck `docs/slides/package-updates.html`, decisions G1 A and G2 A)

## Context

Kusunga controls its window (show, hide, focus, close-to-hide, minimum size) through window_manager. It controls its menu-bar or notification-area icon and menu through tray_manager. In version 0.7.x and 0.9.x, both packages are rebuilt on nativeapi. nativeapi is a C++ core that is compiled from source at build time (the `cnativeapi` build hook) and called through FFI. The 0.5.x API remains only in `legacy.dart`, and all of that API is deprecated. Design note: `docs/design/package-updates.md`.

## Decision

We will use window_manager 0.7.x and tray_manager 0.9.x through their native API, without `legacy.dart`. The two port classes (`lib/window/window_manager_port.dart`, `lib/tray/tray_manager_port.dart`) stay the only code that touches these packages. The tray port gets an injectable backend, so that tests never call the real plugin.

## Consequences

- The app now ships a new native library (cnativeapi, MIT). It is built on our machines and in CI with Xcode or MSVC, which makes the first build slower.
- The Mac release path must sign the cnativeapi library as well as the sqlite3mc library.
- No MethodChannel exists any more. Tests use a fake backend, and the real tray and window behaviour is proven by QA on the running app.
- The Windows tray no longer leaks USER objects on each menu rebuild (tray_manager#111).
- To go back, revert the change. There is no data step.
