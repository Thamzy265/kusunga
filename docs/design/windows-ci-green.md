# Windows CI green — design note

Date: 2026-11-19 — Plan item: "Windows CI green" (large) — Status: waiting for PM (deck `docs/slides/windows-ci-green.html`)

## Problem

CI run 44550682517 (main 7e9baf5) was the first time Kusunga's tests ran on Windows. 85 of 3,869 Windows tests failed, and `flutter build windows` never ran. On Mac, 1 test failed only under CI load.

## Diagnosis (developer, 2026-11-19, no code changed)

| Group | Count | Cause | Kind |
|---|---|---|---|
| A | 73 | Tests clean up with `HistoryService.dispose()`, which never closes the SQLite store (`history_service.dart:831-841`; only `close()` does, `:818`). Windows refuses to delete an open file (errno 32); macOS allows it. | Test |
| B | 3 | `your_data_edge_test.dart:388-391` writes a 1-byte fake `kusunga.db`. Windows SQLite says "file is not a database"; Mac sqlite3mc silently replaces it. | Test |
| C | 1 | Export temp file: on Windows `createSync(exclusive: true)` (`your_data_service.dart:67`) succeeds over a dangling link, then `_refuseLink` (`:117`) fails the export instead of writing in place. Not exploitable in practice (128-bit random name; links need extra rights on Windows). | Product, minor |
| D | 6 | Guard tests split on `\n` and read CRLF checkouts. `.gitattributes` covers only `LICENSE`. | Test / config |
| E | 2 | Guard tests assume `/` in paths. Also a false green: `own_marker_edge_test.dart:264`. | Test |
| Mac | 1 | `file_error_log_handle_test.dart:240-258` asserts ≥ 90% whole lines from two concurrent writers; Dart append is not atomic (known BUG-L5), so the rate depends on CPU load. | Test |

### Does Delete everything work on Windows?

Yes, with one Kusunga running (developer: about 85% sure). On windows-latest with the real sqlite3mc, the tests that run Delete everything to the end passed and assert `kusunga.db` is gone. There is one DB connection, the eraser closes it before deleting (`data_eraser.dart:143`), the log file is opened per line, and export/import close their files in `finally` blocks.

Files can stay behind only if a second Kusunga process holds the DB (there is no single-instance guard on Windows) or antivirus briefly opens a file. In both cases the user sees the existing "couldn't be removed" message; nothing is hidden. A Windows QA run confirms it (M1.9d).

## Fix

- **A:** a `test/support` helper that closes, then disposes the service (pattern from `export_erase_edge_test.dart:57-58`), used in the 8 files. Tear-downs run last-registered-first, so the DB closes before the folder is deleted.
- **B:** create the "stuck" files after the screen opens, and only those not yet present.
- **C (if W2 = fix):** check `typeSync(followLinks: false)` before `createSync`; if anything is there, write in place. Test-first.
- **D:** `.gitattributes`: `* text=auto eol=lf` above `LICENSE -text`. All 424 text files are LF in the index already; `git add --renormalize .` must show no change. A `test/ci` test asserts the rule.
- **E:** `package:path` (`p.basename`, `p.split`, `p.posix`) in the 3 files, including the false green.
- **Mac:** replace the 90% floor with checks that don't depend on timing: per writer, the whole lines kept are in strictly increasing order, and each writer keeps at least one. The size bound and `.1` checks stay. The reviewer judges whether this weakens the test. BUG-L5 (atomic append) stays a product item.
- **CI:** run `flutter build windows` even when tests fail (`if: always()` on that step), so one run shows both.
- **Windows build:** the native Windows code (bridges, `flutter_window.cpp`, `main.cpp`) has never been compiled with MSVC, and warnings are errors (`/W4 /WX`, `windows/CMakeLists.txt:39`). Build errors found here are fixed in this item, each through the gates. If one needs a behaviour change, the lead brings it to the PM first.

## Verification

On the pushed branch `fix/windows-ci` with a pull request (PM, 2026-11-19: "Yes, branch and PR"). Each push runs both CI jobs. Locally: `./tool/check.sh` on Mac, run alone.

## Privacy and security

No new data, store, integration or trust boundary. Delete everything is unchanged unless W1 = B. CI only runs on pushes to main and on pull requests; fork pull requests need approval for first-time contributors (GitHub default for public repos). No secrets in CI.

## Decisions for the PM

- **W1. Group A fix:** A: tests only (recommended — smallest change; the app already closes the DB before deleting) · B: also make `dispose()` close the store (product change, with a Mac unit test).
- **W2. Export over a dangling link (C):** A: fix in this item (recommended — small, a failing test exists) · B: Later line.
- **W3. Single instance on Windows:** A: add to M1.9d before the beta (recommended — a second copy would also capture every copy twice and keep the DB open during Delete everything) · B: Later line with a trigger.

## Later

None proposed.
