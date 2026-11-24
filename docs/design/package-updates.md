# Package updates: sqlite3, window_manager, tray_manager (M1.10b) — design note

Date: 2026-11-24 — Size: large — the sqlite3 update changes the library that encrypts the history database; the window and tray packages move to a new native core on both platforms — Phase: MVP — Status: approved by PM 2026-11-24 ("Approve, all A"; deck `docs/slides/package-updates.html`)

## Context

M1.10a moved the app to Flutter 3.50.1 (ADR 0008, merged 2026-11-24, PR 11). M1.10b updates the three packages that needed it. Lookup 2026-11-24 (report: lead scratchpad `m110b_research.txt`; sources are pub.dev archives, changelogs, upstream GitHub and the repo at 7eef5fe):

- The targets are the latest versions: sqlite3 3.9.2, window_manager 0.7.1, tray_manager 0.9.1 (all 2026-11-22). They resolve together on Flutter 3.50.1, and each part also resolves alone (`flutter pub get --dry-run` on copies of the pubspec).
- **sqlite3 3.9.2** bundles SQLite3 Multiple Ciphers 2.7.1 on SQLite 3.54.1 (today: 2.5.0 on 3.53.4). Correction 2026-11-24 (developer, M1.10b): the sqlite3 CHANGELOG says 2.7.0, but the library it downloads reports 2.7.1 (upstream tag 2026-11-15). 2.7.0 → 2.7.1 does not touch the ChaCha20 page path.
  - The ChaCha20 read path and `hexkey` handling are the same code as 2.5.0. On write, 2.7.x re-rolls the nonce, and it uses the scalar code where the counter would wrap. So existing databases should open with the existing key. This is a source reading: the tests and QA must prove it.
  - The prebuilt library is downloaded from the sqlite3.dart GitHub release at build time and checked against SHA-256 hashes inside the package. The lockfile pins the package hash, and CI uses `--enforce-lockfile`.
  - The Dart API changes are additive only. No `lib/` change is expected.
  - About 12 files hold the old versions: licence assets, `docs/licences.md` and about 7 tests.
  - Versions 3.7.0–3.8.x are never used (sqlite3mc 2.6.x ChaCha20 counter bug).
- **window_manager 0.7.1 and tray_manager 0.9.1** are thin wrappers over `nativeapi`.
  - nativeapi is a C++ core, compiled from source at build time by the `cnativeapi` build hook. It reaches Dart through FFI, with no MethodChannel.
  - The 0.5.x API is still there in `legacy.dart`, but every class and global in it is `@Deprecated` ("will be removed in a future release"). `flutter analyze` fails on deprecation infos here.
  - Our use: 2 files (`lib/window/window_manager_port.dart`, `lib/tray/tray_manager_port.dart`), about 17 calls.
  - The 7 tests in `test/tray/tray_manager_port_test.dart` and `tray_submenu_port_test.dart` mock `MethodChannel('tray_manager')`, which no longer exists. They need a new seam. A test must never call the real plugin, because it would build the C++ library and create a real menu-bar item.
  - Our Swift and C++ runner code does not use either plugin. The generated plugin registrants lose three entries.
- **New packages:**
  - `nativeapi`, `nativeapi_flutter` and `cnativeapi` 0.6.2: MIT, LiJianying, publisher leanflutter.dev.
  - `process` 5.0.6: BSD-3-Clause, tools.dart.dev.
  - Several build-time Dart packages are bumped.
  - Dropped from the build: `menu_base`, `screen_retriever` (and its platform packages), `json_annotation`, `shortid`.
  - cnativeapi builds offline. The only build-time download is still sqlite3's.
- **Fixed upstream in nativeapi 0.6.2:**
  - nativeapi#49: hidden start on Windows.
  - nativeapi#39: a file dialog shown 20 s late, or never, after a hidden start.
  - nativeapi#40: resize lag.
  - tray_manager#111: the 0.5.x tray leaked Windows USER objects on every menu rebuild. 0.9.x is not affected.
  - No open issues in the three repositories. No reports for macOS 27, which is absence of evidence, not testing.

## Requirements and non-goals

- Functional:
  - The encrypted history and snippets open unchanged with the existing key.
  - The tray menu and its submenu, left and right click, tooltip and icon all work as today.
  - Window show, hide and focus, close-to-hide and the minimum size work as today.
  - The picker, hotkey, clipboard watcher, Cmd+Q database flush and Dock reopen work as today.
- Non-functional:
  - `./tool/check.sh` and `.\tool\check.ps1` pass with no new analyzer ignores, and both CI jobs pass.
  - The licence page and `docs/licences.md` list every new package that ships in the app.
- Non-goals:
  - Other package updates.
  - Using new nativeapi features (badges, progress, new window kinds).
  - Universal Mac build.

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| Data integrity | Every existing database opens with its key, with no data loss | The frozen v3 and v6 database fixtures (`test/data/frozen_db_fixture_test.dart`) on the new library; QA opens the qa profile written by the 3.44.6 and 3.50.1 builds |
| No behaviour change in tray and window | Same menu, clicks, show/hide, close-to-hide, picker | Rewritten port tests on a fake backend; QA on the Mac (tray, Dock reopen, login start, Cmd+Q flush) and the Windows CI build |
| Supply chain | Every new native binary or source is pinned and licensed | Lockfile hashes with `--enforce-lockfile`; the 4 new sqlite3mc SHA-256 values recorded in `docs/licences.md`; `tool/check_sqlite3mc.sh` re-run; reviewer header grep of the cnativeapi C++ |

