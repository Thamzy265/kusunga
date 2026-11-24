# Kusunga

A clipboard history and saved-snippets app for Mac, Windows, iOS and Android. It keeps what you copy (up to a limit you set) and lets you save things you paste often, such as your phone number, email, links or bank details, and paste them with a shortcut.

Status: early setup (desktop first). The app currently opens a window and a menu-bar / tray icon with a Quit item.

## Requirements

Flutter 3.50.1 (Dart 3.14.0). On Mac, Xcode. On Windows, Visual Studio with the "Desktop development with C++" workload.

## Run

```sh
flutter pub get
flutter run -d macos      # or: flutter run -d windows
```

## Check

One command runs format, analyze and tests. Run it before every commit.

```sh
./tool/check.sh           # Mac
.\tool\check.ps1          # Windows (PowerShell)
```

The same check runs in CI (`.github/workflows/check.yml`) on macOS and Windows, followed by a debug build.

## Docs

Plan: `docs/PLAN.md`. Decisions: `docs/adr/`.

## Licence

Kusunga is licensed under the GNU General Public License, version 3 only (SPDX: GPL-3.0-only). Copyright (C) 2026 William Nasoni. See [LICENSE](LICENSE) for the full text. Licences of the dependencies are listed in `docs/licences.md`.
