# Dependency licences (GPL-3.0-only check)

Kusunga is licensed under the GNU General Public License, version 3 only (SPDX: `GPL-3.0-only`; PM decisions D8, 2026-11-18, and R5, 2026-11-19). It has no later-version option. This lists every direct dependency in `pubspec.yaml`, the version resolved in `pubspec.lock`, and its licence. Checked 2026-11-18 by the developer; revised 2026-11-19 after the review. The reviewer confirms; this is not legal advice.

"Where read" is the package's `LICENSE` file in the pub cache (`~/.pub-cache/hosted/pub.dev/<package>-<version>/LICENSE`) unless stated.

| Package | Version | Licence (SPDX) | Where read | Compatible with GPL-3.0-only |
|---|---|---|---|---|
| crypto | 3.0.8 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| ffi | 2.2.0 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| file_selector | 1.1.0 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | pub cache LICENSE (German Saprykin) | Yes. Permissive. |
| path | 1.9.1 | BSD-3-Clause | pub cache LICENSE (Dart project authors) | Yes. Permissive. |
| path_provider | 2.1.6 | BSD-3-Clause | pub cache LICENSE (Flutter Authors) | Yes. Permissive. |
| sqlite3 (Dart package) | 3.5.2 | MIT | pub cache LICENSE (Simon Binder) | Yes. Permissive. |
| tray_manager | 0.5.3 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| win32 | 6.4.0 | BSD-3-Clause | pub cache LICENSE (Halil Durmus) | Yes. Permissive. |
| window_manager | 0.5.2 | MIT | pub cache LICENSE (LiJianying) | Yes. Permissive. |
| SQLite3 Multiple Ciphers | 2.5.0 | MIT, plus bundled third-party parts (table below) | Upstream `LICENSE`, `LICENSE.spdx`, `src/filelist.md` and source headers at tag v2.5.0 (read 2026-11-19). The version comes from the sqlite3 3.5.2 CHANGELOG and `SQLITE3MC_VERSION_STRING`. | Yes; extensionfunctions.c is unclear (flag 1) and 14 files' licence is inferred (flag 6). See the table below. |
| SQLite | 3.53.4 | blessing (public domain) | `SQLITE_VERSION` in upstream `src/sqlite3.h` at v2.5.0; public-domain dedication confirmed at https://www.sqlite.org/copyright.html (read 2026-11-19); SPDX `blessing` | Yes. Public domain, no restriction. |
| Flutter SDK | 3.44.6 | BSD-3-Clause (framework); the engine bundles third-party components (see `sky_engine/LICENSE`: Apache-2.0, MPL-2.0 data, FTL, ICU/Unicode, zlib, libpng, CC0); Material Icons font CC-BY-4.0 | `LICENSE` at the SDK root (framework); the rest from the reviewer's scan 2026-11-19 | Yes. None incompatible (reviewer scan 2026-11-19). |
| Dart SDK | 3.12.2 | BSD-3-Clause | `LICENSE` in `bin/cache/dart-sdk` (Dart project authors) | Yes. Permissive. |

All the BSD files were checked for the three clauses (source and binary redistribution, and the no-endorsement clause); none has an advertising clause.

## SQLite3 Multiple Ciphers 2.5.0: what it bundles

Read from the upstream project at tag v2.5.0 (`src/filelist.md` and the licence header of each source file). The amalgamation `src/sqlite3mc.c` includes the parts below. Which optional parts are compiled into a given prebuilt binary depends on the sqlite3.dart build flags, which are not in the pub cache.