## Estimate

n/a — no load change.

## Data

There is no schema, store or key change. The encryption library is the risk: SQLite3 Multiple Ciphers moves from 2.5.0 to 2.7.1 with the same ChaCha20 format.

Failure mode: if a database does not open, the app already shows its "can't open your history" path and never overwrites the file. The tests prove both directions:
- an old file opens on the new library;
- a wrong key still fails.

## Options

### Split

- **S-A: two items, each with its own branch and pull request.**
  - First M1.10b, sqlite3 only: about 12 files, no `lib/` change, and the data-safety acceptance criterion.
  - Then M1.10c, window_manager and tray_manager.
  - A problem in one part cannot hold up or hide a problem in the other.
- **S-B: one branch, as the plan says today.** One QA run and one merge, but a failure in either part blocks both, and the review is larger.

### Window and tray API

- **API-A: the native API now.**
  - Rewrite the 2 port files on `WindowManager.instance.getCurrent()`, `TrayIcon` and `Menu`/`MenuItem` with per-item click listeners.
  - Add a small injectable tray backend, so tests never touch the real plugin.
  - Handle a null "current window" on a hidden Windows start: retry, or bind the window explicitly.
  - Cost: 2 lib files, 2 tests rewritten, about one developer round.
  - The analyzer gate stays strict.
- **API-B: `legacy.dart` with `// ignore_for_file: deprecated_member_use`** in the 2 port files.
  - Smallest change: the imports only, and the existing ports keep working.
  - Legacy also resolves a hidden Windows start window for us.
  - It adds the first analyzer ignores, and the API "will be removed in a future release". That is a weaker gate, so it is a risk you accept, with a Later trigger.

## Decision

S-A and API-A. PM approved G1 A and G2 A on 2026-11-24 ("Approve, all A"). ADR 0009 (accepted) records the move of the window and tray to nativeapi. ADR 0002's choice of the encrypted SQLite store is unchanged.

## Failure plan

There are no outbound calls at run time. Build-time downloads keep their pins:
- the sqlite3mc binary (package-internal SHA-256, recorded in docs);
- pub packages (lockfile hashes, `--enforce-lockfile`).

## Observability

n/a — no run-time change. Existing error-log lines for window and tray setup failures stay: `WindowService.start` and the tray service already catch and log setup errors.

## Trust boundaries and abuse cases

- **Boundaries:**
  - the sqlite3mc prebuilt binary from GitHub releases;
  - the new pub packages, including C++ source compiled on our machines and in CI.
- **Abuse case:** "As an attacker I swap the sqlite3mc binary on the release page so that builds ship my code."
  - Mitigation: the package checks the SHA-256 before use, and the package itself is pinned by the lockfile hash.
  - We record the 4 expected hashes in `docs/licences.md`.
  - QA compares the downloaded macOS file's hash.
- **Abuse case:** "As an attacker I publish a look-alike nativeapi package, or a new version with hostile C++."
  - Mitigation: the publisher is the verified leanflutter.dev (same as window_manager today).
  - The exact versions are pinned by lockfile hash, and CI uses `--enforce-lockfile`.
  - The reviewer checks the publisher and greps the C++ for network or process calls.
- **Abuse case:** "As a local user I see another user's clipboard through the new window hooks."
  - n/a: nativeapi's hooks are in-process window events for our own window. There is no new data path.

## Privacy

No personal data change. The encrypted store, its key and the retention rules are unchanged. The encryption library version changes, and the data-integrity tests cover it. There is no new processor and no network at run time.

## Rollout and rollback

- With S-A:
  1. Branch `chore/sqlite3-3-9` (M1.10b): developer → tester → reviewer → QA → PR and CI → PM merge.
  2. Then branch `chore/window-tray-nativeapi` (M1.10c), with the same gates.
- Rollback: revert the merge commit.
  - Databases opened by 2.7.1 keep the ChaCha20 format, so 2.5.0 can still read them. Re-rolling the nonce on write is part of the format.
  - QA proves this once by opening a qa database written by the new build with the old build.
- With M1.10c, the Mac release path must sign the new `cnativeapi` native asset like the sqlite3mc one. The release guards (`tool/mac_release_guards.sh`) are run in M1.10c's QA.

## Later lines

None new. If G2 is API-B, add:
- "Move window and tray off `legacy.dart` — deprecated bridge with analyzer ignores — trigger: a window_manager or tray_manager release that removes `legacy.dart`, or ≥ 1 new deprecation info in the check — noted 2026-11-24 by lead".

## Decisions for the PM

- **G1. Split:**
  - A: two items — sqlite3 first (M1.10b), then window and tray (M1.10c), each with its own pull request (recommended: smaller changes, and the data-safety part is checked on its own).
  - B: one branch, as the plan says today.
- **G2. Window and tray API:**
  - A: move to the native API now (recommended: no analyzer ignores, and no code that "will be removed").
  - B: keep the old API through `legacy.dart` and silence the deprecation (a weaker gate, which is a risk you accept, with a Later trigger).
