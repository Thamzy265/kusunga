# Dependency licences (GPL-3.0-only check)

Kusunga is licensed under the GNU General Public License, version 3 only (SPDX: `GPL-3.0-only`; PM decisions D8, 2026-11-18, and R5, 2026-11-19). It has no later-version option. This lists every direct dependency in `pubspec.yaml`, the version resolved in `pubspec.lock`, and its licence. Checked 2026-11-18 by the developer; revised 2026-11-19 after the review. The reviewer confirms; this is not legal advice.

"Where read" is the package's `LICENSE` file in the pub cache (`~/.pub-cache/hosted/pub.dev/<package>-<version>/LICENSE`) unless stated.

| Package | Version | Licence (SPDX) | Where read | Compatible with GPL-3.0-only |
|---|---|---|---|---|
| crypto | 3.0.8 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| ffi | 2.2.0 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| file_selector | 1.1.0 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | pub cache LICENSE (German Saprykin) | Yes. Permissive. |
| material_ui | 1.11.1 | BSD-3-Clause | pub cache LICENSE (Flutter Authors); publisher flutter.dev (pub.dev, checked 2026-11-24) | Yes. Permissive. |
| path | 1.9.1 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| path_provider | 2.1.6 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| sqlite3 (Dart package) | 3.9.2 | MIT | pub cache LICENSE (Simon Binder) | Yes. Permissive. |
| tray_manager | 0.5.3 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| win32 | 6.4.0 | BSD-3-Clause | pub cache LICENSE (Halil Durmus) | Yes. Permissive. |
| window_manager | 0.5.2 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| SQLite3 Multiple Ciphers | 2.7.1 | MIT, plus bundled third-party parts (table below) | Upstream `LICENSE`, `LICENSE.spdx`, `src/filelist.md` and source headers at tag v2.5.0 (read 2026-11-19), re-read at tag v2.7.1 (2026-11-24). The version is what the loaded library reports (`sqlite3mc_version()`, the same as `SQLITE3MC_VERSION_STRING` at v2.7.1); the sqlite3 3.9.2 CHANGELOG says 2.7.0, but its prebuilt library (the SHA-256 below) is 2.7.1. | Yes; extensionfunctions.c is unclear (flag 1) and 16 files' licence is inferred (flag 6). See the table below. |
| SQLite | 3.54.1 | blessing (public domain) | `SQLITE_VERSION` in upstream `src/sqlite3.h` at v2.7.1 and `sqlite3_libversion()` of the loaded library (2026-11-24); public-domain dedication confirmed at https://www.sqlite.org/copyright.html (read 2026-11-19); SPDX `blessing` | Yes. Public domain, no restriction. |
| Flutter SDK | 3.50.1 | BSD-3-Clause (framework); the engine bundles third-party components (see `sky_engine/LICENSE`: Apache-2.0, FTL, ICU/Unicode, zlib, libpng, CC0; 3.50.1 dropped the MPL-2.0 `fallback_root_certificates` data and added `ai`, BSD-3-Clause, Dart authors); Material Icons font CC-BY-4.0 | `LICENSE` at the SDK root (framework); the rest from the reviewer's scan 2026-11-19, re-run on 3.50.1 by the reviewer on 2026-11-24 | Yes. None incompatible (reviewer scans 2026-11-19 and 2026-11-24). |
| Dart SDK | 3.14.0 | BSD-3-Clause | `LICENSE` in `bin/cache/dart-sdk` (Dart project authors) | Yes. Permissive. |

All the BSD files were checked for the three clauses (source and binary redistribution, and the no-endorsement clause); none has an advertising clause.

## SQLite3 Multiple Ciphers prebuilt binaries

