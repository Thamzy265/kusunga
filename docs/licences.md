# Dependency licences (GPL-3.0 check)

Kusunga is licensed under the GNU GPL v3.0 (PM decision D8, 2026-11-18). This lists every direct dependency in `pubspec.yaml`, the version resolved in `pubspec.lock`, and its licence. Checked 2026-11-18 by the developer. The reviewer confirms; this is not legal advice.

"Where read" is the package's `LICENSE` file in the pub cache (`~/.pub-cache/hosted/pub.dev/<package>-<version>/LICENSE`) unless stated.

| Package | Version | Licence (SPDX) | Where read | Compatible with GPL-3.0 |
|---|---|---|---|---|
| crypto | 3.0.8 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| ffi | 2.2.0 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| file_selector | 1.1.0 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | pub cache LICENSE (German Saprykin) | Yes. Permissive. |
| path | 1.9.1 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| path_provider | 2.1.6 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| sqlite3 (Dart package) | 3.5.2 | MIT | pub cache LICENSE (Simon Binder) | Yes. Permissive. |
| SQLite3 Multiple Ciphers (native library built into sqlite3 with `source: sqlite3mc`) | 2.5.0 (per sqlite3 3.5.2 CHANGELOG; the string `SQLite3 Multiple Ciphers 2.5.0` is in the built `libsqlite3mc.dylib`) | MIT (see flag 1) | Not read locally: no licence file ships in the pub cache. Upstream https://github.com/utelle/SQLite3MultipleCiphers | Expected yes (MIT is GPL-3.0 compatible). Unconfirmed, see flag 1. |
| SQLite (inside SQLite3 Multiple Ciphers) | 3.53.4 (per sqlite3 3.5.2 CHANGELOG) | Public domain (blessing; no SPDX id, often written `blessing`) | Not read locally: no licence file ships in the pub cache. Upstream https://www.sqlite.org/copyright.html | Yes. Public domain, no restriction. Unconfirmed locally, see flag 1. |
| tray_manager | 0.5.3 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| win32 | 6.4.0 | BSD-3-Clause | pub cache LICENSE (Halil Durmus) | Yes. Permissive. |
| window_manager | 0.5.2 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| Flutter SDK | 3.44.6 | BSD-3-Clause | `LICENSE` at the Flutter SDK root (Flutter Authors) | Yes. Permissive. |
| Dart SDK | 3.12.2 | BSD-3-Clause | `LICENSE` in `bin/cache/dart-sdk` (Dart project authors) | Yes. Permissive. |

All the BSD files were checked for the three clauses (source and binary redistribution, and the no-endorsement clause); none has an advertising clause.

## Flags

1. SQLite3 Multiple Ciphers and SQLite: the native library is a prebuilt binary that the `sqlite3` build hook downloads from the `simolus3/sqlite3.dart` GitHub releases. Its licence text is not in the pub cache, so the licences in the table come from the upstream projects' published terms, not from a file read here. I recall that SQLite3 Multiple Ciphers is MIT and also bundles code under other permissive terms for individual ciphers, but I did not read that list. Someone should read the upstream `LICENSE.md` of version 2.5.0 before the repo is made public.
2. Redistribution notice: BSD-3-Clause and MIT require the copyright notice and licence text to travel with binary distributions. An in-app licence screen or bundled notices file is out of scope for this item. Flutter's `LicenseRegistry` already collects the notices of the Dart and Flutter packages, but nothing shows them yet. Needed before the first release to the app stores (M1.9 or later).
3. App store terms: GPL-3.0 and the Apple App Store terms have a known conflict for code with outside contributors. With a single copyright holder (PM) this is the holder's call, and a contributor agreement is out of scope here (see PM decision D8 in `docs/status.md`).
4. Only direct dependencies are listed, as asked. Transitive packages (for example the platform plugins behind `file_selector` and `path_provider`) are not checked.