| Component | Licence (SPDX) | Source of the statement | Compatible with GPL-3.0-only |
|---|---|---|---|
| SQLite3 Multiple Ciphers own code (cipher_*.c, codec_algos.c, codecext.c, sqlite3mc*.c, AEGIS wrapper cipher_aegis.c) | MIT | `LICENSE`, `LICENSE.spdx` (`PackageLicenseDeclared: MIT`), headers | Yes |
| AEGIS (src/aegis) | MIT | `SPDX-License-Identifier: MIT` in each file | Yes |
| Ascon (src/ascon): aead.c, hash.c, pbkdf2.c, api.h, crypto_aead.h, crypto_hash.h, crypto_pbkdf2.h, prolog.h, round.h | MIT (Ulrich Telle). Each header says "Based on: Public domain Ascon reference implementation" (ascon-c). The headers say public domain, not CC0. | file headers (v2.5.0) | Yes |
| Ascon helper files with no licence header: ascon.h, bendian.h, config.h, constants.h, forceinline.h, permutations.c, permutations.h, printstate.c, printstate.h, round32.h, round64.h, word.h | No licence text in the file. They are part of the same src/ascon copy of the Ascon reference code (public domain upstream) and of the project, whose `LICENSE` is MIT. | `LICENSE`; directory context only | Yes if MIT or public domain. The files themselves do not say which. See flag 6. |
| aes_hardware.c (AES-NI and ARM crypto code), memory_secure.c (secure memory wipe) | MIT (Ulrich Telle) | `License: MIT` in each header | Yes |
| argon2/libargon2.c (wrapper that `#include`s src/argon2 sources and sets the ARGON2_* macros to `static`) | No licence text in the file (30 lines, macros and includes only). It falls under the project `LICENSE` (MIT). The sources it includes are CC0-1.0 OR Apache-2.0 (next rows). | `LICENSE`; file has no header | Yes. See flag 6. |
| mystdint.h (stdint typedefs for MSVC before 2010; included by sha1.c, fastpbkdf2.h, chacha20poly1305.c, sqlite3mc_vfs.c) | No licence text in the file (27 lines, typedefs and macros only). It falls under the project `LICENSE` (MIT). | `LICENSE`; file has no header | Yes. See flag 6. |
| ChaCha20 and Poly1305 (chacha20poly1305.c) | Public domain | file header and `filelist.md` | Yes |
| AES / Rijndael (rijndael.c) | MIT per the file header (original code public domain, S. Stefanek); `filelist.md` says `LGPL-3.0-or-later WITH WxWindows-exception-3.1` | header and `filelist.md` disagree | Yes either way: LGPL-3.0 code may be combined with GPL-3.0 code |
| SHA-1 (sha1.c), MD5 (md5.c) | Public domain | file headers and `filelist.md` | Yes |
| SHA-2 (sha2.c) | BSD-3-Clause (Olivier Gay) | file header | Yes |
| PBKDF2 (fastpbkdf2.c) | CC0-1.0 | file header | Yes |
| Argon2 (src/argon2, including blake2) | CC0-1.0 OR Apache-2.0, at the user's option | file headers | Yes. Choose CC0-1.0, or Apache-2.0 (compatible with GPL-3.0). |
| SQLite3 Multiple Ciphers RC4 cipher (cipher_sds_rc4.c), SQLCipher-compatible cipher (cipher_sqlcipher.c) | MIT (own code, no SQLCipher source copied; the SQLCipher format is only imitated) | file headers | Yes |
| miniz (miniz.c, used by the compress and zipfile extensions) | MIT | file header | Yes |
| SQLite core and SQLite extensions (shathree, csv, fileio, series, uuid, regexp, sqlar, zipfile, compress, rekeyvacuum) | Public domain (blessing) | file headers and `filelist.md` | Yes |
| vsv.c (extension) | Public domain (Keith Medcalf; builds on SQLite's csv.c) | file header | Yes |
| extensionfunctions.c | No licence text. Upstream `filelist.md` only assumes it is public domain | `filelist.md` | Unclear. Only compiled with `SQLITE_ENABLE_EXTFUNC`. The macOS arm64 binary the sqlite3 hook downloaded here has none of its function names (checked with `strings`), so it is not in that binary. Windows binary not checked. See flag 1. |

Nothing in SQLite3 Multiple Ciphers is GPL-2.0-only, LGPL-only without the "or later" option, AGPL or proprietary.

## Flags

1. `extensionfunctions.c` in SQLite3 Multiple Ciphers has no licence text. It is not in the macOS binary checked. It should be confirmed absent from the Windows (and later iOS and Android) binaries before each release; run `tool/check_sqlite3mc.sh <binary>` (on Windows, in Git Bash on `sqlite3mc.dll`; see the script header). It fails if a binary has the function names that extensionfunctions.c registers (`padl`, `stdev` and others). Checked on the Mac binaries (arm64 and x86_64) on 2026-11-21: none present. Apart from the 14 files in flag 6, the rest has a stated permissive or public-domain licence.
2. Notices must ship with any binary given to anyone, the M1.9 beta included. BSD-3-Clause, MIT and Apache-2.0 require the copyright notice and licence text to travel with the binary. Flutter's `LicenseRegistry` and the generated `NOTICES.Z` collect the notices of the Dart and Flutter packages but not the SQLite3 Multiple Ciphers / SQLite notice, so that one must be added by hand. This is now an M1.9 acceptance criterion. An in-app licence screen is out of scope for this item.
3. App store terms: GPL-3.0 and the Apple App Store terms have a known conflict for code with outside contributors. With a single copyright holder (the PM) this is the holder's call; a contributor agreement is out of scope here (see PM decision D8 in `docs/status.md`).
4. All 85 entries of `pubspec.lock` (direct and transitive) were checked by the reviewer on 2026-11-19. All are permissive (BSD-3-Clause, MIT, Apache-2.0, zlib). There is no GPL-2.0-only, LGPL, AGPL, SSPL or MPL code and no proprietary licence among them. The direct dependencies above were read by the developer; the transitive ones by the reviewer.
5. `test/ci/licence_test.dart` keeps the versions in the table in step with `pubspec.lock`, the sqlite3 package's CHANGELOG (for SQLite and SQLite3 Multiple Ciphers) and the SDK versions named in the README. A version bump that is not reflected here fails the check.
6. In SQLite3 Multiple Ciphers v2.5.0, 14 files carry no licence header (listed in the table): 12 files in `src/ascon`, `src/argon2/libargon2.c` and `src/mystdint.h`. The licence is inferred from the project `LICENSE` (MIT) and, for the Ascon files, from the public-domain reference code they come from; mystdint.h is 27 lines of stdint typedefs, used only by MSVC before 2010, and is included by sha1.c, fastpbkdf2.h, chacha20poly1305.c and sqlite3mc_vfs.c. This is not stated in the files. The risk is low (nothing GPL-incompatible is plausible there), but it is an inference, not a quote. Checked by the developer against the upstream v2.5.0 source on 2026-11-19.