The sqlite3 package does not compile SQLite3 Multiple Ciphers. Its build hook downloads a prebuilt library from the sqlite3.dart GitHub release (`sqlite3-3.9.2`) and refuses it unless its SHA-256 equals the value in the package's own list (`lib/src/hook/asset_hashes.dart`). The package itself is pinned by its hash in `pubspec.lock`, and CI runs `flutter pub get --enforce-lockfile`. The desktop values for sqlite3 3.9.2 (SQLite3 Multiple Ciphers 2.7.1), read from that list on 2026-11-24; `test/data/bundled_sqlite_test.dart` keeps them equal to it:

| File | SHA-256 |
|---|---|
| `libsqlite3mc.arm64.macos.dylib` | f9cb9a5c884f6af6171fa04f44d270b3a3bb96fe6ae5ef59983cb58f69872372 |
| `libsqlite3mc.x64.macos.dylib` | 6f8979caec12ac2c5c22bf4c1dbf1ef4cabf7d6b72348a8707bd35aef1865a1b |
| `sqlite3mc.x64.windows.dll` | c8013fb5eb6d9fd46884801d0c4e89a424b5548bca49a7f33dd7b1a267b3e500 |
| `sqlite3mc.arm64.windows.dll` | 237999b350af7522175df00927261619d679dca5bfed2d5003657e9b98e7c26f |

## SQLite3 Multiple Ciphers 2.7.1: what it bundles

Read from the upstream project at tag v2.5.0 (`src/filelist.md` and the licence header of each source file, 2026-11-19), and again at tag v2.7.1 for M1.10b (2026-11-24: every file new since v2.5.0 was checked for licence text, and every quoted header is unchanged). The amalgamation `src/sqlite3mc.c` includes the parts below. Which optional parts are compiled into a given prebuilt binary depends on the sqlite3.dart build flags, which are not in the pub cache.

| Component | Licence (SPDX) | Source of the statement | Compatible with GPL-3.0-only |
|---|---|---|---|
| SQLite3 Multiple Ciphers own code (cipher_*.c, codec_algos.c, codecext.c, hwcheck.c, sqlite3mc*.c, AEGIS wrapper cipher_aegis.c) | MIT | `LICENSE`, `LICENSE.spdx` (`PackageLicenseDeclared: MIT`), headers | Yes |
| AEGIS (src/aegis) | MIT | `SPDX-License-Identifier: MIT` in each file | Yes |
| Ascon (src/ascon): aead.c, hash.c, pbkdf2.c, api.h, crypto_aead.h, crypto_hash.h, crypto_pbkdf2.h, prolog.h, round.h | MIT (Ulrich Telle). Each header says "Based on: Public domain Ascon reference implementation" (ascon-c). The headers say public domain, not CC0. | file headers (v2.5.0) | Yes |
| Ascon helper files with no licence header: ascon.h, bendian.h, config.h, constants.h, forceinline.h, permutations.c, permutations.h, printstate.c, printstate.h, round32.h, round64.h, word.h | No licence text in the file. They are part of the same src/ascon copy of the Ascon reference code (public domain upstream) and of the project, whose `LICENSE` is MIT. | `LICENSE`; directory context only | Yes if MIT or public domain. The files themselves do not say which. See flag 6. |
| aes_hardware.c (AES-NI and ARM crypto code), memory_secure.c (secure memory wipe) | MIT (Ulrich Telle) | `License: MIT` in each header | Yes |
| argon2/libargon2.c (wrapper that `#include`s src/argon2 sources and sets the ARGON2_* macros to `static`) | No licence text in the file (30 lines, macros and includes only). It falls under the project `LICENSE` (MIT). The sources it includes are CC0-1.0 OR Apache-2.0 (next rows). | `LICENSE`; file has no header | Yes. See flag 6. |
| mystdint.h (stdint typedefs for MSVC before 2010; included by sha1.c, fastpbkdf2.h, chacha20poly1305.c, sqlite3mc_vfs.c) | No licence text in the file (27 lines, typedefs and macros only). It falls under the project `LICENSE` (MIT). | `LICENSE`; file has no header | Yes. See flag 6. |
| ChaCha20 and Poly1305 (chacha20poly1305.c), entropy and random numbers (csprng_entropy.c) | Public domain. csprng_entropy.c (new in 2.7.x) has no licence text; its header says it was taken out of the ChaCha20-Poly1305 code. | file headers and `filelist.md` | Yes. csprng_entropy.c: see flag 6. |
| ChaCha20 and Poly1305 from libsodium (src/chacha20): stream_chacha20.c, onetimeauth_poly1305.c and the ref, dolbeau, donna, sse2 and private files they include; libchacha20.c (wrapper) | ISC (Frank Denis), per `src/chacha20/src/LICENSE`; ref/chacha20_ref.c is public domain (D. J. Bernstein). The other files carry no header of their own. libchacha20.c has no licence text and falls under the project `LICENSE` (MIT). | `src/chacha20/src/LICENSE`, chacha20_ref.c header, `filelist.md` at v2.7.1 ("Files in `chacha20` directory are under the `ISC` license") | Yes. ISC is permissive. libchacha20.c: see flag 6. |
| AES / Rijndael (rijndael.c) | MIT per the file header and `filelist.md` (original code public domain, S. Stefanek) | header and `filelist.md` at v2.7.1 agree (at v2.5.0 `filelist.md` said LGPL-3.0-or-later with the WxWindows exception) | Yes |
| SHA-1 (sha1.c), MD5 (md5.c) | Public domain | file headers and `filelist.md` | Yes |
| SHA-2 (sha2.c) | BSD-3-Clause (Olivier Gay) | file header | Yes |
| PBKDF2 (fastpbkdf2.c) | CC0-1.0 | file header | Yes |
| Argon2 (src/argon2, including blake2) | CC0-1.0 OR Apache-2.0, at the user's option | file headers (`filelist.md` at v2.7.1 names only Apache 2.0; the headers of the files themselves give the choice) | Yes. Kusunga uses it under CC0-1.0, and the notice says so (PM decision 2026-11-23). |
| SQLite3 Multiple Ciphers RC4 cipher (cipher_sds_rc4.c), SQLCipher-compatible cipher (cipher_sqlcipher.c) | MIT (own code, no SQLCipher source copied; the SQLCipher format is only imitated) | file headers | Yes |
| miniz (miniz.c, used by the compress and zipfile extensions) | MIT | file header | Yes |
| SQLite core and SQLite extensions (shathree, csv, fileio, series, uuid, regexp, sqlar, zipfile, compress, rekeyvacuum, btreecopyfile.c) | Public domain (blessing) | file headers and `filelist.md` | Yes |
| vsv.c (extension) | Public domain (Keith Medcalf; builds on SQLite's csv.c) | file header | Yes |
| extensionfunctions.c | No licence text. Upstream `filelist.md` only assumes it is public domain. | `filelist.md` | Unclear. Only compiled with `SQLITE_ENABLE_EXTFUNC`. It must not be compiled in; enforced by `tool/check_sqlite3mc.sh` (macOS and Windows 2.7.1 binaries checked 2026-11-24; each shipped binary is checked again before release). See flag 1. |

Nothing in SQLite3 Multiple Ciphers is GPL-2.0-only, LGPL-only without the "or later" option, AGPL or proprietary.

## Flags

1. `extensionfunctions.c` in SQLite3 Multiple Ciphers has no licence text. It is not in any of the macOS or Windows binaries checked. The shipped binary must be checked again before each release (and the iOS and Android binaries once they ship); run `tool/check_sqlite3mc.sh <binary>` (on Windows, in Git Bash on `sqlite3mc.dll`; see the script header). It fails if a binary has the function names that extensionfunctions.c registers (`padl`, `stdev` and others). Checked on the Mac binaries (arm64 and x86_64) of 2.5.0 on 2026-11-21: none present. Checked on the arm64 Mac binary of 2.7.1 (sqlite3 3.9.2) on 2026-11-24: none present. Checked by the reviewer on 2026-11-24 on all 4 desktop release files of 2.7.1 (sqlite3-3.9.2: `libsqlite3mc.arm64.macos.dylib`, `libsqlite3mc.x64.macos.dylib`, `sqlite3mc.x64.windows.dll`, `sqlite3mc.arm64.windows.dll`), each with the SHA-256 in the table above: all 4 printed "ok", none present. Apart from the 16 files in flag 6, the rest has a stated permissive or public-domain licence.
2. Notices must ship with any binary given to anyone, the M1.9 beta included. BSD-3-Clause, MIT and Apache-2.0 require the copyright notice and licence text to travel with the binary. Flutter's `LicenseRegistry` and the generated `NOTICES.Z` collect the notices of the Dart and Flutter packages but not the SQLite3 Multiple Ciphers / SQLite notice, so that one must be added by hand. This is now an M1.9 acceptance criterion, met by the in-app licence page (Settings, About, View licences; M1.9a): it lists Kusunga's GPL-3.0 text, the SQLite3 Multiple Ciphers notice with the parts in the table above, and the SQLite notice, from texts bundled as assets (`assets/licences/`), next to the notices Flutter collects.
3. App store terms: GPL-3.0 and the Apple App Store terms have a known conflict for code with outside contributors. With a single copyright holder (the PM) this is the holder's call; a contributor agreement is out of scope here (see PM decision D8 in `docs/status.md`).
4. All 85 entries of `pubspec.lock` (direct and transitive) were checked by the reviewer on 2026-11-19. All are permissive (BSD-3-Clause, MIT, Apache-2.0, zlib). There is no GPL-2.0-only, LGPL, AGPL, SSPL or MPL code and no proprietary licence among them. The direct dependencies above were read by the developer; the transitive ones by the reviewer. On 2026-11-24 (M1.10a, Flutter 3.50.1) `pubspec.lock` has 90 package entries: 5 new, 6 changed and 79 unchanged since 2026-11-19. The reviewer checked the 11 new or changed ones on 2026-11-24 from the pub cache `LICENSE`. BSD-3-Clause (Flutter Authors): material_ui 1.11.1, cupertino_ui 1.1.7, listen 1.0.1, vector_math 2.4.4 (it no longer has the zlib part that 2.2.0 had). BSD-3-Clause (Dart project authors): intl 0.20.3, matcher 0.12.20, meta 1.19.0, stack_trace 1.12.2, test_api 0.7.14. Apache-2.0: clock 1.1.3 (as 1.1.2). flutter_localizations comes with the SDK and is covered by the Flutter SDK row. All are compatible with GPL-3.0-only, and none of the BSD files has an advertising clause.
5. `test/ci/licence_test.dart` keeps the versions in the table in step with `pubspec.lock`, the sqlite3 package's CHANGELOG (for SQLite and SQLite3 Multiple Ciphers) and the SDK versions named in the README. A version bump that is not reflected here fails the check.
6. In SQLite3 Multiple Ciphers v2.7.1, 16 files carry no licence header (listed in the table): 12 files in `src/ascon`, `src/argon2/libargon2.c` and `src/mystdint.h` (as in v2.5.0), and, new in 2.7.x, `src/chacha20/libchacha20.c` (a 41-line wrapper that includes the libsodium files) and `src/csprng_entropy.c` (entropy and random numbers; its header says it was taken out of the public-domain ChaCha20-Poly1305 code). The licence is inferred from the project `LICENSE` (MIT) and, for the Ascon files, from the public-domain reference code they come from; mystdint.h is 27 lines of stdint typedefs, used only by MSVC before 2010, and is included by sha1.c, fastpbkdf2.h, chacha20poly1305.c and sqlite3mc_vfs.c. This is not stated in the files. The risk is low (nothing GPL-incompatible is plausible there), but it is an inference, not a quote. Checked by the developer against the upstream v2.5.0 source on 2026-11-19 and against v2.7.1 on 2026-11-24. (The libsodium files under `src/chacha20/src` mostly have no header either, but their directory has its own ISC `LICENSE`, so they are not counted here.)
