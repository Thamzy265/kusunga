# Status log

## 2026-11-22 — M1.9a About and licences — developer round 6 (BUG-T1 fixed); reviewer re-check dispatched
- Changed: developer report (opus, high effort, round 6), word for word ("How to verify" and file list left out, sub-lists joined onto one line):
  > Both fixes are committed on feat/about-licences and the full check passes: format clean, analyze reports no issues, 4179 tests pass and 10 are skipped (exit 0). Nothing is pushed.
  > Branch: feat/about-licences (2 new commits on top of the tester's f83541c): ac584d4 fix(licences): a NOTICES.Z that cannot be read gives no notices, so Kusunga's own still list (BUG-T1, M1.9a); e10bf9a docs(licences): the sqlite3mc intro says decorative comment-only lines were left out too (M1.9a)
  > Built: `lib/about/flutter_notices.dart`: loading, unpacking, decoding and parsing NOTICES.Z now sit inside one try/catch. On any failure the stream ends empty with no error, so the licence page still lists Kusunga and its GPL, SQLite and sqlite3mc notices. Reading LICENSE was already caught this way, and the drop-the-duplicate rule is unchanged. `assets/licences/sqlite3mc.txt` line 7: the intro now reads "Only the comment marks at the start of lines (/*, */, **, * and //) are left out, and so are the decorative lines made only of comment characters." No quoted words changed. `docs/ui/about-and-licences.md` line 54: the same addition.
  > Tests: 4179 passing, 10 skipped (`./tool/check.sh`, exit 0, "No issues found!", "Formatted 313 files (0 changed)"). One new test: `test/about/licence_texts_test.dart` "the intro says decorative comment lines were left out too".
  > First failing runs, before each fix: the tester's repro failed with `Expected: at least one matching candidate / Actual: _TextWidgetFinder:<Found 0 widgets with text "Kusunga": []>`; the 3 changed tests failed with `FormatException: Filter error, bad data` (not gzip), `FormatException: Invalid UTF-8 byte (at offset 0)` (not UTF-8) and `Unable to load asset: "NOTICES.Z".` (missing); the wording test failed with `Expected: contains 'decorative lines made only of comment characters'`.
  > Tests changed to match the new behaviour (each now expects an empty list and no error, with a comment naming BUG-T1): 1. flutter_notices_test.dart "without NOTICES.Z the error reaches the licence page, as Flutter's own collector does" (was throwsA(isA<FlutterError>())) is now "without NOTICES.Z it gives no notices and no error, so the page still lists Kusunga's own". 2. flutter_notices_edge_test.dart "bytes that are not gzip fail with an error on the stream" (was throwsA(isA<FormatException>())) is now "... give no notices and no error" (tester's). 3. flutter_notices_edge_test.dart "gzip of bytes that are not UTF-8 fails on the stream" is now "... gives no notices and no error" (tester's). Tests 2 and 3 are outside your list; they are the same inputs as the tester's repro checked one level lower, so the repro could not pass while they still expected an error. No other tester test changed.
  > Deviations from plan: (1) no log code added (flutterNotices is a tear-off with no ErrorLog in reach; optional in the brief). (2) the matching UI spec line changed to the new intro wording.
  > Risks / unverified: the rijndael.c/miniz.c decorative-line claim is from the brief, not re-checked against the sources. A broken NOTICES.Z now fails silently, so the Flutter package notices vanish with no log line; intended trade-off for keeping the GPL notices visible. Kusunga not launched.
  > Personal data touched: none. Later lines added: none. Spec gaps raised: none.
  > Findings: BUG-T1 — fixed (ac584d4). sqlite3mc intro wording — fixed (e10bf9a).
  > Blockers: none
  Lead: the tester's rijndael.c/miniz.c note (tester round 5 report above) confirms the decorative-line claim. Reviewer re-check dispatched for ba6ed2b..e10bf9a, including the two tester tests the developer changed.
- Gates: developer pass (round 6) · tester BUG-T1 repro passes · reviewer re-check in progress · QA re-check pending · PM merge not asked
- Open findings: none
- Decisions: open for PM: Apache-2.0 and CC0-1.0 full texts
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9a About and licences — tester round 5: BUG-T1 (low); developer round 6 dispatched
- Changed: tester report (sonnet, medium), word for word (sub-lists joined onto one line, scratchpad paths shortened):
  > Branch: feat/about-licences (5 test commits on 2317e6b: 3c2a891, 3bfe84c, e40c050, 0b737ce, f83541c; not pushed)
  > Added: 67 tests in 5 new files: test/about/notice_entry_edge_test.dart (15); test/about/flutter_notices_edge_test.dart (21); test/ui/reveal_on_traversal_edge_test.dart (9); test/about/about_round5_edge_test.dart (12); test/about/sqlite3mc_notice_shape_test.dart (7)
  > E2E tests added: 0 (n/a: no desktop end-to-end tool approved; the widget tests drive Tab, click, Esc and Back on the real Settings screen)
  > Fail-then-pass (old code = ba6ed2b for lib/ and assets/, new file flutter_notices.dart moved aside; restored afterwards, git status clean, no production file differs from 2317e6b): notice_entry_edge_test (all 15): "Method not found: 'NoticeEntry'" on ba6ed2b. Pass on 2317e6b. flutter_notices_edge_test (all): "Method not found: 'flutterNotices'" on ba6ed2b. 20 pass on 2317e6b, 1 fails (BUG-T1). reveal_on_traversal_edge_test: 4 fail on ba6ed2b, for example "step 0: Rect.fromLTRB(28.0, 158.0, 72.0, 202.0) in Rect.fromLTRB(0.0, 0.0, 100.0, 200.0)" (the ring is 2 px past the view). The failing ones are Tab down, Shift+Tab up, the horizontal axis, and bouncing physics. Pass on 2317e6b. about_round5_edge_test: 7 fail on ba6ed2b. These are the toast room at 150% text, 360x640 and 320x480, the room under View licences at 100%, the delete-count toast, and click-then-Esc focus return (2 tests). Pass on 2317e6b. sqlite3mc_notice_shape_test: the "22 blocks" test fails on ba6ed2b (the old asset has no "Text of" blocks). Pass on 2317e6b.
  > Regression locks (both-pass, kept deliberately): reveal_on_traversal_edge_test, five tests (no padding at the content end, a view smaller than the control, a view exactly control plus ring, no scroll ancestor, a node not in the tree); about_round5_edge_test, five tests (Space opens, a click on Copy version does not take focus, two quick clicks open one page, the section is disposed while the page is open, the long import toast still leaves View licences reachable by keyboard); sqlite3mc_notice_shape_test, six tests (file shape); notice_entry_edge_test: "NoticeEntry on the GPL reads it differently".
  > Bugs found: BUG-T1 (low, no regression versus before): a garbled NOTICES.Z (not gzip, or invalid UTF-8) makes the whole licence page show only the error text. Kusunga's GPL, SQLite and sqlite3mc notices vanish with it, because flutterNotices lets the error out of the shared stream and Flutter's page folds the whole registry. Flutter's own collector in the same state left the page loading forever, so this is no worse than before. The existing test "without NOTICES.Z the error reaches the licence page, as Flutter's own does" locks the opposite on purpose. The notices are GPLv3 5(d) material, so a fix would be: catch the NOTICES.Z read, decode and parse in flutterNotices and yield nothing. The developer or PM should decide, and then change the old test too. Repro (fails today): test/about/flutter_notices_edge_test.dart, "the licence page with a broken NOTICES.Z a garbled NOTICES.Z still lists Kusunga and its notices". It is the only failing test, left failing on purpose. Not bugs: an empty or zero-byte NOTICES.Z gives one empty entry (the same as Flutter's parser). A gzip cut in half is read silently by Dart (no error, partial text).
  > Checked and found correct (all locked in tests): NoticeEntry rules (indent, tabs, CRLF, trailing spaces, blank runs, common indent, 10000 blocks fast; GPL entry paragraphs equal LicenseEntryWithLineBreaks(LICENSE) exactly). flutterNotices drops only exactly ["kusunga"] with the LICENSE text, whitespace-insensitive; keeps all other variants and 300 other notices in order; not calling super.initLicenses() loses nothing (Flutter 3.44's ServicesBinding.initLicenses only registers the NOTICES.Z collector). revealOnTraversal: ring in view on Tab, Shift+Tab, horizontal axis, bouncing physics; no throw. B3: no overlap at 150% text, 100% at 360x640 and 320x480, or with the "12 items deleted" toast; at least 60 px under View licences; multi-line import toast (pre-existing) can still cover the end, View licences stays reachable by keyboard. B4: click then Esc/Back, Space, repeated rounds, Shift+Tab, Copy version click does not move focus; keyboard path unchanged. sqlite3mc.txt vs the downloaded v2.5.0 sources (read-only script, `python3 -I`): all 22 "Text of <path>, lines a to b" blocks match the named lines; words verbatim apart from comment marks in 19 of 22; rijndael.c 14-44 and miniz.c 2-26 omit one decorative line each (no words lost); the argon2 block adds one sentence of the notice's own after the quote; Apache-2.0 and CC0-1.0 full texts are not in the notice (PM decision).
  > Abuse cases covered: n/a. UI states covered: B2, B3 and B4 rows plus the hidden-row state. Not covered: the 200% text and 360 px toast case.
  > Gaps not covered: toast at 200% text and 360 px wide (Ahem test font wraps "Link copied" to two lines and overlaps; left out of the suite with a comment; needs a real-font QA check, as does the sqlite3mc entry at 360 and 800 px). Real NOTICES.Z from a release build untested. The sqlite3mc quote check is a manual script run, not a repo test.
  > Production code changed: none
  > Suite: 4177 passing / 1 failing (the BUG-T1 repro) / 10 skipped (was 4114). `./tool/check.sh`: format 313 files, 0 changed; analyze: no issues; test: "+4177 ~10 -1".
  > Blockers: none (BUG-T1 needs a decision from the developer or PM; the Apache-2.0 and CC0-1.0 texts decision is already with the PM)
  Lead: BUG-T1 is a correctness fix, so it goes to the developer (round 6, escalated to opus at high effort after a second failed round), with the old "error reaches the licence page" test changed to match. Also asked: the sqlite3mc intro names the decorative lines left out (rijndael.c, miniz.c).
- Gates: developer round 6 in progress · tester found BUG-T1 · reviewer re-check pending · QA re-check pending · PM merge not asked
- Open findings: BUG-T1 low
- Decisions: open for PM: Apache-2.0 and CC0-1.0 full texts
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9a About and licences — developer round 5 (QA bugs, hidden row, licence texts); tester dispatched
- Changed: developer report (sonnet, high effort, round 5), word for word ("How to verify" left out, sub-lists joined onto one line, scratchpad paths shortened):
  > Branch: feat/about-licences (7 new commits on top of ba6ed2b; not pushed). Worktree: scratchpad/m19a-wt
  > Commits (oldest first): df8fbbc fix(licences): SQLite blessing keeps its three lines (B1); 5ad128d feat(licences): sqlite3mc notice carries the MIT text and every part's licence text, verbatim from v2.5.0 (AC1, AC7, R6); 4e0e6e8 fix(ui): Tab reveals the whole focus ring (B2); 61bd538 fix(settings): room under the last control for a toast (B3); 578491d fix(about): View licences takes focus when clicked (B4); 80fc383 fix(licences): hide Flutter's second copy of the app licence (lower-case "kusunga" row); 2317e6b docs(ui): spec follows the PM decisions (R1 order, hidden row, verbatim texts)
  > Built:
  > - B1: new `NoticeEntry` in lib/about/licences.dart. Lines indented 4+ spaces keep their line breaks; everything else is read the way Flutter reads it. The SQLite and sqlite3mc notices use it; LICENSE (GPL) stays on LicenseEntryWithLineBreaks. sqlite.txt only had its first blessing sentence joined onto one line.
  > - Licence texts: assets/licences/sqlite3mc.txt now has, under each of the 18 part blocks, "Text of <path>, lines a to b" followed by the verbatim text. The intro names the project and tag v2.5.0 and says only the comment marks at the start of lines (/*, */, **, *, //) were left out.
  > - B2: `revealOnTraversal` (lib/ui/focus_order.dart) now calls `showOnScreen` with the control's box inflated by 2 px (`focusRingReach`). This is the shared helper, so it also applies to other screens that use it. The root cause was that the control was scrolled flush to the view edge, so the 2 px outside ring was clipped.
  > - B3: Settings scroll padding at the bottom is now space4 + one-line toast height (43 + textScaler.scale(20)), so the toast sits below View licences at 100% and 200% text.
  > - B4: `AboutSection` is now Stateful with a FocusNode on View licences. Click or Enter first requests focus on that node, then opens the page.
  > - Hidden row: new lib/about/flutter_notices.dart (`flutterNotices`) reads NOTICES.Z like Flutter does and drops only an entry whose package list is exactly ["kusunga"] and whose text equals LICENSE (whitespace-insensitive). `KusungaBinding.initLicenses` registers ours, then `flutterNotices`, and no longer calls `super.initLicenses()` (marked `// ignore: must_call_super`). Reason: Flutter's collector cannot be removed from the registry and the licence page cannot hide a row. NOTICES.Z is decoded on the main isolate because `test/ci/zone_assumption_test.dart` forbids `compute` in lib.
  > - Spec docs/ui/about-and-licences.md updated: list order, hidden duplicate row, verbatim texts. "— development build" and the "Development build" caption are untouched. "Licenses" (US) is untouched.
  > Tests: full check.sh: "Formatted 308 files (0 changed)", "No issues found!", "04:19 +4114 ~10: All tests passed!", exit 0 (flutter_tester was not running beforehand; no background jobs left). New tests: test/about/licence_texts_test.dart (R6): per part, key lines word for word (copyright holders, MIT/BSD/miniz full text, CC0/Apache URLs, blessing), each source file and the tag named, and the MIT text appears exactly twice (project and miniz); licence_registry_edge_test.dart: B1 paragraph test plus NoticeEntry unit tests; about_edge_test.dart: "the blessing is shown on three lines"; about_focus_ring_test.dart (B2), about_toast_room_test.dart (B3), about_licences_focus_test.dart (B4), shared harness about_settings_harness.dart; flutter_notices_test.dart (hidden row); the skipped MIT test in licence_registry_test.dart is un-skipped.
  > First failing runs, before each fix: B1: licence_registry_edge_test "the SQLite blessing keeps its three lines on the page" — Actual: one line; widget test "Expected: an object with length of <3>, Actual has length of <1>". R6/AC7: licence_texts_test with the old asset: 38 failures; un-skipped MIT test on the old asset: "Expected: contains 'MIT License' ...". B2: ring bottom 634 vs view bottom 632 at 800x632 (and 642 vs 640 at 360x640). B3: toast Rect(0,569,800,632) overlaps View licences Rect(16,566,...); at 200% toast top is 549. All 4 cases fail. B4: "Expected: true Actual: <false>" after a mouse click (Esc and Back both). Hidden row: compile failure (`flutter_notices.dart` did not exist). Behaviour tests then pass. Failing outputs for B2-B4 are saved at scratchpad/fail-b2b3b4.txt. Each regression test was run against the old code before the fix.
  > Downloads (plain curl of raw.githubusercontent.com at tag v2.5.0, into a new directory scratchpad/sqlite3mc-dl; read as text only, nothing run; no prompt or sandbox refusal). Base URL: https://raw.githubusercontent.com/utelle/SQLite3MultipleCiphers/v2.5.0/ — LICENSE, LICENSE.spdx, src/filelist.md (read only, to find part paths); 21 part files quoted in the notice; others downloaded but not quoted (checked only that they carry the same licence lines, or have no header). Generator (not in repo): scratchpad/sqlite3mc-gen/gen.py, run with `python3 -I`. Paths that returned 404 and were dropped: src/argon2/LICENSE, LICENSES/*, src/aegis/LICENSE and similar. Parts with no licence text in their files (Ascon helper files, libargon2.c, mystdint.h, extensionfunctions.c) keep the existing "No licence text ..." wording. Nothing was invented for them.
  > Deviations from plan: `super.initLicenses()` is no longer called (reason above). The two tests that checked that string now check `registerLicences();` before `LicenseRegistry.addLicense(flutterNotices)`. B2 changed the shared `revealOnTraversal`, not only About. Comment markers were stripped from the quoted headers (the words are verbatim). The tester's R10 test now builds a `NoticeEntry` instead of a LicenseEntryWithLineBreaks. PM decisions confirmed in docs/status.md on main (line 65-68).
  > Checklists: ui-build — n/a items: states-matrix additions, new breakpoints, new copy, new tokens. data-and-apis — n/a. Test hooks: no new interactive controls. E2E: n/a — no desktop end-to-end tool approved. Kusunga was not launched; no xcodebuild test.
  > Risks / unverified: Apache-2.0 and CC0-1.0 FULL texts are NOT in the notice. The v2.5.0 tree has no such file in the paths I could fetch (src/argon2/LICENSE and LICENSES/* are 404). The Argon2 and fastpbkdf2 headers are quoted verbatim and name the texts by URL; the notice says the texts themselves are not in the files. AC1/AC7 asked for them "as applicable". PM needs to decide: either allow a download of the canonical texts from another source (e.g. the Argon2 reference repo or SPDX), or accept the headers plus URLs, since Argon2 is CC0 "or" Apache at the user's option and CC0 needs no text to travel. No non-allowed host was used. The rijndael filelist.md "LGPL-3.0+ WITH WxWindows" claim has no LGPL text; the file header says MIT. Existing wording is kept. Not visually checked in the real app; QA should look at the sqlite3mc entry at 360 px and 800 px. The toast room is a measured constant for a one-line toast; the long import toast can still cover the end of the scroll (already so, not in B3). Row hiding only works with a real build that has NOTICES.Z; unit-tested with a fake NOTICES.Z. NOTICES.Z is decoded on the main isolate when the page opens (not measured). I used /tmp/x once by mistake (a cp into an existing directory). I removed the file I created; the directory was already there. A local history fix-up happened (a fixup squashed into the hide-row commit so every commit passes alone); nothing was pushed.
  > Personal data touched: none. Later lines added: none. Spec gaps raised: none new.
  > Findings: B1 — fixed (df8fbbc). B2 — fixed (4e0e6e8). B3 — fixed (61bd538). B4 — fixed (578491d). R6 — fixed (5ad128d). R1 and hide-row decisions — done (2317e6b, 80fc383).
  > Blockers: none that stop the work. Open decision for PM: Apache-2.0/CC0 full texts (see Risks).
  Lead: tester dispatched on feat/about-licences (2317e6b) for the round-5 changes. The Apache-2.0 / CC0-1.0 full-text question goes to the PM.
- Gates: developer pass (round 5) · tester in progress · reviewer re-check pending · QA re-check pending · PM merge not asked
- Open findings: none open from QA (B1–B4 fixed, waiting for re-test)
- Decisions: open for PM: Apache-2.0 and CC0-1.0 full texts for the Argon2 and fastpbkdf2 parts
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9b Mac release build — merged to local main
- Changed: `git merge --no-ff build/mac-release` into local main (6ff4cd7). Full check on merged main: "Formatted 301 files (0 changed)", "No issues found!", "04:32 +3963 ~10: All tests passed!", exit 0 (`pgrep -fl flutter_tester` empty before the run). Not pushed.
- Gates: developer pass · tester pass · reviewer approve · QA build checks pass, launch check moved to M1.9e (PM, 2026-11-22) · PM merge approved
- Open findings: none
- Decisions: PM approved the local merge (2026-11-22) — PM said: "Yes, merge locally"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9b Mac release build — PM decision: Hardened Runtime launch check on the signed build (M1.9e); correction
- Changed: correction to the entry below: QA was **not** dispatched. Before dispatch the lead found that the test-profile switch works in Debug builds only (`lib/history/data_profile.dart`, `#if DEBUG` in `macos/Runner/MainFlutterWindow.swift`, PM decision 2026-11-05), so a Release or Profile build always opens the PM's real history and keychain item. Launching it would break the QA rules (qa or dev profile only; keychain dialogs are the PM's). The lead asked the PM how to do the launch check. Options given: (A) on the Developer ID-signed build in M1.9e, where ADR 0007 already needs QA on a signed build; (B) the PM launches the release build on real data. Lead recommended A. Added to the M1.9 acceptance criteria in docs/PLAN.md: the Hardened Runtime launch check on the signed build (M1.9e).
- Gates: developer pass · tester pass · reviewer approve · QA: build checks done without launch (arm64 only, `flags=…(runtime)`, guards exit 0 — tester report); launch check moved to M1.9e by PM decision · PM merge waiting
- Open findings: none
- Decisions: PM chose the launch check on the signed build (2026-11-22) — PM said: "Do it on signed build"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9b Mac release build — reviewer re-check: approve; QA dispatched
- Changed: reviewer re-check report (opus, high), word for word (sub-lists joined onto one line):
  > Mode: branch
  > Branch: build/mac-release (32d419e..4e80d18, re-check of a5887de, 3ec359c and 4e80d18) — Verdict: approve
  > Checks: ./tool/check.sh — pass — "Formatted 293 files (0 changed)", analyze "No issues found!", tests "+3927 ~10: All tests passed!", exit 0. I confirmed `pgrep -fl flutter_tester` was empty before the run, and `/bin/bash -n` passes on tool/mac_release_guards.sh.
  > Code review: 4 findings (4 fixed, 0 open): R2, R3, R4 and D1. R1 is under security.
  > Design review: 1 finding (1 fixed, 0 open): D1.
  > Security review: 2 findings, both fixed. R1 was Medium (no CVSS score: band + basis — only reachable by a commit to the tracked example file, and the binary guard already caught what got through). R2 was Low (same reach, failed only when the file was unreadable or bigger than the pipe buffer). No new security findings: the rest of the OWASP list is unchanged from the first review (n/a or holds).
  > Privacy review: no issues (build config and a release-time script only; no personal data, logs, network calls or storage).
  > Later lines: ok. The Intel line is on main at docs/PLAN.md:139, in the right format, with a measurable trigger, and not on the never-deferred list. Added by reviewer: none.
  > Findings (most severe first): none open.
  > Fix outcomes:
  > - R1 — fixed. tool/mac_release_guards.sh:72-115 now does three things: it accepts only these keys: DEVELOPMENT_TEAM, CODE_SIGN_STYLE, CODE_SIGN_IDENTITY, PROVISIONING_PROFILE_SPECIFIER; it turns CR and NUL into LF; it fails on any `-D` token outside whole-line `//` comments. Fails on old code: in round 1 I ran the old script (14ed399) on all four repros (single quote, a variable holding `-DDEBUG`, `$(inherited)-DDEBUG`, CR-only line ends) and it exited 0 on each. Xcode does use all four (checked with xcodebuild -showBuildSettings). Passes on new code: the same probe files now exit 1. So do the BOM, `/* */` and backslash probes. I also tried to get past the new list. Spellings that still pass the guard: `;` chaining, vertical tab, form feed, U+2028, NEL. I checked each with `xcodebuild -showBuildSettings` on a scratch copy of macos/, with the probe as Local.xcconfig. Xcode reads all of them as part of the DEVELOPMENT_TEAM value, and SWIFT_ACTIVE_COMPILATION_CONDITIONS is never set. So none of them is a bypass. Regression tests: test/ci/mac_release_guards_xcconfig_test.dart:26-51 covers (a) to (d) one by one, and also checks that other keys, `#include` and continuation lines fail, and that the real example file passes. ADR 0003 line 45 now describes the allow-list accurately.
  > - R2 — fixed. The script now reads the file with `tr` before scanning, and uses here-strings instead of pipes; every grep exit code is checked. Fails on old code: in round 1 an unreadable file exited 0, and a 789 KB file exited 0 on 5 of 5 runs. Passes on new code: the same unreadable probe now exits 2, and the large file exits 1. Regression tests: xcconfig_test.dart:125-158 (unreadable file → 2, a large file with the setting first → 1, a large clean file → 0).
  > - R3 — fixed. test/ci/mac_release_guards_needle_test.dart reads `needle=` from the script and `static let argument = "..."` from TypedShortcutCore.swift, and checks that the argument contains the needle. Renaming either one now fails the test. It passes on old code too, which is expected: the old code had no mismatch, and the test is there to catch a future one.
  > - R4 — fixed. test/ci/mac_release_guards_bugs_test.dart:5-8 is reworded as regression tests for bugs that are now fixed.
  > - D1 — fixed (the lead added it). docs/PLAN.md:139 on main. My M1.9e notes are now an AC at docs/PLAN.md:110 on main.
  > Tester tests that changed (were they weakened?): no. mac_release_guards_edge_test.dart: every changed expectation went from 0 to 1, which is stricter and is what the allow-list requires. That covers OTHER_SWIFT_FLAGS=-Onone, GCC_PREPROCESSOR_DEFINITIONS, `FOO = $(SWIFT_ACTIVE_COMPILATION_CONDITIONS)`, `A = 1 // ...`, `#include`, and lower-case keys. The "key after a trailing //" case still expects 0, now on an allowed key. The one removed test ran the guard on the build .xcconfig files, which the allow-list would now rightly reject. It has been replaced by an equivalent Dart check (xcconfig_test.dart:104-121): no SWIFT_ACTIVE_COMPILATION_CONDITIONS and no `-D` token outside comments in Release, AppInfo, Warnings and Flutter-Release. It covers the same ground as the old deny-list and more. Every other edge test is unchanged and still passes.
  > Risk accepted by PM: none
  > Open items: none
  > Blockers: none. ReportFindings was not available in this session, so the outcomes are in this report instead. The probe files are in scratchpad/xcprobe/. I created no git refs, launched nothing, and pushed nothing.
  Lead: QA dispatched for the Hardened Runtime launch in the qa profile. M1.9a developer dispatched (B1–B4, hidden row, licence-text download, spec update).
- Gates: developer pass · tester pass · reviewer approve · QA in progress · PM merge not asked
- Open findings: none
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9b Mac release build — developer round 3 (review fixes); reviewer re-check dispatched
- Changed: developer report (sonnet, high effort, round 3), word for word ("How to verify" left out, sub-lists joined onto one line):
  > Branch: build/mac-release (3 new commits on 14ed399, tip 4e80d18)
  > Commits: a5887de fix(mac-release): xcconfig guard allow-lists the signing keys, reads CR line ends, and fails on an unreadable or large file (R1, R2; also the ADR 0003 line and the old tests whose expectations changed); 3ec359c test(mac-release): the binary guard needle is the SyntheticKeysSwitch argument in Swift (R3); 4e80d18 test(mac-release): bug repro header reworded as regression tests (R4). All commit messages end with the Claude Opus 5.5 Co-Authored-By line. Worktree is clean. No push, no background jobs left. The Release.xcconfig and signing are untouched.
  > Built:
  > - R1 (tool/mac_release_guards.sh, guard_xcconfig): It is now an allow-list. After CR and NUL are turned into LF and whole-line `//` comments are dropped, any `-D` token fails (exit 1). Any non-blank line that is not `KEY[...]* =` for an allowed key also fails. Allowed keys are DEVELOPMENT_TEAM, CODE_SIGN_STYLE, CODE_SIGN_IDENTITY and PROVISIONING_PROFILE_SPECIFIER. The real Local.xcconfig.example sets only the first three. I added PROVISIONING_PROFILE_SPECIFIER on your instruction, for manual signing. No other key is needed. `[sdk=..]` and `[config=..]` conditions still work on allowed keys. `-D` is matched as `(^|[^[:alnum:]_])-D`, so `My-Dev Profile` passes. `$(inherited)-DDEBUG`, `'-DDEBUG'`, `"-D" X` and `-D` after a tab or in a trailing comment all fail. `#include`, lower-case keys, unknown keys and continuation lines all exit 1. ADR 0003's last Build-facts line now says exactly this. It also says the build `.xcconfig` files are not run through the guard.
  > - R2: the file is read with `tr ... < file` into a variable (exit 2 if that fails). All matching is on here-strings with `grep -E`, with no pipes, and each grep's rc is checked (>1 exits 2). A here-string of nothing is one empty line, so the match is skipped when no lines are left. Works on /bin/bash 3.2.57 (the tests resolve `bash` to /bin/bash).
  > - R3: new test/ci/mac_release_guards_needle_test.dart reads `needle="..."` from the script and `static let argument = "..."` from macos/Runner/TypedShortcutCore.swift, then asserts the argument contains the needle.
  > - R4: the header of test/ci/mac_release_guards_bugs_test.dart now reads as regression tests for BUG-M1, M2, M3 and M5. I did not share the duplicated fixture helpers (optional).
  > Tests: full ./tool/check.sh passes: `04:53 +3927 ~10: All tests passed!`, with format and analyze clean.
  > First failing run, on 14ed399's script with the new test/ci/mac_release_guards_xcconfig_test.dart (14 tests, 9 failed, 5 passed): (a) single-quoted -D: expected 1, got 0; (b) variable holding -D: failed; (c) `$(inherited)-DDEBUG`: failed; (d) CR-only line endings: failed; any key outside the allow-list: failed; a -D token in an allowed key: failed; a -D in a trailing comment: failed; unreadable file: expected 2, got 0, and it prints "ok"; large file (about 790 KB, 25000 setting lines after the first): setting first, expected 1, got 0. After the fix, all 14 pass. Tests that pass on both: the real Local.xcconfig.example exits 0, the build-xcconfig check, a large clean file exits 0, and the signing keys pass.
  > - R3 mutation check: changing the script's needle to `...Keyz` makes the new test fail, with Actual '-KusungaAcceptSyntheticKeys'. It passes on 14ed399 because that code was already consistent. It is a coupling guard, not a bug repro.
  > - The unreadable-file test is skipped when run as root (uid 0).
  > - Note: a large file whose filler is only `//` comment lines did not trigger the old SIGPIPE false pass. The filler must be non-comment lines, as in the committed test.
  > E2E: n/a — no suite for these scripts. No UI flow was run, and Kusunga was never launched.
  > Test hooks: n/a — no UI
  > Deviations from plan: Existing tester tests in test/ci/mac_release_guards_edge_test.dart pinned the old deny-list behaviour and had to change with the allow-list: `OTHER_SWIFT_FLAGS = -Onone`, `GCC_PREPROCESSOR_DEFINITIONS`, `FOO = ...` and `A = 1 // ...` now expect 1 instead of 0. The "documented limit" test for `#include` and lower-case keys now expects 1. A trailing-comment test now uses an allowed key. The "build xcconfig files pass the guard" test moved to the new xcconfig test file. It now greps those files in Dart for SWIFT_ACTIVE_COMPILATION_CONDITIONS and `-D`, because Release.xcconfig (ARCHS and so on) legitimately sets other keys and would fail an allow-list. Splitting R1 and R2 into separate commits was not practical: both rewrite the same function, so they share one commit.
  > Checklists: none — n/a items: data-and-apis, ui-build (shell guard and tests only)
  > Risks / unverified: A `-D` inside an allowed key's value, such as a profile named `Foo -DBar`, fails. That is intended and conservative. `#include` is rejected rather than followed. Local.xcconfig.example has none today. NUL bytes start a new line (conservative). I did not check against xcodebuild how Xcode treats NUL. I did not re-run `xcodebuild -showBuildSettings` for (a) to (d). I relied on your confirmation, and the guard no longer depends on how Xcode parses them. UTF-16 and BOM-prefixed xcconfig files were not tested. A BOM would make the first line fail, which is safe.
  > Personal data touched: none
  > Later lines added: none
  > Spec gaps raised: none
  > Findings: R1 — fixed (a5887de, test/ci/mac_release_guards_xcconfig_test.dart); R2 — fixed (a5887de, same file: unreadable file exits 2, large file exits 1); R3 — fixed (3ec359c, test/ci/mac_release_guards_needle_test.dart); R4 — fixed (4e80d18)
  > Blockers: none
  Lead: reviewer re-check dispatched on 4e80d18. The M1.9a developer starts after the re-check, so checks don't run in parallel.
- Gates: developer pass (round 3) · tester pass · reviewer re-check in progress · QA open · PM merge not asked
- Open findings: R1–R4 fixed, waiting for the reviewer's re-check
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9a About and licences — PM decisions on the spec questions and the licence texts
- Changed: lead asked four questions (QA spec gaps and the open licence-text decision); the PM chose:
- Gates: unchanged (QA pass with B1–B4; AC1/AC7 open)
- Open findings: B1–B4 (minor)
- Decisions (PM, 2026-11-22, answers as chosen word for word):
  - R1 licence order — question "Is that OK?" — PM chose: "OK as it is (Recommended)" (keep Kusunga first; the spec is updated to match)
  - Lower-case "kusunga" row — PM chose: "Hide it (Recommended)"
  - Flutter's US spelling "Licenses" — PM chose: "Accept it (Recommended)"
  - SQLite3 Multiple Ciphers licence texts — PM chose: "Allow the download" (developer may download utelle/SQLite3MultipleCiphers tag v2.5.0: LICENSE and the bundled parts' licence headers, from GitHub)
  - Not asked, default kept: "— development build" plus the "Development build" caption both stay, as in the spec.
- Blockers: Developer none (licence-text download now allowed) · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9a About and licences — QA report; bugs B1–B4 queued for the developer
- Changed: QA report (sonnet), word for word (sub-lists joined onto one line, wording unchanged):
  > Milestone: M1.9a About and licences — 13/15 rows pass; 1 open (known), 1 not observed — Date: 2026-11-22 — Environment: macOS 27.2, Flutter 3.44.6, branch feat/about-licences at 38b4f77 (not pushed). Debug build A had the 0.9.0 / 1 defines. Debug build B had no defines. Built and run one after the other, qa profile only.
  > Automated: 0/15. All manual on the real app, because no desktop end-to-end tool is approved. I used AX reads, guarded click and key helpers, window screenshots and ffmpeg.
  > Per criterion (details in docs/qa/m1.md, section "M1.9a About and licences (2026-11-22)"):
  > - GPL notice (About text, licence-page legalese, full GPL in the Kusunga entry): PASS.
  > - Third-party notices, AC1/AC7: OPEN (known, PM decision pending). The Kusunga entry holds 3 notices: the GPL, then the SQLite3 Multiple Ciphers notice, then the SQLite notice. The sqlite3mc notice is the index only: heading "SQLite3 Multiple Ciphers 2.5.0 and the parts it bundles", one intro paragraph, then each part with a "Licence: ..." line. It has no MIT permission text, no copyright-holder line, and no BSD-3-Clause, CC0 or Apache-2.0 text. The SQLite notice shows the blessing and the sqlite.org copyright link.
  > - Version with defines: PASS. The About line reads "Kusunga 0.9.0 (build 1) — development build". The licence page shows 0.9.0 (build 1). Copy version copies the line.
  > - No defines: PASS. The line reads "Kusunga (version unknown) — development build". Copy version copies that text.
  > - Source link: PASS for debug builds (the plain repo URL plus the "Development build" caption).
  > - Copy buttons and toasts: PASS. "Version copied" and "Link copied" show, and the clipboard contents are correct. Eight own copies did not appear in History, which stayed at 3 items.
  > - Licences list: PASS (recorded, not failed). "Kusunga" is the first row. "sqlite", "SQLite", "sqlite3" and "SQLite3 Multiple Ciphers" sit in alphabetical order near "s", out of 159 rows.
  > - Keyboard: PASS, with B2 and B4 below. Tab order in Settings: 12 stops, ending Copy version, Copy link, View licences. The page opens with the first row focused (blue fill), and the back button has a ring. Esc on an entry goes to the list. The next Esc goes to Settings with focus on View licences (keyboard path).
  > - Reduce motion: not observed (see below).
  > - Copy word for word: PASS.
  > - 360 px layout: PASS (About, licences list and entry; buttons stack, link wraps, no sideways scroll).
  > - Accessibility names: PASS from the AX tree. The names are "Copy version 0.9.0 build 1" and "Copy source code link". Toast text appears in the tree.
  > - Contrast: PASS. Focus ring 8.39:1; focused row fill 3.69:1; buttons 40 pt high.
  > - States matrix: PASS for the reachable states.
  > - Video: done.
  > Fail: none of the criteria fail. Four bugs, all Minor (B2 arguably Major):
  > - B1 (Minor): the SQLite blessing runs onto one line ("* May you do good... * May you find...") although assets/licences/sqlite.txt has three lines. Repro: Settings > View licences > Kusunga > scroll to the end. Evidence: screens/m19a-kusunga-entry-bottom-sqlite.png.
  > - B2 (Minor, arguably Major under WCAG 2.4.7): the focus ring of Copy version, Copy link and View licences is clipped at the bottom edge of the 800x632 window when Tab scrolls them into view. Repro: Settings, press Tab 10, 11 and 12 times from the top. Evidence: screens/m19a-focus-copy-version.png, m19a-focus-copy-link.png, m19a-focus-view-licences.png. At 360x640 the ring is complete.
  > - B3 (Minor): the toast covers the View licences button for about 3 s when Settings is scrolled to the end. Evidence: screens/m19a-toast-version-copied.png.
  > - B4 (Minor): after opening the licences page with the mouse, Esc puts focus on the Settings tab, not on View licences, because the click never focused the button. The keyboard path is fine. Evidence: screens/m19a-esc-returns-focus-view-licences.png.
  > Spec gaps (PM questions):
  > - R1: the spec says the three notices are "at the top"; in the real list only Kusunga is at the top and the others are alphabetical. Is that acceptable?
  > - A lower-case "kusunga" row (Flutter's own collection of the app licence) repeats the GPL text next to the pinned row. Keep it or hide it?
  > - Flutter's page title and counts use the US spelling ("Licenses"), while the app copy says "licences". Accept it?
  > - The version line says "— development build" and the caption "Development build" repeats it two lines lower (both are in the spec). Keep both?
  > - The "Test profile: qa" badge is not on the licences page (full-screen route). QA-only; no action unless the PM wants it.
  > Re-verified: none.
  > Needs PM: none required. Optional, if the PM wants the two items under Not observed: 1. Turn on Reduce motion in System Settings > Accessibility > Display, open Settings > About > View licences and check there is no slide. Turn it off again. 2. With VoiceOver on (Cmd+F5), Tab to Copy version and listen for "Copy version 0.9.0 build 1". Turn VoiceOver off.
  > Not observed: Reduce motion (needs a System Settings change, which QA must not make; covered by widget tests). Release-build tag link (v0.9.0): only debug builds were made; covered by BuildInfo unit tests. The "Couldn't copy. Try again." toast: I could not force a clipboard failure. Live VoiceOver: I read the AX tree instead. The licence-list spinner: too brief to catch. 200% text and the 840 px side-by-side layout. Windows. I did not run check.sh or flutter test, because flutter_tester was running in another worktree.
  > Accessibility: pass on what I could check (keyboard, 360 px, names from the AX tree, contrast), except B2 (focus ring clipped at the window bottom edge, arguably Major). Live screen reader and 200% text were not observed.
  > Privacy: n/a — no network, cookies or personal data in this item. Nothing was fetched, and the source link is shown as text only.
  > Claims: n/a
  > Dialogs and incidents: No keychain, permission or trust dialog appeared. A SecurityAgent helper process started at each launch (pids 74693 and 66873). System Events showed no window for it, Kusunga stayed frontmost and the app loaded, so I clicked nothing. One Return key press went to the Claude app instead of Kusunga, because my first key script had no frontmost check. It had no visible effect. After that every key press goes through a script that refuses unless Kusunga is frontmost. The click helper refused once for the same reason and sent nothing. The Mac clipboard was overwritten with test text (the version string and the link). I wrote one scratch screenshot to /tmp/x.png and deleted it.
  > Evidence: docs/qa/m1.md (section "M1.9a About and licences (2026-11-22)", with the PM check note); screens: docs/qa/m1/screens/ (22 files, prefix m19a-); videos: m1.9a-about-licences-flow.mp4 (60 s; in qa-artifacts/m1.9a/ in the worktree and in the main checkout, git-ignored, not committed).
  > Commit: ba6ed2b on feat/about-licences, docs/qa only, message ends with the Co-Authored-By Opus 5.5 line. Not pushed.
  > PM check steps: verified n/a — nothing needs the PM — docs/qa/m1.md#pm-check-m19a
  > Stopped: both qa Kusunga instances (pids 74536 and 66746), no ffmpeg left running. The qa profile is unchanged (3 made-up history items).
  > Blockers: none
  Lead: spot-checked m19a-focus-copy-version.png (qa label, made-up data only; the clipped ring is visible). Process note: QA's stray Return key went to the Claude app before it added a frontmost check — no effect seen, logged and told to the PM. B1–B4 go to the developer once the M1.9b developer's check run is done (checks never run in parallel). The new spec questions go to the PM.
- Gates: developer pass · tester pass · reviewer approve with notes · QA pass with 4 minor bugs; AC1/AC7 open (licence texts) · PM merge not asked
- Open findings: 4 minor (B1–B4); R5 (in plan), R6 open; AC1/AC7 open
- Decisions: none new
- Blockers: Developer sqlite3mc licence texts (PM) · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — licence texts, R1 order and 3 new spec questions

## 2026-11-22 — M1.9b Mac release build — reviewer: block; fixes back to the developer
- Changed: reviewer report (opus, high), word for word (sub-lists joined onto one line, wording unchanged):
  > Mode: branch
  > Branch: build/mac-release (32d419e..14ed399) — Verdict: block (R1 is Medium with no dated task in the plan. It becomes approve with notes if R1 is fixed, or if the lead adds a dated task with an owner and due date)
  > Checks: ./tool/check.sh — pass — "+3914 ~10: All tests passed!", exit 0. I confirmed `pgrep -fl flutter_tester` was empty before the run. `bash -n` and `/bin/bash -n` (3.2.57) both pass on tool/mac_release_guards.sh.
  > Code review: 4 findings (0 fixed, 4 open): R2, R3, R4 and the Later-line gap D1. R1 is listed under security.
  > Design review: 1 finding (0 fixed, 1 open): D1, a missing Later line for the Intel build.
  > Security review: 2 findings
  > - R1 Medium (no CVSS score: band + basis). Only someone committing to the tracked Local.xcconfig.example can trigger it, and PR review stands in their way. The xcconfig guard then says "ok" while Xcode turns on Swift conditions such as DEBUG. The binary guard still catches the marker downstream, so this is a gap in defence in depth, but it is in a gate AC10 requires.
  > - R2 Low (no CVSS score: band + basis). Same reach, with an even less likely trigger: the file is unreadable, or it is bigger than the pipe buffer (about 64 KB). The guard then exits 0 when it should exit 2.
  > The rest of the OWASP list: A01, A04, A07 and A09 are n/a (no endpoints, auth, crypto or logging). A02 holds: Release.entitlements has no Hardened Runtime exceptions, and the release build was checked with codesign, flags=adhoc,runtime. A03 is n/a (no new packages). A05 holds: the script only takes paths from the release script, quotes every expansion, and refuses paths that start with a dash. A06 holds: the design note's top threat, the test switch in a release, is covered by the binary guard, which I checked on real builds (see Evidence). A08 and A10: see R1 and R2. AI: n/a, no AI features. Secrets: none in the diff. The security-review skill ran against the session cwd (main checkout on fix/windows-ci), so its diff was empty and its result is not usable. I worked through references/security.md by hand on 32d419e..14ed399 instead.
  > Privacy review: no issues. No personal data, logs, network calls or storage are touched. Retention, erasure, processors, consent, SDKs and regions are n/a: this is build config and a release-time script only.
  > Later lines: none added by the branch. Added by reviewer: none, because this reviewer cannot edit files. The lead should add this line (see D1): "- Universal (Intel + Apple silicon) Mac build — D3 A ships Apple silicon only to avoid the Flutter 3.44.6 lipo failure on macOS 27, and Intel Macs on macOS 26 or older get no build — trigger: ≥ 1 tester or user asks for an Intel build, or the pinned Flutter is upgraded past 3.44.6 — noted 2026-11-22 by reviewer"
  > Findings (most severe first):
  > - R1 — Medium — tool/mac_release_guards.sh:71-72
  >   - Failure scenario: the xcconfig guard exits 0 ("ok") for four spellings that Xcode does honour. I checked each one with `xcodebuild -showBuildSettings -target Runner -configuration Release`, on a copy of macos/ in the scratchpad, with the probe saved as Local.xcconfig (AppInfo.xcconfig pulls it in with `#include?`):
  >     - (a) `OTHER_SWIFT_FLAGS = $(inherited) '-DDEBUG'`: Xcode gives `OTHER_SWIFT_FLAGS = '-DDEBUG'`.
  >     - (b) `KUSUNGA_FLAGS = -DDEBUG` plus `OTHER_SWIFT_FLAGS = $(inherited) $(KUSUNGA_FLAGS)`: Xcode gives `-DDEBUG`.
  >     - (c) `OTHER_SWIFT_FLAGS = $(inherited)-DDEBUG`: Xcode gives `-DDEBUG`.
  >     - (d) CR-only line endings, `DEVELOPMENT_TEAM = X\rSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG\r`: Xcode gives `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`.
  >   - Who is affected: if someone edits the example file this way, developers who copy it build release binaries with DEBUG code in them, including the synthetic-keys switch. AC10's second bullet ("a guard checks that Local.xcconfig.example sets no Swift compilation conditions") is not met, and ADR 0003's last Build-facts line overstates what the guard does.
  >   - Expected fix: allow-list the keys the signing example may set (DEVELOPMENT_TEAM, CODE_SIGN_STYLE, CODE_SIGN_IDENTITY, PROVISIONING_PROFILE_SPECIFIER). Any other key, or any `-D` token anywhere outside a whole-line `//` comment, exits 1. Turn CR into LF before matching. Add a regression test for each of (a) to (d), and give both runs (fails on 14ed399, passes after).
  > - R2 — Low — tool/mac_release_guards.sh:71
  >   - Failure scenario: `grep -v ... | grep -Eq ...` runs under `set -o pipefail`, so any non-zero status from either grep makes the `if` false, and the guard prints "ok".
  >     - A `chmod 000` file holding `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG` prints "grep: Permission denied", then "ok", and exits 0.
  >     - A 789 KB file with that line first exits 0 in 5 out of 5 runs: grep -q stops at the match, and grep -v then dies on SIGPIPE (141).
  >   - This breaks the script's own rule that exit 2 means the guard could not run. The binary guard handles the same cases correctly.
  >   - Expected fix: capture the output first with `filtered="$(grep -v '^[[:space:]]*//' "$file")" || rc=$?`, exit 2 if rc > 1, then run `grep -Eq '...' <<< "$filtered"` with no pipe. Add tests: an unreadable file exits 2, and a large file with the setting first exits 1.
  > - R3 — Low — tool/mac_release_guards.sh:20 against macos/Runner/TypedShortcutCore.swift:287
  >   - Failure scenario: the needle is hard-coded and no test ties it to `SyntheticKeysSwitch.argument`. test/ci/typed_shortcut_guards_test.dart:343 only checks `seen >= 4` across four needles, so it still passes without the marker. If someone renames the argument (for example to `-KusungaAllowSyntheticKeys`), the release guard passes every build from then on, including one built with DEBUG on.
  >   - Expected fix: a test that reads `static let argument = "..."` from TypedShortcutCore.swift and checks that it contains the script's needle.
  > - D1 — Low (design, plan hygiene) — docs/PLAN.md "Later" section
  >   - Failure scenario: the design note's D3 row says "Intel becomes a Later line", but neither main nor the branch has one, so the Intel deferral has no trigger and could be forgotten.
  >   - Expected fix: the lead adds the line given under "Later lines" above.
  > - R4 — cleanup — test/ci/mac_release_guards_bugs_test.dart:5-8
  >   - The header says "Each of these FAILS on the branch today", which is no longer true after 14ed399. A reader could treat a real regression as an expected failure.
  >   - Expected fix: reword it as regression tests for BUG-M1, M2, M3 and M5. Optional: the three test files each define the same fixture helpers (bin/app/guard), and these could be shared.
  > Notes for M1.9e (not findings on this branch):
  > - The file that actually reaches signed builds is the git-ignored Local.xcconfig. AppInfo.xcconfig includes it at target level for every configuration, so it can also override Release.xcconfig's ARCHS and ENABLE_HARDENED_RUNTIME. The release script should: run `xcconfig` on the real Local.xcconfig as well, if it exists; check `lipo -archs` = arm64 and that the codesign flags include "runtime" on the shipped binary; run `binary` on a Debug build as a positive control, expecting exit 1.
  > - A dropped code-review idea: Profile signs with DebugProfile.entitlements, which has allow-jit, under Hardened Runtime. The ADR only claims that the release entitlements have no exceptions, which is true, and Profile is not shipped.
  > - Also dropped: RunnerTests under the Release Hardened Runtime: CI runs XCTest in Debug only (check.yml:25). Per-file grep speed: the Release .app has 36 files and the scan takes 0.16 s.
  > Evidence I gathered (all reads, nothing launched, built, signed or pushed):
  > - `xcodebuild -showBuildSettings` on the scratch copy: Release: ARCHS=arm64, ENABLE_HARDENED_RUNTIME=YES, MACOSX_DEPLOYMENT_TARGET=12.0. Profile: ARCHS=arm64, ENABLE_HARDENED_RUNTIME=YES, ONLY_ACTIVE_ARCH=NO. Debug: ARCHS=arm64 x86_64, ONLY_ACTIVE_ARCH=YES, ENABLE_HARDENED_RUNTIME=NO, SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG. So the inheritance works as intended, and Debug is untouched.
  > - Flutter 3.44.6 `build_macos.dart` passes a generic destination and no ARCHS for release, so the xcconfig ARCHS is what applies.
  > - The worktree's Release build: `lipo -archs` gives arm64, and codesign gives flags=0x10002(adhoc,runtime).
  > - Binary guard on real builds, using /bin/bash 3.2: main checkout's Debug Kusunga.app: exit 1 (marker found in Contents/MacOS/Kusunga.debug.dylib); worktree Release and Profile .app: exit 0. I found no false pass in the binary guard: no pipes, find and grep errors give exit 2, there are no locale problems, and symlinked targets give exit 2.
  > - ADR 0003 Build facts are accurate apart from the R1 overstatement. 12.0 traces back to d94a892 (Xcode 27.2), and D3 A is dated 2026-11-19.
  > - Probe files are in scratchpad/xcprobe/. No git refs were created.
  > Fix outcomes: none yet (first review round).
  > Risk accepted by PM: none
  > Open items: R1 (Medium, open, no dated task), R2 (Low), R3 (Low), D1 (Low, needs the lead to add the Later line), R4 (cleanup)
  > Blockers: none. ReportFindings was not available in this session, so the findings are in this report instead.
  Lead: D1 done — the Intel Later line is in docs/PLAN.md. The M1.9e notes became one M1.9 AC in docs/PLAN.md (real Local.xcconfig guard, lipo and runtime checks, Debug positive control, ./ or absolute paths). R1–R4 go back to the developer (round 3, effort raised to high after a failed review round). No dated-task route for R1: it is fixed now.
- Gates: developer round 3 · tester pass · reviewer block (R1 Medium) · QA open · PM merge not asked
- Open findings: 1 medium (R1), 2 low (R2, R3), 1 cleanup (R4); D1 closed by the lead
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — PM decisions: push main; `name.json.json` to Later
- Changed: Later line added in docs/PLAN.md for the doubled `.json` save name. Main pushed to origin with the PM's approval.
- Gates: n/a — docs and decisions only
- Open findings: none
- Decisions: PM (2026-11-22) approved pushing main and chose Later for the `name.json.json` observation — PM said: "Yes, push main, and add name.json.json to Later"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — M1.9b Mac release build — developer round 2; reviewer dispatched
- Changed: developer report (sonnet, round 2), word for word ("How to verify" steps left out here):
  > Branch: build/mac-release (4 commits on top of main; round 2 added 14ed399 to tip 39b7d7a)
  > Built:
  > - All four bugs are fixed in tool/mac_release_guards.sh only. No production config touched.
  > - BUG-M1: `export LC_ALL=C` at the top of the script, so grep, find and the rest read bytes whatever the caller's locale.
  > - BUG-M2: the xcconfig regex is now `OTHER_SWIFT_FLAGS[^=]*=(.*[[:space:]"=])?-D`, so -D is caught right after `=`, after whitespace or after a quote. Comments, [sdk] conditions, CRLF, tabs and -Xfrontend -DX behave as before.
  > - BUG-M3: find now lists only non-empty files (`-size +0c`). An empty file, or a bundle of only empty files, exits 2 with "nothing to scan".
  > - BUG-M5: a target starting with `-` exits 2 with a hint to write `./-name`. This is by design: the repro test expects exit 2 even for a clean existing dash path. `./-x` still works. A find failure now exits 2, never 1.
  > Tests: full check.sh passed ("All tests passed!", +3914 ~10, which is 3914 passing and 10 skipped).
  > - New tests: none added. The 7 existing repros in test/ci/mac_release_guards_bugs_test.dart now pass and were not weakened. The edge test file is unchanged and passes.
  > - First failing run, before the fix: `flutter test` on the bugs and edge test files gave +5 -7 for the bugs file and +37 -7 overall. Failing: BUG-M1 (LANG only, and marker next to invalid UTF-8), BUG-M2 (no space around =, quoted flags, and others), and the M3 and M5 repros, which were not individually named in the truncated output.
  > - The only failure after the M1-M3 edits was M5 (`a path starting with a dash exits 2, not 1`), which I then fixed.
  > E2E: n/a — no suite (desktop UI automation is TBD per CLAUDE.md).
  > Test hooks: n/a — no UI.
  > Deviations from plan: none.
  > Checklists: none — n/a: data-and-apis and ui-build (a shell script fix only).
  > Risks / unverified:
  > - I did not run the script under /bin/bash 3.2 myself. The edge-test group "bash 3.2 (stock macOS)" passes and it is part of the 3914.
  > - Dash-leading paths are rejected rather than normalised. The Mac release script (M1.9e) must pass `./` paths or absolute paths.
  > - Documented limits remain: UTF-16 and NUL-split markers are not found, and symlinks are not followed.
  > Personal data touched: none.
  > Later lines added: none.
  > Spec gaps raised: none.
  > Findings: BUG-M1 — fixed (14ed399, mac_release_guards_bugs_test.dart); BUG-M2 — fixed (14ed399, same file); BUG-M3 — fixed (14ed399, same file); BUG-M5 — fixed (14ed399, same file).
  > Blockers: none.
  Lead: dispatched the reviewer (Mode: branch) on build/mac-release at 14ed399. M1.9e note added: the release script passes absolute or ./ paths to the guard.
- Gates: developer pass (round 2) · tester pass (repros green) · reviewer in progress · QA open (Hardened Runtime launch in the qa profile) · PM merge not asked
- Open findings: none open (BUG-M1, M2, M3, M5 fixed)
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — Windows CI green — merged and closed
- Changed: QA commit 90b2272 pushed to fix/windows-ci; PR 9 merged on GitHub with merge commit 8e9c141 (https://github.com/Thamzy265/kusunga/pull/9). Local main merged origin/main (4cdd25a). Plan box ticked. Local main still holds unpushed docs commits; pushing main waits for the PM.
- Gates: developer pass · tester pass · reviewer approve · QA pass · PM merge approved ("Merge, accept BUG-C1", 2026-11-22)
- Open findings: none; BUG-C1 residual accepted by the PM (entry below) and tracked in Later
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main

## 2026-11-22 — Windows CI green (PR 9) — PM approves the merge and accepts the BUG-C1 residual
- Changed: lead asked "May I merge PR 9, accepting the low BUG-C1 risk?" with the QA evidence (5/5 pass) and the merge route (push QA evidence commit 90b2272 to fix/windows-ci, then merge PR 9 on GitHub with a merge commit).
- Gates: developer pass · tester pass · reviewer approve · QA pass · PM merge approved
- Open findings: none
- Decisions:
  - Merge approved by PM (2026-11-22): PR 9, branch fix/windows-ci, merge commit on GitHub — PM said: "Merge, accept BUG-C1"
  - Risk accepted by PM (2026-11-22): accepted: BUG-C1 residual (low) — a link swapped into the export folder, by someone who can already write to it and has listed the random temp name, can make an empty file where it points, in the gap between the plain-file check and the open (every OS) and, on Windows, between the nothing-there check and the exclusive create; never the user's data — scope: PR 9 / fix/windows-ci, finding BUG-C1, tracked by the PLAN Later line "Export temp file made and opened with no gap at all against a link swapped in (BUG-C1 residual)" — expiry/review: when that Later line's trigger fires (the pinned Dart SDK gains a no-follow open mode, or ≥ 1 report of a stray empty file next to an export) — PM said: "Merge, accept BUG-C1"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-22 — Windows CI green (PR 9) — QA pass; merge approval asked
- Changed: PM unlocked the Mac ("Unlocked, run QA"). QA report (sonnet), word for word (lists joined onto one line, wording unchanged):
  > Milestone: Windows CI green (PR 9, `fix/windows-ci`) — 5/5 criteria pass — Date: 2026-11-22 — Environment: macOS 27.2, Flutter 3.44.6 / Dart 3.12.2, HEAD 275fd20 (code d3a8e6c), debug build from 2026-11-21 10:42, qa profile only
  > Automated: 4/5 criteria. Manual: row 5 (and the real-flow part of row 3). The app's Flutter UI exposes no AX tree, and the flow needs the native save panel, so QA used a CGEvent click helper plus System Events keystrokes.
  > Fail: none
  > Spec gaps: none
  > Re-verified:
  > - Rows 1, 2 and 4: one `gh run view 44895275732` showed the macos job green (35m23s) and the windows job green (33m54s). The run is the `pull_request` run for PR 9. I updated the rows to PASS citing that run.
  > - Row 3: the real-flow part passes. The BUG-C1 unit tests were not re-run by me, because another session was running `flutter_tester` and I don't run checks in parallel. CI run 4 ran them green.
  > Needs PM: none
  > Not observed:
  > - The export flow on a real Windows machine. Only CI covers Windows (PM or a Windows tester).
  > - A local re-run of the unit tests (see above).
  > - Any flaky history for the macos CI job. I looked only at run 4 and the earlier run 2.
  > Accessibility: n/a — this was a CI and export-correctness check, no new UI. The M1.8 sections above cover the export dialog.
  > Privacy: n/a — qa profile with made-up data only. The export files stay in git-ignored `qa-artifacts/qa-export/`. The "isn't encrypted" note was shown.
  > Claims: n/a
  > Evidence: `docs/qa/m1.md` section "Windows CI green (2026-11-21, updated 2026-11-22)". Screens are in `docs/qa/m1/screens/`, 7 new files, all `ci-5-*.png`: ci-5-settings-your-data.png, ci-5-export-dialog-note.png, ci-5-export-dialog-history-ticked.png, ci-5-save-panel.png, ci-5-replace-confirm.png, ci-5-toast-exported-snippets.png, ci-5-toast-exported-snippets-and-history.png
  > Video: `qa-artifacts/windows-ci-export-flow.mov` (git-ignored, Kusunga window region only, about 13 MB). The Kusunga window region contains only qa data, and the "Test profile: qa" label was visible in every shot.
  > Commit: 90b2272 on `fix/windows-ci`, with only `docs/qa` changes and the Opus 5.5 co-author line. Not pushed.
  > PM check steps: n/a — no PM steps, so nothing to verify.
  > Blockers: none
  > Row 5 detail (4 exports, all with made-up qa data: 4 snippets, 3 history items `qa-m18-copy-1..3`):
  > 1. Snippets only, new file `snippets-only.json`. 2646 bytes, valid JSON, 4 snippets with the expected names and texts, no `history` key. The dialog showed "The file isn't encrypted. Anyone who opens it can read it."
  > 2. History ticked, new file `with-history.json`. 3175 bytes, valid JSON, 4 snippets and 3 history items. The note was shown again.
  > 3. Snippets only, over the existing `with-history.json`. The native "replace it?" prompt appeared and I clicked Replace. The toast read "Exported 4 snippets". The file shrank to 2646 bytes and the `history` key was gone, so the old content was replaced, not appended.
  > 4. History ticked, over the existing `snippets-only.json`. The toast read "Exported 4 snippets and 3 history items". The file grew to 3175 bytes and now holds the 3 history items.
  > After every save `ls -a` of the folder showed only the two `.json` files, and `find qa-artifacts -name '.kusunga-export-*'` found nothing. No `.kusunga-export-*` temp file was left.
  > Dialogs seen: the Kusunga export dialog; the native save panel; the native "already exists, replace it?" confirmation. All three are part of the export flow QA started. No keychain, permission or trust dialog appeared.
  > Minor, not a bug: the save panel's name field already ends in `.json`. A name typed with `.json` became `name.json.json`. The panel opened in the last-used folder (`qa-artifacts/m1.8`), which is macOS behaviour.
  > Clean-up: the qa Kusunga (pid 61541) was quit by pid, and `pgrep` for it is empty. The screen recording is stopped, with no `screencapture` process left. QA started no `flutter_tester`. The PM's default profile and real data were not touched. The helper binary is only in the session scratchpad.
  Lead: spot-checked ci-5-save-panel.png and ci-5-toast-exported-snippets-and-history.png: qa label visible, only made-up data. The `name.json.json` observation goes to the PM as a question (possible small UX item), not a gate failure.
- Gates: developer pass · tester pass · reviewer approve (F1–F5 fixed) · QA pass (5/5) · PM merge waiting
- Open findings: none on the branch; BUG-C1 residual (low) waits for the PM's risk decision
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — merge approval of PR 9 and the BUG-C1 residual decision

## 2026-11-22 — M1.9b Mac release build — tester report; bugs back to the developer
- Changed: tester report (sonnet), word for word:
  > Branch: build/mac-release (2 test commits: 263105a edge tests, 39b7d7a bug repros; not pushed)
  > Added: 44 tests (37 pass, 7 fail as bug repros) in test/ci/mac_release_guards_edge_test.dart (37) and test/ci/mac_release_guards_bugs_test.dart (7). Worktree: scratchpad/m19b-wt
  > E2E tests added: 0 (n/a) — no user flow. The only real runs were the two flutter builds below.
  >
  > Real builds (macOS 27, bash 3.2.57, no Local.xcconfig so ad-hoc signed; app never launched; no keychain or signing dialog):
  > - `flutter build macos --release` succeeded (25.0MB). `flutter build macos --profile` succeeded (35.8MB). The lipo failure on macOS 27 is gone (AC8 met).
  > - Main binary: arm64 only on both. Embedded Frameworks (FlutterMacOS, objective_c): arm64 only.
  > - codesign on both: `flags=0x10002(adhoc,runtime)`, so Hardened Runtime is on (AC3 met).
  > - `tool/mac_release_guards.sh binary` on both .app: exit 0, with /bin/bash 3.2 in C and en_US.UTF-8 locales. Neither binary contains the marker.
  >
  > Fail-then-pass (mutation proof):
  > - All edge tests on merge base 32d419e (script gone, old Release.xcconfig): 29 of 37 fail. Binary tests fail with exit 127 (script not found); build-setting tests fail on the missing ARCHS/runtime.
  > - Release.xcconfig reverted only: "Release.xcconfig sets ARCHS and the runtime once, after its includes" fails.
  > - ARCHS changed to `arm64 x86_64`: the same test fails (and the developer's two build-setting tests).
  > - `ENABLE_HARDENED_RUNTIME = NO` added to the Release target in project.pbxproj: "no target or project setting overrides architectures or runtime" fails.
  > - Debug.xcconfig given an ARCHS line: "Debug gets no ARCHS or Hardened Runtime from its xcconfig files" fails.
  > - Profile project config re-pointed at Debug.xcconfig: "project-level Release and Profile use Release.xcconfig, Debug not" fails.
  > - Every mutation was reverted with git checkout. Production files are unchanged and `git status` is clean.
  > - The 7 bug-repro tests fail on the branch tip (cfa9f52) with the failures below.
  >
  > Regression locks (pass on old and new by design):
  > - Marker in a nested framework, dylib, resource, or across the 64KiB/1MiB/5MiB boundaries: locks that every file is scanned.
  > - In-bundle symlink, dangling symlink, only-symlinks bundle (2), top-level symlink (2): locks that nothing is silently skipped.
  > - Path with spaces/quotes, `./-dash.app`, a file named `-n`, unreadable file (2), C-locale invalid bytes.
  > - Exit codes: wrong arguments always 2, empty path 2, xcconfig on a directory 2, and the /bin/bash 3.2 exit codes.
  > - xcconfig spellings: `[sdk]`/`[config][sdk]`, tab, CRLF, no-space `SWIFT_...=X`, `$(inherited)`, `-Xfrontend -DX`, `-D X`, trailing `//` comment (caught), key inside a `//` comment (ignored).
  > - Project mapping: Release and Profile use Release.xcconfig and Debug uses Debug.xcconfig. No ARCHS, ENABLE_HARDENED_RUNTIME or x86_64 override anywhere in the pbxproj. Release.xcconfig sets ARCHS=arm64 and the runtime once, after its includes. Release and Profile have no DEBUG or -Onone settings. Deployment target is 12.0 everywhere.
  > - Documented limits, pinned so a change is noticed:
  >   - UTF-16 marker passes.
  >   - NUL-split marker passes.
  >   - Lower-case marker passes.
  >   - Symlink to a file outside the bundle passes (`find -type f` skips it; codesign rejects such bundles anyway).
  >   - xcconfig `#include` is not followed.
  >   - Lower-case xcconfig keys are not flagged (Xcode keys are case-sensitive, so they are inert).
  >
  > Bugs found (all in tool/mac_release_guards.sh; fix is developer work):
  > - BUG-M1 HIGH, false pass: in a UTF-8 locale (my terminal's default, LC_ALL/LANG=en_US.UTF-8), `grep -a -c -F` skips any line that has invalid UTF-8, so a marker on the same newline-delimited line as one invalid byte is missed and the release passes (exit 0).
  >   - Repro: a file of `0xFF` + KusungaAcceptSyntheticKeys, or the marker followed by `0xFF`, with `LC_ALL=en_US.UTF-8`. It exits 0; with `LC_ALL=C` it exits 1.
  >   - Not triggered on a real /bin/ls: 25 of 25 random offsets were caught, so exposure on real binaries is probable but not demonstrated. The fix is simple: run grep with `LC_ALL=C` inside the guard.
  >   - Repro tests: "BUG-M1 ... finds the marker next to bytes that are not valid UTF-8" and "... also with LANG only".
  > - BUG-M2 MEDIUM, false pass: the xcconfig guard misses `OTHER_SWIFT_FLAGS=-DX` (no whitespace before `-D`), `OTHER_SWIFT_FLAGS = "-DX"`, `"-D" "X"` and `$(inherited) "-D" X`. All exit 0. The regex needs whitespace before `-D`, and quoted flags break that.
  >   - Repro tests: "BUG-M2 ... no space around =" and "... quoted flags".
  > - BUG-M3 LOW, false pass: an empty file as the target, or a bundle whose files are all empty, exits 0 ("ok") although nothing was scanned. The "nothing to scan" rule (exit 2) is not applied.
  >   - Repro tests: "BUG-M3 ... an empty file is nothing to scan (2)" and "... a bundle whose files are all empty ...".
  > - BUG-M5 LOW, wrong exit code: `binary -dash.app` makes `find` fail on the dash-leading path and the script exits 1, which means "marker found". It should exit 2. The failure is safe but misleading.
  >   - Repro test: "BUG-M5 ... a path starting with a dash exits 2, not 1".
  > - Also noted, not a bug: the `#include` limit above. `Local.xcconfig.example` has none today.
  >
  > Abuse cases covered: n/a — M1.9b has no abuse cases of its own. I worked from the AC10 guard concerns (marker hiding, false passes) and covered all the binary-guard and xcconfig-guard cases you listed, except the two gaps below.
  > UI states covered: n/a — no UI.
  >
  > Gaps not covered:
  > - Profile and Release were only built and guarded once each, on this Mac. The Debug build and its effective settings were not built or inspected (an xcodebuild settings dump was not run); Debug was checked only statically (xcconfig and pbxproj).
  > - Notarisation and signing with a real identity (M1.9c/e) were not run.
  > - No positive control on a real built binary: the marker only exists in Debug builds, which were not built, so the guard was proven on fixtures and a modified /bin/ls only.
  > - The guard's behaviour on a non-macOS shell (Windows bash) was not run.
  > - `#include` following and xcconfig backslash continuation are not handled by the guard (documented limits).
  >
  > Production code changed: none
  > Suite: 3907 passing / 7 failing / 10 skipped (was 3870 passing / 0 failing / 10 skipped). `./tool/check.sh` ends with `04:49 +3907 ~10 -7: Some tests failed.` and exits 1. All 7 failures are the BUG-M1/M2/M3/M5 repros above. Format and analyze steps passed. `pgrep -fl flutter_tester` was empty before each run, and no background job is left.
  > Blockers: none (the check stays red until the developer fixes BUG-M1, M2, M3 and M5)
  Lead: the 4 bugs (BUG-M1 high, BUG-M2 medium, BUG-M3 and BUG-M5 low) are all in tool/mac_release_guards.sh and go back to the developer (same branch, sonnet, round 2). Reviewer and QA wait for the fix. Also running now: QA re-dispatched for the Windows CI export check (PR 9), the Mac is unlocked (PM: "Unlocked, run QA").
- Gates: developer round 2 · tester done (7 repro tests red until fixed) · reviewer, QA open · PM merge not asked
- Open findings: 1 high, 1 medium, 2 low (BUG-M1, M2, M3, M5)
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none (Mac unlocked) · Marketer none · Lead none

## 2026-11-21 — M1.9b Mac release build — developer hand-off; tester started
- Changed: lead created worktree build/mac-release from main 32d419e and dispatched the developer (sonnet). Size: part of M1.9 (large); this part is build config and guards, one platform, no data. Developer report, key lines word for word:
  > Branch: build/mac-release (1 commit, cfa9f52, not pushed)
  > macos/Runner/Configs/Release.xcconfig: `ARCHS = arm64` and `ENABLE_HARDENED_RUNTIME = YES`. This file is the project-level base for both Release and Profile; Debug is untouched (no hardened runtime, so local runs and unit-test hosts load unsigned code as before).
  > tool/mac_release_guards.sh, for the M1.9e release script to call. `binary <Kusunga.app|file>` exits 1 if any file in the bundle contains KusungaAcceptSyntheticKeys. `xcconfig <file>` exits 1 if non-comment lines set SWIFT_ACTIVE_COMPILATION_CONDITIONS or a -D in OTHER_SWIFT_FLAGS. Exit 2 means the guard could not run [...]. The binary guard uses `grep -a -c -F` on the raw bytes, not `strings`. [...]
  > ADR 0003 has a new "Build facts" section: minimum macOS 12.0 (AC9), arm64 only (D3 A), Hardened Runtime on for release/profile, and the guards.
  > Tests: 3870 passing, 10 skipped (the full `./tool/check.sh` ended "All tests passed!"; format and analyze passed). 15 new tests in test/ci/mac_release_build_guards_test.dart. [...] First failing run, before the script and settings: `00:00 +1 -14: Some tests failed.`
  > Risks / unverified: The Hardened Runtime build was NOT launched (rule: never launch). [...] QA should check it with the qa-profile launch below. [...] The ad-hoc release app carries the entitlement `com.apple.security.get-task-allow = true`. Xcode injects it for non-distribution signing, and notarisation rejects it. M1.9c/e must sign with Developer ID so it is dropped, then check with `codesign -d --entitlements -`. I did not change signing. Entitlements: I added none.
  > Build evidence: `flutter build macos --release` gave "✓ Built build/macos/Build/Products/Release/Kusunga.app (25.0MB)". `flutter build macos --profile` gave "✓ Built build/macos/Build/Products/Profile/Kusunga.app (35.8MB)". `lipo -archs` on each Mach-O in both apps: arm64 [...]. `codesign -dv --verbose=4` on the release app: `flags=0x10002(adhoc,runtime)`, Signature=adhoc, TeamIdentifier=not set.
  > Blockers: none. No keychain or signing dialog appeared. No background jobs are left.
  ("[...]" marks lines left out here.) Lead: the get-task-allow point is noted for M1.9e (the release script's codesign/notarisation checks will fail on it; M1.9e adds an explicit `codesign -d --entitlements -` check). Tester dispatched.
- Gates: developer pass · tester in progress · reviewer, QA open (QA needs an unlocked screen for the Hardened Runtime launch) · PM merge not asked
- Open findings: none
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — as in the morning report

## 2026-11-21 — M1.9a About and licences — reviewer: R10 fixed, approve with notes
- Changed: reviewer confirmation, key lines word for word:
  > R10 is fixed and the verdict stays approve with notes. [...] Verdict: approve with notes [...] My focused run [...] at 38b4f77 passed: "+40 ~1: All tests passed!" [...] Findings (most severe first, both Low): R6 [...] R5 [...] Separate from the code verdict, AC1/AC7 can't be ticked until: the verbatim sqlite3mc texts are in the asset, the MIT test is unskipped, R6's checks are added, and `tool/check_sqlite3mc.sh` has been run and recorded on the Windows sqlite3mc.dll. Nothing else in the branch blocks once those land. Blockers: none
- Gates: developer pass · tester pass · reviewer approve with notes · QA open (needs an unlocked screen; also waits for the texts for AC1/AC7) · PM merge not asked
- Open findings: R5 Low (AC in plan), R6 Low (texts)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — R10 fixed; reviewer confirms
- Changed: developer report, key lines word for word:
  > R10 is fixed in 38b4f77 on feat/about-licences (on top of 0f032a7, not pushed). `./tool/check.sh` passed: `04:17 +4046 ~11: All tests passed!`
  > First failing run, before the full stop: `Expected: contains 'public domain. It is only compiled'  Actual: '... only assumes it is public domain It is only compiled with SQLITE_ENABLE_EXTFUNC. ...'`
  > Findings: R10 — fixed (38b4f77, "extensionfunctions.c paragraph reads as sentences on the page")
  > Blockers: none. [...] No flutter_tester or other job is left running.
  Reviewer asked to confirm R10.
- Gates: developer pass · tester pass · reviewer approve with notes (R10 confirm pending) · QA open (screen locked) · PM merge not asked
- Open findings: R6 Low (texts); AC1/AC7 notice texts and Windows DLL check
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — reviewer re-check 2: approve with notes; R10 to developer
- Changed: reviewer re-check 2 on 0f032a7, key lines word for word:
  > Verdict: approve with notes
  > Code review: 6 findings (4 fixed, 1 open Low, 1 no_change_needed) [...] Design review: 5 findings (3 fixed, 2 open Low) [...] Security review: 0 findings. [...] Privacy review: no issues.
  > R10 — Low (cosmetic, in the shipped notice text) — assets/licences/sqlite3mc.txt:59-60. What happens: Flutter's LicenseEntryWithLineBreaks joins lines with the same indent into one paragraph. The "Licence:" line has no full stop, so the page shows: "Licence: No licence text. Upstream `filelist.md` only assumes it is public domain It is only compiled with SQLITE_ENABLE_EXTFUNC. [...]". Expected fix: add a full stop at the end of line 59. A test on the parsed paragraph text would be good.
  > R6 — Low (carried) [...] R5 — Low (carried) [...]
  > R4 deviation judged: accepted. The developer's rule is correct, and it is better than mine. [...] Does the loop terminate? Yes. [...]
  > Fix outcomes: R4 — fixed. R8 — fixed. R9 — fixed. Earlier outcomes stand: R1 fixed, R2 fixed, R3 no_change_needed [...], R5 carried to M1.9e, R7 fixed.
  > Open items: R10, R6 and R5 are Low [...]. Separate from the code verdict, AC1/AC7 can't be ticked until: the verbatim sqlite3mc texts are in the asset, the MIT test is unskipped, R6's checks are added, and `tool/check_sqlite3mc.sh` has been run and recorded on the Windows sqlite3mc.dll. Nothing else in the branch blocks once those land.
  > Blockers: none
  ("[...]" marks lines left out here.) Lead: R5's AC is already in docs/PLAN.md (5d5685a). R10 is a one-line fix plus a test; sent to the developer now. R6 waits for the texts. The Windows DLL check goes with M1.9b/e.
- Gates: developer R10 · tester pass · reviewer approve with notes · QA open (screen locked) · PM merge not asked
- Open findings: R10 Low (in progress); R6 Low (texts); AC1/AC7 notice texts and Windows DLL check
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — developer round 4 (opus); reviewer re-check 2
- Changed: developer (opus, high effort) report, key lines word for word:
  > All four items are fixed in 4 new commits on feat/about-licences. Nothing is pushed. `./tool/check.sh` passed: `04:14 +4045 ~11: All tests passed!`
  > Branch: feat/about-licences (4 new commits on 777e36e: fb6350c, ffeffd8, 6b8ca18, 0f032a7).
  > R4: opening View licences with the keyboard now puts focus on the first row. [...] Focus outside the page (View licences still has it after Tab and Enter): "not yet", keep waiting. `_start`, or a route scope inside the page: the page still holds focus, so move it to the first row. Any other node inside the page: the user moved it, so stop. Why not the rule you suggested [...]: in the real Settings flow, primary focus ends on the scope of LicensePage's own nested Navigator, which sits *inside* `_start`, not on `_start`. Your rule would read that as the user moving focus and stop again.
  > R8: `skipTraversal: true` on the `_start` Focus. [...] R9: the 320 px / 200% text test now checks that the exception it takes is the overflow. Cleanup: the extensionfunctions.c cell in docs/licences.md and the matching line in assets/licences/sqlite3mc.txt now both read "It must not be compiled in; enforced by tool/check_sqlite3mc.sh (macOS checked 2026-11-21; Windows checked before release)."
  > First failing runs: R4, run against unchanged 777e36e code: all 4 "Tab and Enter/Space open" tests failed with `Expected: true Actual: <false>` [...]. Your probe [...] on 777e36e printed `keyboard=true ... firstRow=false` [...]. After fb6350c and again after ffeffd8 it prints firstRow=true in all 4 cases. R8 [...] both cycle tests failed with `Expected: not contains 'licences start'`. R9 [...] the old bare `takeException()` passed [...]. The new assertion failed [...]. Cleanup: failed first with `Expected: contains 'must not be compiled in'`.
  > Deviations from plan: R4 uses the "focus outside the page / page holds / user moved" rule above instead of the exact rule you suggested, for the nested-Navigator reason given under Built.
  > Findings: R4 — fixed (fb6350c) | R8 — fixed (ffeffd8) | R9 — fixed (6b8ca18) | Cleanup — fixed (0f032a7)
  > Blockers: none. My one check.sh run (in the foreground) was moved to the background by the tool after 180 s. I waited for it to finish and started nothing else. No flutter_tester or other job is left running.
  ("[...]" marks lines left out here.) Reviewer re-check 2 dispatched.
- Gates: developer pass · tester pass · reviewer re-check 2 in progress · QA open · PM merge not asked
- Open findings: R4, R8, R9 waiting for re-check; R6 pending texts; AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — reviewer re-check: block (R4 reopened, R8, R9); developer round 4 on opus
- Changed: reviewer re-check on 777e36e, key lines word for word:
  > Verdict: block
  > R4 (reopened) — Medium (spec focus rule fails for keyboard users, the users it is for) — lib/about/licences.dart:104-107 (`_userMovedFocus`). Steps to reproduce: Tab to View licences, press Enter, let the notices load. What happens: focus stays on the invisible wrapper ("licences start"), not the first row. Why: the first post-frame callback runs before the route's focus moves, which happens in a microtask after the frame. At that moment the primary focus is still the View licences button: not `_start` and not a FocusScopeNode. So `_userMovedFocus` returns true and the loop stops for good. Opening with a tap works, because a tap doesn't focus the button. [...] Why the tests stay green: the new tests open the page by tapping. [...] Expected fix: count it as "user moved" only when the focus is inside the page and is not `_start`, for example `_start.hasFocus && !_start.hasPrimaryFocus`. Until `_start` holds focus, keep waiting. Regression test: open with Tab+Enter and assert the first row has focus. It must fail on 777e36e.
  > R8 (new) — Medium (basic accessibility, WCAG 2.4.7 Focus Visible, AA; never deferred) — lib/about/licences.dart:150-151. What happens: the `_start` Focus is a normal Tab stop with no visible indicator. [...] Expected fix: `skipTraversal: true` on that Focus. Autofocus still gives it focus at once, so Esc keeps working. Add a test that cycling with Tab never puts primary focus on "licences start".
  > R9 (new) — Low (test quality) — test/about/about_edge_test.dart:423-428. [...] a bare `tester.takeException()` throws away any exception, so a different, real error during opening would also pass. Expected fix: assert the taken exception is the overflow [...].
  > Fix outcomes: R1 — fixed. R2 — fixed. R3 — no_change_needed. My finding was wrong. [...] R4 — not fixed (reopened above). R5 — no_change_needed on this branch. [...] R6 — stays open until the verbatim texts land. R7 — fixed.
  > Your question (3) [...] accepted on the lead's basis. [...] Low cleanup: docs/licences.md:49 now says in one cell both "not compiled into Kusunga's binaries" and "Windows binary not checked". [...] word it as the rule ("must not be compiled in; enforced by tool/check_sqlite3mc.sh").
  > Open items: R4 and R8: focus. A small fix, but basic accessibility is never deferred, so they block. R9: Low [...]. No other part of the branch blocks once the texts land.
  ("[...]" marks lines left out here; the full report is in the agent hand-off.) Lead: R5's AC is already in docs/PLAN.md on main (5d5685a). R4 failed a second round, so the developer goes to opus (high effort) for R4, R8, R9 and the docs/licences.md:49 wording.
- Gates: developer round 4 (opus) · tester pass · reviewer block · QA open · PM merge not asked
- Open findings: R4 Medium, R8 Medium, R9 Low, docs cell cleanup; R6 pending texts; AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — developer round 3; reviewer re-check
- Changed: developer (sonnet, high effort) round 3 on feat/about-licences, 5 commits on 31aca27, HEAD 777e36e. Report key lines, word for word:
  > Findings: R1 — fixed (a4d1e85; binding_order_test.dart, about_edge_test.dart "Kusunga is the first row" and "both SQLite notices are reachable", registry tests) | R2 — fixed (d01a7a8; about_edge_test.dart "page transition" group) | R3 — disputed → no_change_needed (688cfcf adds the tightened test only: one Esc on a notice goes to the list, the next goes to Settings with focus on View licences. On the unchanged old code at 31aca27 that test passes. A probe at 320 px, after tap-open, Tab, then Esc, also left only the detail popped. Cause: flutter/lib/src/material/about.dart:1396 wraps the nested Navigator in `NavigatorPopHandler`, a `PopScope(canPop: false)`. The outer route's `maybePop()` (our Esc binding) is therefore handed to the nested navigator first. I could not reproduce the whole-page close. If the reviewer still sees it, I need the exact steps and focus state.) | R4 — fixed (e3bfe9a; about_edge_test.dart "focus moves to the first row" at 320 and 900 px, plus "Esc on the first row goes back to Settings") | R7 — fixed (777e36e; comment finished by removal, y-position Tab test removed in favour of about_edge_test.dart, docs/licences.md flag 2 updated, extensionfunctions.c line and docs row updated, reachability tests green). R5 and R6 not in this round.
  > Tests: `./tool/check.sh` ran alone, in the foreground (it was moved to the background after 3 min, but no second copy ran). `pgrep -fl flutter_tester` was empty before it. Result: format "Formatted 301 files (0 changed)", analyze "No issues found!", test "04:14 +4034 ~11: All tests passed!"
  > First failing runs: R1: `Expected: ['Kusunga'] Actual: ['Copyright 2013 The Flutter Authors']`; R1 reachability: `Bad state: No element`; R2: `Expected: Duration:<0:00:00.000000> Actual: Duration:<0:00:00.450000>`; R4: "focus moves to the first row, at 320 px" and "at 900 px" both failed with `Expected: true Actual: <false>`.
  > Deviations: the widget test registers `registerLicences()` first and a fake binding-style collector after it, because that is now the real order; the real order is proven by `binding_order_test.dart` with the real binding. Three registry tests adapted to the new entry shape (`['Kusunga']`, `['Kusunga','SQLite3 Multiple Ciphers']`, `['Kusunga','SQLite']`). The 320 px / 200% text test now calls `tester.takeException()` once after opening: with the zero-duration route, Flutter's own loading view overflows by 532 px for under 1 s (debug stripes only); not worked around.
  > Risks: the `extensionfunctions.c` line says "not compiled into Kusunga's binaries", but only the macOS binaries are checked; the Windows binary is not checked yet. Observation, not changed: the `Focus(autofocus)` that holds the Esc binding is itself a Tab stop with no visible ring; `skipTraversal: true` would remove it.
  > Blockers: none.
  Lead: the extensionfunctions.c sentence stays (AC1 requires the Windows DLL check before any build ships; until then the claim is covered by that gate). The invisible Tab stop goes to the reviewer to judge in the re-check. R3 dispute goes to the reviewer.
- Gates: developer pass · tester pass · reviewer re-check in progress · QA open · PM merge not asked
- Open findings: R3 disputed; R6 pending texts; AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — reviewer: block (R1–R7); developer round 3
- Changed: reviewer (opus, Mode: branch) report, word for word:

  > Mode: branch
  > Branch: feat/about-licences (8614d88..31aca27) — Verdict: block
  > Checks: ./tool/check.sh — not run by me (you told me not to). The developer reports "+4025 ~11: All tests passed!". My focused run of `flutter test test/about test/ci/sqlite3mc_extfunc_check_test.dart test/ci/sqlite3mc_extfunc_abuse_test.dart` at 31aca27 passed: "+170 ~1: All tests passed!" (the 1 skip is the known MIT-notice test). pgrep showed no flutter_tester running before the run.
  > Code review: 4 findings (0 fixed, 4 open): R1, R3, R6, R7
  > Design review: 3 findings (0 fixed, 3 open): R2, R4, R5
  > Security review: 0 findings. Manual pass, OWASP items: A01, A07, A09: n/a (no endpoints, auth or security events). A02: no debug-only config in this change. A03: no new package, pubspec.lock unchanged, the pubspec diff adds assets only. A04: n/a. A05: the script quotes every path and uses fixed grep patterns. The abuse tests cover odd names, symlinks and newlines. A06: the design note's sqlite3mc supply-chain case is served by the script. A08: notices are bundled assets, never fetched. A10: a failed licence load leaves that notice out, and a failed copy shows the error toast. AI: n/a, no AI features. I did not run the `security-review` skill. origin/HEAD (7e9baf5) is behind the review base 8614d88, so it would mix unrelated commits into the review. The skill only allows the temporary ref when there is no remote.
  > Privacy review: no issues. No network use: no url_launcher, HttpClient or dart:io in lib/about. Nothing is logged. Own copies go through ClipboardSource.writeOwn (the same path snippets use, lib/history/history_service.dart:79) and never through Clipboard.setData. Test about_edge_test.dart "both buttons leave history empty and use only writeOwn" shows no history item and no platform setData. n/a: retention, erasure, consent, processors and regions. No personal data is involved.
  > Later lines: none added (docs/PLAN.md is not touched) — added by reviewer: none
  > Findings (most severe first):
  > - R1 — Medium (spec conformance, and the test meant to catch it is a false green) — lib/about/licences.dart:21-24 (comment "so they are listed at the top") and test/about/about_edge_test.dart:486-503. What happens: Flutter's LicensePage pins only the first package of the first licence collector, then sorts the rest case-insensitively (flutter/lib/src/material/about.dart:946-963). In the real app, WidgetsFlutterBinding.ensureInitialized() registers the NOTICES collector (ServicesBinding.initInstances → initLicenses) before main() calls registerLicences(). So "abseil-cpp" is pinned first, and our three entries sort in with everything else. Simulated with the real Release NOTICES.Z (about 146 rows): Kusunga is row 59 (after "khronos"), SQLite row 111 (next to the engine's own "sqlite"), SQLite3 Multiple Ciphers row 113. I reproduced it with a widget test in my scratchpad that registers a binding-like collector first: "ORDER: [abseil-cpp, archive, Kusunga, path, SQLite, sqlite3, SQLite3 Multiple Ciphers]". Impact: every tester who opens the licences finds the GPL text, which the GPL 5(d) notice tells them to see, buried mid-list. The spec says "Kusunga, SQLite3 Multiple Ciphers and SQLite at the top". Why the test stays green: it registers its fake after ours (the opposite of start-up order). It asserts only Kusunga's position. Its comment ("pub package names are lower case, so they sort after these capitalised names") is wrong: the sort lower-cases both names. Expected fix: register Kusunga's collector before the binding's, for example a WidgetsFlutterBinding subclass whose initLicenses() calls registerLicences() before super.initLicenses(). That pins "Kusunga" first. For the two SQLite notices, either also yield those entries under the "Kusunga" package so they are reachable from the top row, or the PM accepts alphabetical placement and the spec is updated (PM decision). Rewrite the test to register a binding-style collector first and assert all three positions. Fix the comment.
  > - R2 — Low (spec accessibility note "Motion: the page transition follows the existing prefers-reduced-motion handling" is not met; WCAG 2.3.3 is AAA, so not an AA failure) — lib/about/licences.dart:45-46. What happens: MaterialPageRoute ignores MediaQuery.disableAnimations (no reduced-motion handling in material/page*.dart, page_transitions_theme.dart or widgets/routes.dart). A user with Reduce motion on still gets the slide or zoom transition. The rest of the app honours it (history_row.dart:172, picker_panel.dart:86). Expected fix: use a zero-duration transition when MediaQuery.disableAnimationsOf(context) is true, plus a test.
  > - R3 — Low (keyboard path differs from the spec flow) — lib/about/licences.dart:48-50. What happens: under 840 px, LicensePage shows a package's text in its own nested Navigator. The Esc binding pops the outer route, so Esc on a package's text closes the whole licence page and lands on Settings. The Back button returns to the list. The spec flow is P → Back → L, then L → Back/Esc → Settings. Test about_edge_test.dart:440-458 accepts "one or two Esc presses", so it can't tell the difference. Expected fix: Esc pops the innermost navigator first (for example maybePop on the Navigator of FocusManager.instance.primaryFocus?.context, falling back to the outer one). Assert exactly one press goes detail → list.
  > - R4 — Low (spec deviation, needs the PM's OK or a spec update) — lib/about/licences.dart:53-54. What happens: focus lands on a wrapper Focus, not on the first row as the spec says ("Focus moves to the first row"). A keyboard user needs extra Tabs to reach the list. Reasonable, because the rows load asynchronously. Either the PM accepts it and docs/ui/about-and-licences.md is updated, or focus moves to the first row once the list has loaded.
  > - R5 — Low (R1 source offer and R2 version are not enforced) — lib/about/build_info.dart:22-26. What happens: a release build made without --dart-define=KUSUNGA_VERSION/KUSUNGA_BUILD silently ships "Kusunga (version unknown)" and the plain repo link, not the tag. Nothing fails. Expected fix: no code change on this branch. The lead adds an AC to M1.9e (release script) that the defines come from the tag and the build fails if they are missing or differ from the tag.
  > - R6 — Low (licence completeness once the texts land) — test/about/licence_registry_test.dart:101-115. What happens: the only verbatim-text test checks the MIT notice. BSD-3-Clause (SHA-2, Olivier Gay) and each MIT part (AEGIS, miniz, Ascon, rijndael) need their copyright line and licence text in the binary too. The SPDX-name tests would pass on an index with no texts. Expected fix: when the texts land, the tester adds per-part checks (for example "Redistribution and use in source and binary forms" plus the Olivier Gay copyright line, and each MIT copyright line).
  > - R7 — cleanup (can wait: no behaviour impact): test/about/about_edge_test.dart:24 has an unfinished doc comment ("Open bugs ... run them with"). docs/licences.md:56 still says "An in-app licence screen is out of scope for this item", which is now wrong. about_section_test.dart "Tab order" compares y positions only. The real Tab test is in about_edge_test.dart. Optional: the extensionfunctions.c line in assets/licences/sqlite3mc.txt could say it is not compiled into Kusunga's binaries, so readers don't think it ships.
  > Developer deviations judged: Accepted: Navigator.push + Esc: showLicensePage does the same MaterialPageRoute push. "Kusunga 0.9.0" when there is no build number. --dart-define with trim and v-strip: the spec lets the developer choose. See R5. Copy version copies the whole line including " — development build": it matches the spec's "copies that text" and keeps reports honest. copyOwn through writeOwn: it is the snippet rule, D1, and it is tested. tool/check_sqlite3mc.sh kept out of check.sh: in check.sh it would fail on any fresh clone by design. The release run belongs to R3/M1.9e. extensionfunctions.c listed as an upstream part: lead decision. Needs PM: initial focus (R4).
  > Check script reliability: no false-pass path found. It fails on a missing, empty or unreadable file and on one with no sqlite_master. It fails when it finds nothing to check. It runs LC_ALL=C, so it handles bytes that are not valid UTF-8. The distinctive names (strfilter, charindex, leftstr, rightstr, lower_quartile, upper_quartile) are matched inside strings, so the linker merging string tails can't hide them. On the real binaries, built-in SQLite function names such as "acos", "regexp" and "sqlite3mc_config" are seen as whole strings, so the method works on real files. With no argument it passes on every Mac binary in the main repo: 2 dylibs (x86_64 and arm64), and the Debug and Release framework binaries.
  > GPL 5(d): the About section shows the copyright, NO WARRANTY, GPL-3.0-only, and how to view the licence (View licences, whose Kusunga entry holds the full LICENSE, tested byte for byte). The legalese is the GPL's interactive notice. It complies, apart from the prominence problem in R1.
  > Fix outcomes: none yet
  > Risk accepted by PM: none
  > Open items: R1 to R6 are open. R7 is cleanup. AC1/AC7 stay open for the known verbatim sqlite3mc texts, and the MIT test must be unskipped. Once the texts land, these still block: R1 (or a PM decision on the order), and R6's verbatim checks for the non-MIT parts. AC1 also needs `tool/check_sqlite3mc.sh` run on the Windows sqlite3mc.dll (Git Bash or CI), with the evidence recorded. docs/licences.md flag 1 records only the Mac binaries as checked.
  > Blockers: none

  Lead actions: R5 → new AC added to M1.9 in docs/PLAN.md (release script takes the version defines from the tag and fails if missing or different). R1, R2, R3, R7 → developer round 3 (failed review round, so one effort level higher: high). R4 → developer implements the spec (focus moves to the first row once the list loads), so no spec change is needed; if that proves unreliable, it comes back to the PM. R1's two SQLite notices: the developer pins "Kusunga" first and also yields both SQLite notices under the "Kusunga" entry, so they are reachable from the top row; their own alphabetical entries stay. That differs from the spec's wording ("at the top"), so it goes to the PM as a decision with the merge ask. R6 → tester, once the texts land. The Windows DLL check (AC1) → a CI step or the PM's Windows run, to plan with M1.9b/e. The previous developer agent was stopped after its work was committed (it kept re-sending the same report).
- Gates: developer round 3 · tester pass · reviewer block · QA open · PM merge not asked
- Open findings: R1 Medium; R2, R3, R4, R6 Low; R7 cleanup; AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line; R1 SQLite notice placement

## 2026-11-21 — M1.9a About and licences — developer round 2; reviewer started
- Changed: developer report, word for word:

  > Round 2 is done: all four bugs are fixed in one commit, 31aca27 on feat/about-licences (6 commits now). The full ./tool/check.sh passed once, with no overlapping runs: "04:15 +4025 ~11: All tests passed!" Format and analyze are clean. The 11 skips are the existing ones plus the blocked sqlite3mc MIT test; none of the tester's repro skips remain. Nothing is pushed.
  > Branch: feat/about-licences (6 commits; round 2 = 31aca27)
  > Built: no new features, only the fixes below. The skips and the PROBE_BUGS define are removed from the tester's repro tests (build_info_edge_test.dart, about_edge_test.dart, sqlite3mc_extfunc_abuse_test.dart), so they run as normal tests.
  > Tests: 4025 passing, 11 skipped, 0 failing in the full check. Before the fixes, run with --dart-define=PROBE_BUGS=true: 8 repro tests failed: build_info_edge_test.dart: all 5 "odd defines" tests, including "does not become vv0.9.0"; sqlite3mc_extfunc_abuse_test.dart: "a bad binary is still named in a UTF-8 locale" and "a clean binary with invalid UTF-8 passes in a UTF-8 locale"; about_edge_test.dart: "one notice that fails to load does not blank the whole page". After the fixes, test/about, sqlite3mc_extfunc_check_test.dart and sqlite3mc_extfunc_abuse_test.dart: 170 passed, 1 skipped, 0 failed. The skipped one is the blocked sqlite3mc MIT-text test.
  > E2E: n/a — no suite
  > Test hooks: unchanged.
  > Deviations from plan: BuildInfo keeps its constructor named `version:` and `build:`, but `version` and `build` are now getters (they use private constructor fields). A whitespace run inside a version becomes "-" in the source link only.
  > Checklists: ui-build (unchanged from round 1). Other items n/a as before.
  > Risks / unverified: The script ran on the real Mac binaries in both LC_ALL=C and en_US.UTF-8: all 5 files (arm64 and x86_64, dylib and framework) pass with the added marker names. This is a manual run on this machine, not part of the check. The Windows DLL is still unchecked; the added names were not tested against real extensionfunctions code.
  > Personal data touched: none
  > Later lines added: none
  > Spec gaps raised: none
  > Findings: BUG-M19A-5 — fixed (31aca27, the two UTF-8-locale repros). The script's `tr` now runs with LC_ALL=C, and so do its sed and sort. BUG-M19A-1 — fixed (31aca27, the four "odd defines" repros). Version and build are trimmed, and whitespace-only counts as empty. BUG-M19A-2 — fixed (31aca27, the "does not become vv0.9.0" repro). A leading v or V is stripped from the version, so the tag is v<version> once. BUG-M19A-4 — fixed (31aca27, the "one notice that fails to load" repro). registerLicences now loads each notice on its own and leaves out any that fails; the others still show. Tester note (a), discovery — done. No-argument discovery also finds sqlite3mc.dll, not only libsqlite3mc.*, in the hook-cache folder. The script header documents this. The build/ folder was already covered. Tester note (b), extra marker names — done. I added atn2, cot, coth and proper as whole-string matches. I left out the other names (difference, sign, square, reverse, mode, median) because they are common words that could hit a clean binary. The real Mac binaries still pass. Tester note (c), extensionfunctions.c listed in the notice — left unchanged, deliberately. assets/licences/sqlite3mc.txt row 58 is generated from docs/licences.md, which is the source (table row at line 49). The reachability test derives its list from that table. The row describes upstream's bundle list, and it says the part is compiled only with SQLITE_ENABLE_EXTFUNC. It does not claim the part ships in the binary. Decision for the lead: if you want it dropped from the in-app notice because the check proves it is absent, change the docs row and the asset together. I will not do that without your word.
  > Blockers: Same as round 1: the verbatim upstream texts for the SQLite3 Multiple Ciphers MIT licence and each bundled part are not in assets/licences/sqlite3mc.txt. I did not try to fetch them. AC1 and AC7 stay open until someone adds them. Needs the lead or PM, and it blocks any build being handed out. The MIT test is still skipped.
  > How to verify: same steps as the round 1 hand-off, plus: 1. Build with `--dart-define=KUSUNGA_VERSION=v0.9.0 --dart-define=KUSUNGA_BUILD=1`. The About line reads "Kusunga 0.9.0 (build 1)". In a release build, Copy link gives .../tree/v0.9.0 (not vv0.9.0). 2. In Terminal.app (UTF-8 locale), run `./tool/check_sqlite3mc.sh` after a native build. It prints "ok" for every binary and does not report "not a SQLite library".

  Lead: note (c) stays as is — the row describes upstream's bundle and says it is compiled only with SQLITE_ENABLE_EXTFUNC; the check proves it is absent from the shipped binary. Reviewer dispatched (Mode: branch).
- Gates: developer pass (AC1/AC7 blocked) · tester pass (4 bugs fixed) · reviewer in progress · QA open · PM merge not asked
- Open findings: AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — M1.9a About and licences — tester report; developer round 2
- Changed: tester report, word for word:

  > Tester report for M1.9a "About and licences". No production code was changed, nothing was pushed.
  > **Short version:** 3 test commits, 106 new passing tests, 8 more written as open-bug repros and skipped. I found 5 bugs, none high severity. BUG-M19A-5 is the only one a release operator will hit: the sqlite3mc check script gives a false FAIL on the real macOS binary in a normal UTF-8 terminal. The full `check.sh` passes. The MIT-notice test is still skipped for the known blocker.
  > Branch: feat/about-licences (3 test commits: e525f33, 61e05de, dcfc47b, on top of f65ffc6, ace9d66, b78d0fb)
  > Added: 106 passing tests + 8 skipped open-bug repros in: test/about/build_info_edge_test.dart, test/about/about_edge_test.dart, test/about/licence_registry_edge_test.dart, test/ci/sqlite3mc_extfunc_abuse_test.dart
  > E2E tests added: 0 — n/a. No Flutter integration_test or UI-automation tool is chosen yet (Team setup: TBD), and I did not launch Kusunga. The user flows are covered as widget tests (tap, Tab, Enter, Space, Esc, Back).
  > Fail-then-pass: Old code (8614d88): every new test file fails to compile, because lib/about and tool/check_sqlite3mc.sh do not exist there. I confirmed this by moving them aside, then restoring them. More useful proof, one deliberate break each (restored with git checkout; git status clean): check script, unquoted "$1" in strings_of — fails: file-name tests ("sqlite3mc copy.dll", "two  spaces.dll", a root folder with spaces); check script, grep -x removed — fails: "marker names inside longer words pass", "marker with a space or dot around it"; check script, `check "$f" || failed=1` made `&& failed=0` — fails: file-name tests and the several-file tests; check script, Mac framework branch removed from discovery — fails: "finds the Mac framework binary under build/"; BuildInfo.sourceUrl ignores `development` — fails: "development=true version=0.9.0 links plain repo", "never links a tag"; BuildInfo, empty build prints "(build )" — fails: "version set, build empty" in every surface; HistoryService.copyOwn uses Clipboard.setData instead of writeOwn — fails: "both buttons leave history empty and use only writeOwn", plus the copyOwn tests; licences.dart, Esc shortcut removed — fails: 4 Esc tests (320 px, after Tab, focus returns, reopen); licences.dart, package name 'SQLite' renamed — fails: 3 registry tests; sqlite3mc.txt, miniz block deleted — fails: 3 per-part tests; sqlite3mc.txt, "Licence: CC0-1.0" changed to MIT — fails: "each part names the licences docs/licences.md gives it". All pass on the branch.
  > Regression locks (pass on old and new by design; all fail on a mutation above): source-link tag rule table: release links tag v<version>, debug/profile links the plain repo. Could break if someone changes how the build mode is read. Licence registry exact-bytes and per-part checks: could break if docs/licences.md or the notice text drift apart. "three notices above packages Flutter collects": passes only because pub package names are lower case and "Kusunga", "SQLite3…" and "SQLite" start with capitals. LicensePage sorts by name, so this holds by luck, not by design.
  > Bugs found (all repro tests are skipped; run them with `flutter test --dart-define=PROBE_BUGS=true <file>`):
  > BUG-M19A-5 (medium) tool/check_sqlite3mc.sh fails the real macOS binary in a UTF-8 locale. `tr '\0' '\n'` stops with "Illegal byte sequence" on non-UTF-8 bytes. Real result: LC_ALL=en_US.UTF-8 on build/native_assets/macos/libsqlite3mc.dylib gives "FAIL … not a SQLite library"; LC_ALL=C gives ok. It fails closed, so it never passes a bad binary, but a release operator in Terminal.app or iTerm gets a false FAIL with a misleading reason. Fix: `LC_ALL=C tr` in strings_of. Repro: sqlite3mc_extfunc_abuse_test.dart "a bad binary is still named in a UTF-8 locale" and "a clean binary with invalid UTF-8 passes in a UTF-8 locale".
  > BUG-M19A-1 (low) BuildInfo does not trim --dart-define values. A whitespace-only version shows "Kusunga     (build 1)" and links tree/v%20…. " 0.9.0 " gives a link with spaces. A whitespace-only build shows "(build   )". A version with a newline gives a link with a newline. Repro: build_info_edge_test.dart, group "odd defines", 4 tests.
  > BUG-M19A-2 (low) KUSUNGA_VERSION=v0.9.0 gives the link /tree/vv0.9.0. Repro: build_info_edge_test.dart "does not become vv0.9.0".
  > BUG-M19A-4 (low) registerLicences has no per-asset error handling. If one asset fails to load, the LicensePage future errors and, in my test, even "Kusunga" (yielded before the failing asset) does not show. Unlikely in a real build because the assets are bundled. Repro: about_edge_test.dart "one notice that fails to load does not blank the whole page".
  > BUG-M19A-3 was withdrawn: the order probe passed (see Regression locks).
  > Abuse cases covered: 41/41 listed in the brief (script abuse and odd-define probes): file names with spaces, globs, quotes, $, ;, backslash, unicode, leading dash, newline; symlinks: to clean, to bad, dangling, to a folder; folder as argument, empty argument, Windows-style and Git Bash-style paths; unreadable file (chmod 000); marker names as substrings, at the first or last byte with no NUL, newline-separated, invalid UTF-8 in C/POSIX/UTF-8 locales; 16 MB sparse file, 12 MB single line, 200,000 strings; several files with a good one before or after a bad one; default discovery: Mac framework, Windows DLL, hooks_runner, a root folder with spaces, other file names ignored; LF-only script, no bash 4 features; wide UTF-16 marker is a documented limit (the test passes by design).
  > UI states covered: 14/14 matrix rows that can be tested without a device: default, development build with caption, version unknown, build only, version without build, unknown+development; copy success and failure for both buttons, including a thrown platform error and success after failure; keyboard (Enter, Space, Tab order, toast does not take focus); 320 px at 200% text, 360 px, ≥600 px, very long version string, dark theme; licence page at 320, 600 and 900 px, picking a notice and Back, Esc at every depth, Esc returns focus to View licences, reopen three times; the section sits after Your data. Not covered: hover colour, focus ring, contrast and screen-reader behaviour (see gaps).
  > Gaps not covered: the MIT notice (AC7) and the verbatim upstream texts: the known blocker, existing test still skipped; the real NOTICES.Z collection: only the three hand-added entries are tested, not Flutter's own package notices; sqlite3mc binaries for Windows, iOS and Android: not available here. Only the two Mac dylibs in .dart_tool and build/native_assets passed the script; hover, focus ring, contrast of caption and textMuted, VoiceOver and Narrator announcements, reduced motion: need the running app or a device; the marker list: extensionfunctions.c also registers atn2, coth, cot, proper and a few others. They are not checked, but they would sit beside padl and stdev in the same table, so detection still looks sound. Any extra name widens coverage; Windows discovery: no-argument mode looks for libsqlite3mc.* under .dart_tool, but the Windows hook may name the file sqlite3mc.dll with no "lib" prefix. Unverified; pass the DLL explicitly or confirm the name on a Windows build; the notice text lists extensionfunctions.c as a bundled part (copied from docs/licences.md) although the check proves it is absent. Not a defect, but worth the developer's attention.
  > Does the script run on stock macOS bash 3.2? Yes. This machine's /bin/bash is 3.2.57 and every script test runs under it. A test also guards against bash 4 syntax and CR line endings.
  > Production code changed: none
  > Suite: 4017 passing / 0 failing / 19 skipped (was 3911 passing / 11 skipped). The final ./tool/check.sh finished with rc=0 and "All tests passed!"; format and analyze were clean. pgrep for flutter_tester was empty before each run; I ran one check at a time.
  > Blockers: none new. The known one (verbatim sqlite3mc licence texts missing, AC7 test skipped) stays with the developer or PM.
  > Notes for the lead: The 8 skipped tests are the repros for BUG-M19A-1, -2, -4 and -5. After the developer fixes a bug, remove its `skip` so it becomes a normal test. In build_info_edge_test.dart and sqlite3mc_extfunc_abuse_test.dart the skip is tied to `_probeBugs`; in about_edge_test.dart it is `skip: !_probeBugs`. I read the developer's deviations (Navigator.push with an Esc shortcut, initial focus on the page, whole-line copy, "Kusunga 0.9.0" without a build, own copies via writeOwn) as written. They behave as the developer described. Own copies are not added to history. I covered this two ways: no `Clipboard.setData` call and an empty `service.items` after both buttons, and `writeOwn` is called with the exact text.

  Lead: BUG-M19A-1, -2, -4, -5 and the tester's notes (Windows DLL discovery name, extra marker names, extensionfunctions.c listed as a bundled part) go back to the developer on feat/about-licences.
- Gates: developer round 2 · tester pass with 4 bugs · reviewer, QA open · PM merge not asked
- Open findings: BUG-M19A-5 medium; BUG-M19A-1, -2, -4 low; AC1/AC7 notice texts (blocked)
- Decisions: none new
- Blockers: Developer notice texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — CI run 4 green; M1.9a About and licences — developer hand-off (blocked on notice texts)
- Changed: CI run 4 (44895275732) on d3a8e6c: macos success, windows success (one check after completion). Windows CI green: developer, tester, reviewer (approve) and CI pass; QA's real-app export check waits for the PM to unlock the Mac. M1.9a: lead created worktree feat/about-licences from main 8614d88 and dispatched the developer (sonnet). Developer report, word for word:

  > M1.9a is built and committed but not complete. The SQLite3 Multiple Ciphers notice has no verbatim upstream licence text, so AC7 and half of AC1 are open until someone supplies it. See Blockers.
  > Branch: feat/about-licences (3 commits on 8614d88: f65ffc6, ace9d66, b78d0fb). Worktree: /private/tmp/claude-501/-Users-williamnasoni-Developer-Personal-kusunga/bdcaa771-52a1-4433-b5f6-1f64c65a45f5/scratchpad/m19a-wt. Not pushed.
  > Built:
  > - About section at the bottom of Settings, after "Your data", per the UI spec. Content: version line, copyright, GPL sentence, selectable source link, development-build caption, Copy version, Copy link, View licences. Layout: buttons sit at the end of their lines at 600 px and wider; below 600 px they sit under their text. Code: lib/about/build_info.dart, about_section.dart, licences.dart.
  > - Licence page and registry. The page is Flutter's LicensePage with the spec's name, version and legalese. Esc and Back close it; Back returns focus to View licences. registerLicences() is called in main.dart and registers "Kusunga" (the full GPL text from LICENSE, declared as an asset), "SQLite3 Multiple Ciphers" (assets/licences/sqlite3mc.txt) and "SQLite" (the public-domain blessing, assets/licences/sqlite.txt).
  > - tool/check_sqlite3mc.sh: fails if a sqlite3mc binary has extensionfunctions.c function names (padl, padr, padc, strfilter, charindex, leftstr, rightstr, stdev, variance, replicate, lower_quartile, upper_quartile, RegisterExtensionFunctions). Short names must be a whole string, so "padlock" does not trip it. It also fails on a missing file, an empty file, a non-SQLite file, or no binary found at all. I ran it on the five Mac binaries in the main checkout (x86_64 and arm64, framework and dylib): all clean. It is a separate script, NOT wired into check.sh, because the binaries only exist after a native build. The test that exercises it with fixtures runs in check.sh. A second test checks any binaries present on the machine and skips if none. Windows: run `bash tool/check_sqlite3mc.sh build/windows/x64/runner/Release/sqlite3mc.dll` in Git Bash. It needs only bash, tr and grep. This is documented in the script header and in docs/licences.md flag 1.
  > - Version source: --dart-define KUSUNGA_VERSION and KUSUNGA_BUILD, chosen over reading the platform bundle because it needs no native code on either platform. The pubspec is untouched (it still says 1.0.0+1). Release command: `flutter build macos --release --dart-define=KUSUNGA_VERSION=0.9.0 --dart-define=KUSUNGA_BUILD=1`. Without the defines the line reads "Kusunga (version unknown)". A debug or profile build adds " — development build" and shows the plain repo link plus the "Development build" caption.
  > Tests: 3911 passing, 11 skipped, 0 failing in the full ./tool/check.sh (format and analyze clean). New tests: about/build_info_test.dart, about_section_test.dart, licence_registry_test.dart, ci/sqlite3mc_extfunc_check_test.dart. They cover: every state in the matrix that a widget test can reach (default, development build, version unknown, copy success, copy failure and copy throw); the licences page, Esc, and focus return; semantic labels and tab order; 24 px targets, the 600 / 360 / 320 px layouts, 360 px at 200% text, and dark theme with no overflow; the registry (GPL equals LICENSE, the blessing, all 18 bundled parts of the docs/licences.md table by name, and the spec's named parts); the script (every marker name, whole-word rule, missing, empty and non-SQLite files, several files, no binary found).
  > First failing runs, before the code: build_info_test: "Undefined name 'BuildInfo'". about_section_test: compile error because SettingsScreen had no `buildInfo` parameter. licence_registry_test: (setUpAll) failure because the assets were missing. sqlite3mc_extfunc_check_test: 19 failures, because the script did not exist.
  > Other runs and checks: While writing the script, the first version failed on the real Mac binary (the sanity string and a pipefail/grep -q problem). I fixed both, and the script now passes on the real binaries. I accidentally ran check.sh twice at the same time (one from a timed-out background run). Both runs finished with all tests passed, and the worktree is clean.
  > E2E: n/a — no suite (desktop UI automation is TBD per CLAUDE.md). Nothing launched.
  > Test hooks: Semantics identifiers about-copy-version, about-copy-link, about-view-licences. Accessible names: "Copy version 0.9.0 build 1" (version and build are filled in; plain "Copy version" if unknown), "Copy source code link", "View licences". "About" is a header via SectionHeading.
  > Deviations from plan: showLicensePage is replaced by Navigator.push of the same LicensePage wrapped in an Esc shortcut. showLicensePage has no Esc handling, and the spec asks for Esc. The page content is identical. Initial focus on the licences page is the page itself, not the first row; Tab moves into the rows. Copy version copies the whole version line, including " — development build" for a debug build, so a report from one says so. Spec only says unknown version copies its text. Version set but build empty shows "Kusunga 0.9.0" with no build part. The spec does not cover this case. Own-copy rule confirmed: Kusunga's own copies go through ClipboardSource.writeOwn (PM decision D1). The native watcher skips that change, so the copy is NOT added to history. I added HistoryService.copyOwn(text), which calls writeOwn and returns false on failure or throw. No new rule. pubspec.yaml gained asset entries (LICENSE and assets/licences/), not a version change. docs/licences.md flag 1 now points to the script and records the 2026-11-21 Mac result.
  > Checklists: ui-build (applied). data-and-apis is n/a (no store, API or personal data). Other n/a items: Disabled, Loading, Empty, Permission denied and Offline states have nothing to show (spec marks them n/a); Hover and the real-font visuals are not reachable in a widget test and are left to QA; the Windows DLL check is not run here (no Windows binary).
  > Risks / unverified: The Dart and Flutter package notices come from Flutter's own NOTICES collection. That is not present under flutter test, so only QA in a real build can confirm them. Real Windows DLL not checked. No positive control on real extensionfunctions code, only fixtures with the marker names. Visual look, contrast and hover not checked by eye. Navigator.push focus return is covered by a widget test only.
  > Personal data touched: none (the Copy buttons put only the version line or the link on the clipboard).
  > Later lines added: none
  > Spec gaps raised: none
  > Findings: none (first pass)
  > Blockers: WHAT: assets/licences/sqlite3mc.txt currently holds only an index of the 18 bundled parts, each with its licence name, taken from docs/licences.md. It has none of the verbatim licence texts: no MIT text with its copyright line, and no per-part notices (BSD-3 SHA-2, CC0 fastpbkdf2, Apache-2.0 / CC0 Argon2 and so on). I tried to fetch the upstream v2.5.0 LICENSE and src/filelist.md from raw.githubusercontent.com; the permission system denied it. There is no local copy, and I will not write the copyright lines from memory. AC1 (every shipped notice) and AC7 (the MIT notice on the licence page) are NOT met. The test "SQLite3 Multiple Ciphers: the MIT notice, with its copyright line" is written but skipped, with the reason in the skip text. The beta must not ship until this is fixed. WHO: lead or PM. Either allow a plain GET of the public upstream files, or supply them. WHAT I NEED: verbatim texts from utelle/SQLite3MultipleCiphers at tag v2.5.0 (LICENSE and the licence headers of the bundled parts), appended to assets/licences/sqlite3mc.txt. Then remove the `skip:` on that test. IMPACT: AC1 and AC7 stay open, which blocks M1.9a being ticked and any build handed to anyone.
  > How to verify: (8 steps for QA in the qa profile; kept in the hand-off and passed to QA unchanged.)

  Lead: (1) the developer was denied a fetch of the upstream sqlite3mc licence files; the lead does not fetch them in its place (no routing around a denial) — goes to the PM. (2) Rule deviation: two ./tool/check.sh runs overlapped (one from a timed-out background run); both passed; the developer is reminded. (3) The tester starts on feat/about-licences now; the skipped MIT-notice test stays skipped until the texts arrive.
- Gates (Windows CI green): developer pass · tester pass · reviewer approve · CI run 4 pass · QA blocked (screen locked) · PM merge not asked
- Gates (M1.9a): developer handed off with a blocker · tester in progress · reviewer, QA open · PM merge not asked
- Open findings: M1.9a AC1 (notices) and AC7 (MIT notice) open
- Decisions: none new
- Blockers: Developer M1.9a — verbatim sqlite3mc v2.5.0 licence texts (fetch denied) · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac; allow the fetch or supply the texts; DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — QA blocked (screen locked)
- Changed: QA report, word for word:

  > Milestone: Windows CI green (docs/qa/m1.md, section "Windows CI green (2026-11-21)") — 0/4 criteria confirmed by QA; 3 pending the lead on CI run 4, 1 real-app check NOT RUN — Date: 2026-11-21 — Environment: macOS 27.2, Flutter 3.44.6 / Dart 3.12.2, branch fix/windows-ci at d3a8e6c, debug macOS build (signing: Apple Development (redacted), CDHash 8466fdf5...), qa profile
  > Automated: AC1, AC2, AC4 are CI-only (automated). AC3 rests on unit tests that I did not re-run. Manual: the real-app export check (the BUG-C1 behaviour change) — it needs the real UI and a native save panel, and it did not run (see Blockers).
  > Fail: none observed. Nothing was exercised.
  > Spec gaps: none
  > Re-verified: none. Run 2 (44631551718, green on both jobs on 11c85b7) is recorded as prior evidence from your brief. QA did not re-run it.
  > Needs PM: 1. Unlock the Mac and keep the screen awake and unlocked, then tell the lead so QA can re-run the export check. This is a real needs-PM item: the macOS session is locked and QA cannot enter a password. Nothing else needs the PM.
  > Not observed: the real-app export (snippets only and with history ticked; to a new file and over an existing file; valid JSON; old content replaced; no `.kusunga-export-*` temp file left; "The file isn't encrypted" note). The screen is locked, so QA could not see or drive the app. Result of CI run 4: `gh run view 44895275732` read once showed it still in progress (macos and windows jobs running), so AC1, AC2 and AC4 are marked "pending — lead confirms".
  > Accessibility: n/a — no UI change; the only behaviour change is the export write path.
  > Privacy: n/a — no new data, storage or network use. The "file isn't encrypted" note was not re-checked (see above).
  > Claims: n/a
  > Evidence: docs/qa/m1.md (section "Windows CI green (2026-11-21)"), committed on fix/windows-ci as 275fd20, not pushed; screens: docs/qa/m1/screens/ (0 new files); videos: none — no flow ran.
  > PM check steps: n/a — no PM steps beyond unlocking the Mac.
  > Blockers: The macOS session screen is locked (CGSSessionScreenIsLocked = 1). Full-screen `screencapture` returned an all-black image, `screencapture -l` of the window failed, and the app exposed no AX window content. Who can unblock: the PM (unlock the Mac and keep it awake). What I need: an unlocked, awake screen, then a re-dispatch of QA for the real-app export check (about 15 minutes). Impact: the BUG-C1 real-flow check stays NOT RUN; CI and unit-test evidence is unaffected. I did not try to unlock the Mac or change any setting.
  > Clean-up: the only Kusunga instance I started (pid 60446, qa profile) was quit by pid. No flutter_tester or other process of mine is running. The qa-export folder in the scratchpad is empty. The default profile was never used. The helper tools I built (AX reader) are in the scratchpad and were not committed.

  Lead: CI run 4 still in progress at a second single check. QA re-runs the real-app export check once the PM unlocks the Mac.
- Gates: developer pass · tester pass · reviewer approve (if CI run 4 green) · QA blocked (real-app export not run; CI pending) · PM merge not asked
- Open findings: none
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA screen locked (PM) · Marketer none · Lead none · PM — unlock the Mac for QA; DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — reviewer re-check: approve; QA started
- Changed: reviewer re-check report, word for word:

  > Mode: branch
  > Branch: fix/windows-ci (re-check of 1be521f..d3a8e6c: d9dcd43, 0f7a103, 981182d, 1eee3b6, d3a8e6c) — Verdict: approve. All five findings are fixed and none is open. This holds only if CI run 4 on d3a8e6c is green. I did not poll it, and I could not run check.sh under the brief.
  > Checks: ./tool/check.sh was not run by me, as briefed. The developer reports "+3891 ~10: All tests passed!". My own checks, with pgrep -fl flutter_tester empty first: `flutter analyze` on the 4 changed Dart files: "No issues found!". The parameter annotation raises no invalid_annotation_target. `dart format --set-exit-if-changed` on those files: 0 changed. Focused `flutter test` on file_error_log_handle, key_delete_timing, test/support/, export_temp_name_edge and your_data_service: "+84 ~1: All tests passed!". The F5 test run alone (--plain-name 'addCloseTearDown'): pass. Both rotation log tests ('rotations in the middle' and 'BUG-T1'): 3 runs each, all pass, no flakes.
  > Code review: 5 findings (5 fixed, 0 open)
  > Design review: 0 findings (0 fixed, 0 open)
  > Security review: 1 finding — S1, Low (no CVSS score: band + basis — local only; the attacker must already be able to write to the chosen export folder, list the random name and win a race; the worst result is an empty new file, with no export bytes and no existing file changed). The Later line now covers it; see F4.
  > Privacy review: no issues. The re-check changes no data, store, log or integration. n/a for minimisation, retention, consent and logs: none of them are touched.
  > Later lines: ok. The BUG-C1 residual line was changed in 0f7a103. Format: right. Trigger: measurable ("≥ 1 report of a stray empty file next to an export"). Never-deferred list: not on it. It is hardening against a local attacker who can already write to the folder, and no existing user data can change. It now names both gaps: between the plain-file check and the open (every OS), and between the nothing-there check and CREATE_NEW (Windows). Added by reviewer: none.
  > Findings (most severe first): none open. Earlier findings F1–F5 are listed below.
  > Fix outcomes:
  > - F1 — fixed (981182d), test/log/file_error_log_handle_test.dart:284-307. `expect(parsed, isNotEmpty)` was added, so a regression that garbles every line now fails. In the oneAfterTheOther run, every kept line must match the anchored whole-line pattern, and the storeUnreadable lines must run with no gap to 2999. Neither check depends on timing: the writers don't overlap, and the single-writer rotation test at :27 already shows that the kept lines are contiguous. Old-code run: the developer reports a mutation run that shows the test now catches the problem. I did not repeat it.
  > - F2 — fixed (1eee3b6), test/data/key_delete_timing_test.dart:299-303. `timers.where((d) => d > _t)` must be empty, so any added wait longer than one key time-out fails. The developer reports the mutation run.
  > - F3 — fixed (d9dcd43), lib/data/your_data_service.dart:70. `@visibleForTesting` is on `createTemp`, and analyze is clean. Production still can't reach the seam: the only caller is the `ExportWriter` tear-off.
  > - F4 — fixed (0f7a103), docs/PLAN.md:182. The Later line names both gaps, including the Windows CREATE_NEW gap.
  > - F5 — fixed (d3a8e6c), test/support/close_service_real_db_test.dart:70-91. The check moved into the group tearDown, and the order-dependent test was removed. It passes when run alone. On Windows the test is skipped, and so is its tearDown. The developer reports a mutation run showing it fails without the helper.
  > Risk accepted by PM: none needed. For reference, these PM decisions are in docs/status.md: 2026-11-19 W1 A / W2 A / W3 A ("Yes, as recommended"), and BUG-L5 "PM chose to skip" (2026-11-06).
  > Open items: none. Before merging, CI run 4 on d3a8e6c must be green.
  > Blockers: none.
  > Process note: closed. The lead confirmed the tester and developer round 3 status entries are committed on local main, not on this branch.

  CI run 4 (44895275732) on d3a8e6c in progress at one check. Lead dispatched QA (qa profile only) for the export change.
- Gates: developer pass · tester pass · reviewer approve (if CI run 4 green) · QA in progress · PM merge not asked
- Open findings: none
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — developer round 4 (F1–F5 fixed); pushed; reviewer re-check
- Changed: developer (opus) report, word for word (the "How to verify" steps are in the agent hand-off and repeat the evidence):

  > All five findings are fixed in five commits on fix/windows-ci (HEAD d3a8e6c, not pushed). ./tool/check.sh passes: 3,891 tests pass, 10 skipped. Each strengthened test (F1, F2, F5) fails on a mutation that the test at HEAD 1be521f let through; every mutation was reverted and the tree is clean.
  > Branch: fix/windows-ci (21 commits ahead of main; this round added 5: d9dcd43, 0f7a103, 981182d, 1eee3b6, d3a8e6c)
  > Built:
  > - F1: the rotating-writers log test now fails when no whole line is kept. In the one-after-the-other run it also checks that every kept line is whole and that the storeUnreadable lines end at 2999 with no gaps.
  > - F2: the memory-only erase test fails if any timer is longer than one key time-out (`timers.where((d) => d > _t)` must be empty).
  > - F3: `@visibleForTesting` on the `createTemp` parameter of `writeExportFile`, imported from `package:flutter/foundation.dart`. meta 1.18.0 allows this annotation on parameters.
  > - F4: the BUG-C1 residual Later line now names two gaps. The first is between the plain-file check and the open (every OS). The second is on Windows only: between the nothing-there check and the exclusive create, because CREATE_NEW follows a link. No code change.
  > - F5: the real-database close is now checked in the group's own tearDown, as close_service_test.dart does. The order-dependent "(checked after the one above)" test is removed.
  > Tests: check.sh result line: `04:12 +3891 ~10: All tests passed!` (exit 0; format "Formatted 296 files (0 changed)"; analyze "No issues found!"). The test count went down by 1 because F5's test that depended on order is gone. Runs that show each test catching its problem:
  > - F1, mutation A (every log line garbled: `\n` changed to `x\n` in lib/log/app_log.dart:158) — New test fails in both runs: "whole 0 of 28 … Expected: non-empty Actual: [] no whole line kept". The other run says the same with "whole 0 of 509". Old test at HEAD: "whole 0 of 45 … whole 0 of 508 … All tests passed!"
  > - F1, mutation B (the line that triggers a rotation is dropped: `return;` after renameSync) — New BUG-T1 test fails: "Which: at location [409] is <2616> instead of <2615> … storeUnreadable lines with a gap". Old test: "All tests passed!"
  > - F2, mutation (a 2 s `Future.delayed` after `_deleteKey` in lib/data/data_eraser.dart) — New test fails: "Expected: empty Actual: WhereIterable<Duration>:[Duration:0:00:02.000000] no wait longer than one time-out". Old test: "00:02 +1: All tests passed!"
  > - F5, before the fix: `flutter test test/support/close_service_real_db_test.dart --plain-name '(checked after the one above)'` gave "Expected: ['closed'] Actual: [] … Some tests failed."
  > - F5, after the fix: `--plain-name 'addCloseTearDown'` run alone: "+1: All tests passed!". The whole file: "+5: All tests passed!". Mutation (the helper only disposes, in test/support/close_service.dart): "Expected: false Actual: <true> open at folder deletion … Some tests failed."
  > - F3: a scratch file under lib/ that passed `createTemp:` gave `warning • The member 'createTemp' can only be used within 'package:kusunga/data/your_data_service.dart' or a test • invalid_use_of_visible_for_testing_member`. The file was removed, and the real files analyse clean.
  > E2E: n/a — no suite (end-to-end tools are TBD in Team setup)
  > Test hooks: n/a — no UI
  > Deviations from plan: Two small additions beyond the brief's wording. For F1 I used two mutations: garbled lines, plus a dropped line so the new no-gap check is also shown failing. For F5 I also ran a helper mutation to show that the tearDown check fails when the database is left open. All mutations were reverted (`git status` is clean).
  > Checklists: none — n/a items: data-and-apis and ui-build both n/a. This round is test hardening, one annotation and one plan line, with no new store, API or screen.
  > Risks / unverified: Windows not run locally. The F1 checks for the oneAfterTheOther run assume the second writer starts after the first has finished, which `await` guarantees. They also assume rotation keeps the second writer's newest lines with no gaps, which holds by design. On Windows CI, F5's tearDown check is skipped with the group's tests (noLsof).
  > Personal data touched: none. The export write path only gained an analyzer annotation; its behaviour is unchanged.
  > Later lines added: none new. The existing BUG-C1 residual line in docs/PLAN.md was reworded for F4.
  > Spec gaps raised: none
  > Findings: F1 — fixed (981182d, test/log/file_error_log_handle_test.dart rotatingWriters) | F2 — fixed (1eee3b6, test/data/key_delete_timing_test.dart "memory only: a hanging delete…") | F3 — fixed (d9dcd43, analyzer invalid_use_of_visible_for_testing_member shown on a scratch caller) | F4 — fixed (0f7a103, docs/PLAN.md Later line "BUG-C1 residual") | F5 — fixed (d3a8e6c, test/support/close_service_real_db_test.dart group "tear-down order")
  > Blockers: none

  Lead pushed 1be521f..d3a8e6c to fix/windows-ci (CI run 4) and sent the reviewer the re-check.
- Gates: developer pass · tester pass · reviewer re-check in progress · QA open · PM merge not asked
- Open findings: F1–F5 fixed, waiting for re-check
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — reviewer: approve with notes (F1–F5); developer round 4
- Changed: reviewer (opus, Mode: branch) report, word for word:

  > Mode: branch
  > Branch: fix/windows-ci (16 item commits, 00bd126..1be521f; base 7e9baf5 = origin/main) — Verdict: approve with notes. This depends on CI run 3 on 1be521f going green: I can't confirm the full check myself, and I did not poll the run.
  > Checks: ./tool/check.sh was not run, as briefed. I ran focused `flutter test` with no other flutter_tester running (pgrep was empty) — pass — "+102 ~1: All tests passed!" Files: export_temp_name_edge, your_data_service, test/support/*, file_error_log_handle, key_delete_timing, line_endings, line_endings_checkout, build_config, login_item_guards. Also `xcrun swiftc -typecheck -Xfrontend -warn-long-expression-type-checking=100 macos/Runner/LoginItemCore.swift` gave no warnings (1.5 s). CI run 2 on 11c85b7 was green (lead); run 3 is pending.
  > Code review: 5 findings (0 fixed, 5 open; all Low or cleanup). I did this review by hand at high depth. I did not run the code-review skill.
  > Design review: 0 findings. The work matches docs/design/windows-ci-green.md and W1 A / W2 A / W3 A. One small difference is an improvement: the design said `if: always()`, and the code uses `if: ${{ !cancelled() }}`. The design's "each writer keeps at least one line" was dropped for BUG-T1, and the PLAN note records it.
  > Security review: 1 finding — S1, Low (no CVSS score; band + basis: local only; the attacker must already be able to write to the export folder the user picked and must win a race; worst case is an empty new file, with no export bytes and no existing file changed). It is a wording gap in the BUG-C1 residual Later line; see F4. The security-review skill found no high-confidence vulnerability.
  > Privacy review: no issues.
  > - Export: nothing is written outside the target path. Bytes are never written through a link. The temp-route failure removes only a plain temp file and leaves the user's existing export as it was. I traced lib/data/your_data_service.dart:65-116.
  > - The write-in-place fallback empties the existing export and removes it if the write fails. That is the approved R3 design and is not changed here. In production it is now reached only if something is already at a 128-bit random name.
  > - n/a: data minimisation, retention and consent (no new data, store or integration).
  > - n/a: logs (no new log lines).
  > - n/a: CI secrets (permissions: contents read; no secrets; no untrusted input reaches a shell).
  > Later lines: ok. One line was added: "Export temp file opened with no gap at all … (BUG-C1 residual) … — trigger: … ≥ 1 report of a stray empty file next to an export — noted 2026-11-21 by developer". The format is right and the trigger is measurable. It is not on the never-deferred list: it is hardening against a local attacker who can already write to the folder, and no existing user data can change. The BUG-T1 text is a note under BUG-L5, not a Later line. Added by reviewer: none.
  > Findings (most severe first):
  > - F1 — Low (test strength; a false green is possible) — test/log/file_error_log_handle_test.dart:251-305 (rotatingWriters). Failure scenario: a writer or rotation regression garbles every line when two writers rotate. `parsed` is then empty, the order loop checks nothing, and only `kept isNotEmpty` runs, so the test passes. Mitigation: single-writer and BUG-L4 whole-line tests exist, but several of them skip on Windows. Expected fix: add `expect(parsed, isNotEmpty)`; this does not depend on timing. In the oneAfterTheOther run the writers never overlap, so also assert that every kept line matches `wholeLine` and that the storeUnreadable lines end at 2999 with no gaps. That gives the BUG-T1 test real content. My judgement for the lead (the design note asked for it): dropping the 90% floor is acceptable, because BUG-L5 is a PM-skipped product item. The per-writer order check is not flaky: a whole line can't take a wrong number under the anchored regex, and B's line is always longer than A's.
  > - F2 — Low (test strength) — test/data/key_delete_timing_test.dart:288-298 (memory-only test). Failure scenario: the old wall-clock upper bound (< 3 × _t) is gone. A regression that adds a fixed wait of another length under 4 s, such as a 2 s sleep, still gives `_timeOuts == 1` and passes. Expected fix: also assert that no recorded timer is longer than _t, for example `expect(timers.where((d) => d > _t), isEmpty)`, or keep a generous upper bound on the total time.
  > - F3 — Low (cleanup) — lib/data/your_data_service.dart:69 (`createTemp` seam). It can't be misused in production. The only production caller is the `ExportWriter` tear-off at :280, whose type is (path, bytes) and can't pass the seam. Whatever the seam makes, `_writeInto` (:104-107) refuses to open anything but a plain file. Expected fix: mark it `@visibleForTesting`, so a future caller doesn't pass it.
  > - F4 — Low (S1, Later-line wording) — docs/PLAN.md:182, with your_data_service.dart:77-82. On Windows, the exclusive create (CREATE_NEW) follows a link. A link swapped in between the `typeSync` pre-check at :77 and the create at :82 can therefore make an empty file where it points, before `_writeInto`'s checks run. The Later line names only the gap between the check and the open. The consequence is the same as the gap already recorded (an empty file only). Expected fix: reword the Later line to cover the gap before the create on Windows too. No code change.
  > - F5 — cleanup — test/support/close_service_real_db_test.dart:80-95. The test "(checked after the one above)" depends on test order. Run alone with --plain-name, `h` is not set and `seen` is empty, so it fails. Expected fix: check the result in the group's tearDown itself, as close_service_test.dart:52-55 does.
  > - Note, not a finding: tool/test_mac_login_item.sh:28-35 keeps only lines containing 'type-check', so other swiftc errors are hidden there. The compile step below it still catches them, and the script is not run in CI. Fine as is.
  > Verified:
  > - BUG-C1 regression test. With the new export_temp_name_edge_test.dart on 6955c1d (before the fix), "a dangling link wins the race" fails: Expected notFound, Actual file. It passes on 1be521f. The test was written first and fails without the fix. I used a temp worktree in the scratchpad and removed it afterwards.
  > - The group C test (your_data_service_test.dart:223) can only pass with the pre-check: without it, the no-op createTemp leads `_writeInto` to refuse, and the export fails.
  > - Swift: `reached(_:on:)` has the same conditions as the old closure (on: enabled or requiresApproval; off: notRegistered), used before and after register/unregister. Same behaviour.
  > - CI: `!cancelled()` runs the build after a test failure, and the job still fails. build_config_test guards against `continue-on-error`.
  > - Group E: own_marker_edge's false green is fixed with p.basename.
  > - The tear-down order of closeAndDispose is confirmed by close_service_test and the lsof test.
  > Fix outcomes: none yet.
  > Risk accepted by PM: none needed. The relevant PM decisions are in docs/status.md: 2026-11-19 W1 A / W2 A / W3 A ("Yes, as recommended"), and BUG-L5 "PM chose to skip" (2026-11-06, Later line).
  > Open items: F1-F5. All are Low or cleanup, so none blocks the merge (approve with notes). F1 and F2 are cheap test additions; I recommend doing them on this branch before the PR merges.
  > Blockers: none.
  > Process note for the lead: you pointed me to the tester report and developer round 3 entries, but they are not in docs/status.md. The newest entry is "2026-11-19 — Windows CI green — deck approved; build started", and the working tree is clean. Please log them, plus this review, before the merge.

  Lead: the process note is because status entries are committed on main (local, unpushed) and the reviewer read the branch; both entries are on main (4be4a6c, and the round 3 entry). F1–F5 are all cheap and go to the developer on this branch now (F4 is a wording change in the BUG-C1 residual Later line, which still goes to the PM with the merge ask). CI run 3 on 1be521f was pending at one check; it will be superseded by the round 4 push.
- Gates: developer round 4 (F1–F5) · tester pass · reviewer approve with notes (re-check after round 4) · QA open · PM merge not asked
- Open findings: F1 Low, F2 Low, F3 Low, F4 Low (S1), F5 cleanup
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — developer round 3 (BUG-T1, BUG-C1); pushed for CI run 3
- Changed: developer (opus) report, word for word:

  > Branch: fix/windows-ci (3 new commits on a7f30a9, not pushed)
  > - 6955c1d test(log): no per-writer floor when one writer finishes first (BUG-T1)
  > - 1b3485e fix(export): never open the temp name unless it is a plain file (BUG-C1)
  > - 1be521f docs(plan): BUG-T1 note on the log garble line, Later line for the BUG-C1 residual gap
  > Built:
  > - BUG-T1 (test only, test/log/file_error_log_handle_test.dart): the two writers are now a helper with a `oneAfterTheOther` option. The rotating check runs in two tests: the existing concurrent one, and a new deterministic one called "BUG-T1: the same two writers when one finishes before the other starts...". I removed the "each writer keeps at least one whole line" assertion. "kept is not empty" stays, and the order check now runs only on the lines a writer actually kept. Whole lines are parsed with a stricter pattern anchored at both ends: `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3,6}Z (flushFailed|storeUnreadable) (0|[1-9]\d{0,3})$`, and the number must also be below 3000. So a line BUG-L5 overwrote, with extra digits on the end, no longer matches. Before, the check used `\d+$` with `split(' ').last`.
  > - BUG-C1 (lib/data/your_data_service.dart `_writeInto`): before the open, it now checks with `typeSync(followLinks: false)` that the temp name is a plain file. If it is not, it throws a FileSystemException. The existing link check after the open is kept. Why this approach: every dart:io write mode (write, append, writeOnly, writeOnlyAppend) creates a missing file, and dart:io has no O_NOFOLLOW. There is no open mode that refuses to create through a link. Checking before the open is the only fix possible without native code. On a refusal, the export throws, the link is left alone (`_removeQuietly` only removes plain files), and the user's existing export is unchanged. This is the same as the "link to a file wins the race" case.
  > - I removed the skip on the BUG-C1 repro in test/data/export_temp_name_edge_test.dart. It is now `skip: links`, so it is skipped only on Windows without symlink rights, as its neighbouring tests are.
  > Tests: ./tool/check.sh exited 0. Its last line: `04:33 +3892 ~10: All tests passed!`. dart format and flutter analyze were clean. `pgrep -fl flutter_tester` was empty before and after.
  > - Export suites: test/data/export_erase_edge_test.dart, export_format_test.dart, export_temp_name_edge_test.dart, your_data_service_test.dart and recheck_fixes_test.dart: +192, all passed. recheck_fixes_test.dart on its own: +35, all passed.
  > - BUG-T1, first failing run (the new deterministic test, before the assertion change): `LOG rotation x2 writers: live 396 lines, .1 409 lines, whole 805 of 805` / `Expected: non-empty  Actual: []  flushFailed kept no whole line` (test/log/file_error_log_handle_test.dart 280:9). After the fix the whole file passes: +16 ~1 (the ~1 is the existing BUG-L5 skip).
  > - BUG-C1, first failing run (skip removed, old code): `a dangling link wins the race: nothing is created at its target` / `Expected: FileSystemEntityType:<notFound>  Actual: FileSystemEntityType:<file>  opening for append creates a missing file through a link`. With the fix, export_temp_name_edge_test.dart passes: +19. I then stashed only lib/data/your_data_service.dart and ran the test again. It failed with the same Expected/Actual, and passed again after the stash pop.
  > E2E: n/a — no suite yet (end-to-end tools TBD in Team setup)
  > Test hooks: n/a — no UI
  > Deviations from plan: BUG-T1 is proven with a deterministic test (the writers run one after the other) instead of the loop with `yes` load. The brief said a deterministic proof is preferred. I did not start any `yes` processes, so none needed killing. I also edited docs/PLAN.md: the garble-rate note under the BUG-L5 Later line said the test "checks that each writer keeps at least one whole line", which is no longer true, so I corrected it.
  > Checklists: data-and-apis — n/a items: migrations, endpoints/authorisation, outbound calls/timeouts (this is a local file write only)
  > Risks / unverified: (1) A small gap remains between the new check and `openSync`. Someone who can already write to the export folder, and has listed the random temp name, could swap a dangling link in during that gap and still get an empty file created where it points. The check after the open still stops any bytes being written through it. Closing the gap completely needs a native open; there is a Later line for it. (2) Not run on real Windows. The Windows behaviour was played through the createTemp seam on macOS. Windows CI will confirm it.
  > Personal data touched: export file write path (the user's snippets and history in the export JSON). The behaviour change is refusal only: no new fields, and nothing written to any new place.
  > Later lines added: Export temp file opened with no gap at all against a link swapped in (BUG-C1 residual) — [...] — trigger: the pinned Dart SDK gains such an open mode, or ≥ 1 report of a stray empty file next to an export — noted 2026-11-21 by developer
  > Spec gaps raised: none
  > Findings: BUG-T1 — fixed (6955c1d [...]) | BUG-C1 — fixed (1b3485e [...])
  > Blockers: none

  (The two "[...]" shorten text quoted in full in the commits and in docs/PLAN.md on the branch.) Lead: the BUG-C1 residual gap Later line is a deferral of a known low risk, so it goes to the PM as a decision with the merge ask; the lead does not accept it. Lead pushed a7f30a9..1be521f to fix/windows-ci (approved route for this item) for CI run 3, and dispatched the reviewer (Mode: branch).
- Gates: developer pass · tester pass (BUG-T1, BUG-C1 fixed) · reviewer in progress · QA open · PM merge not asked
- Open findings: none open; BUG-C1 residual gap waiting for PM decision
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7; BUG-C1 residual Later line

## 2026-11-21 — Windows CI green — tester report; CI run 2 green; developer round 3
- Changed: CI run 2 on 11c85b7 (run 44631551718): macos pass (34m36s), windows pass (37m42s). Tester committed afbf373, bd4ca25, a7f30a9 on fix/windows-ci (not pushed). Tester report, word for word:

  > Branch: fix/windows-ci (3 test commits: afbf373, bd4ca25, a7f30a9; not pushed). git status clean, no production file touched, nothing left running.
  > Added: 27 tests (26 run, 1 skipped as a bug repro) in test/data/export_temp_name_edge_test.dart (18), test/support/close_service_real_db_test.dart (6), test/ci/line_endings_checkout_test.dart (2... plus 1 skipped repro counted above; see files). Totals from the suite: 3863 -> 3890 passing.
  > E2E tests added: 0 (n/a — no user flow; this item changes tests, CI config and one file-writing function)
  > Fail-then-pass:
  > - export_temp_name_edge "Windows answer over a link to a folder or a file" and "Windows answer over a dangling link": I took the branch's lib/data/your_data_service.dart and removed only the new typeSync(followLinks:false) check, keeping the createTemp seam. Both fail there ("Expected 'new'..." / the link target was written); both pass on 11c85b7. The old code at the merge base has no seam, so the file does not compile there.
  > - close_service_real_db "closeAndDispose lets go of the database file" and the tear-down order test: with `await service.close()` removed from the helper they fail (Expected false, Actual true; Expected ['closed'], Actual ['open at folder deletion']). Pass on the branch.
  > - line_endings_checkout "text is written with LF and binaries untouched": with the merge-base .gitattributes it fails (Expected [97,10,98,10], Actual [97,13,10,98,13,10]). With the rule changed to `* text eol=lf` (forces binaries to text) it fails on icon.png. Passes on the branch.
  > Regression locks (pass on old and new, justified): export tests for a folder, regular file or hard link at the temp name, a link, dangling link, hard link or folder as target, a failed write that keeps the user's file, a read-only file/folder, and "no temp file left" — they lock behaviour that existed before and that this change touched (the new branch adds a second route to in-place writing). Also the "repository's own binaries are not text" test: it would break if someone adds a rule that forces text. Both are cheap to keep.
  > Bugs found:
  > - BUG-C1 (low) the export creates an empty file where a dangling link points, when a link lands at the temp name AFTER the typeSync check and the create does not fail (the Windows answer, played with the createTemp seam). _writeInto opens the temp name with FileMode.writeOnlyAppend, which creates a missing file through the link; _refuseLink runs after that. The export then fails and the user's file is kept, but the empty file is left outside the export. Needs an attacker to win a race against a 128-bit name, so low; the old code did the same on Windows. Repro: test "a dangling link wins the race: nothing is created at its target" in export_temp_name_edge_test.dart. It is committed with `skip:` (reason string 'BUG-C1 ...') so the suite stays green; remove the skip to see it fail. Suggested fix for the developer: check _refuseLink before opening, or open with a mode that does not create.
  > - BUG-T1 (medium, a flaky test, not product) the rewritten test in test/log/file_error_log_handle_test.dart "two writers x 3,000 lines with rotations..." fails under load. It failed in my first ./tool/check.sh on this branch (the only failure, 3863 passed). Cause: the new rule "each writer keeps at least one whole line" assumes both isolates overlap in time. When one finishes before the other starts, the late writer's 3,000 lines push every line of the first one out through rotation (the file holds only about 560 lines). Message: "Expected: non-empty, Actual: [], storeUnreadable kept no whole line". Repro (not committed, it needs CPU load): run `flutter test test/log/file_error_log_handle_test.dart --plain-name "two writers x 3,000"` in a loop with 8 busy `yes >/dev/null` processes; it failed on the 7th run. The same test passed alone 6 times and under 24 burners 12 times, and once in a full check. It will go flaky on Windows CI too. Fix for the developer: drop the "each writer keeps at least one" assertion (keep "kept is not empty" and the ordering check only for writers that kept lines). A second, unseen risk: the ordering check parses the number from lines that match the shape, and an overwritten (BUG-L5) line can leave extra digits at the end and still match; I did not see it happen. The ordering check itself works: planting `detail -> 2999-detail` in FileErrorLog.log makes it fail ("flushFailed lines out of order at 182, 181"); reverted.
  > Abuse cases covered: 18/18 of those I listed for the export (design note has none beyond the dangling link). The list: dangling link, link to file, link to folder, folder, regular file, hard link at the temp name; the same links, a folder and a hard link as target; Windows-answer over each link kind; a link and a file appearing after the check; read-only file/folder; failure mid-write; existing export longer than the new one; no temp left behind.
  > UI states covered: n/a — no UI
  > Gaps not covered:
  > - T7 comparison: test/data/recheck_fixes_test.dart skips on Windows the link-at-temp-name test, the leftovers test, the hard-link leftover test, the unlistable-folder test and the sandbox test. So on Windows CI the only coverage of the new behaviour is the developer's seam test in your_data_service_test.dart (it uses a Link, and there is no Windows skip — it will fail on a runner without symlink rights; windows-latest runners normally allow it, CI will show). My tests skip every link case on Windows ("creating links needs extra rights"); the folder, regular-file, failing-write and Windows-answer-without-link cases do run there. The real Windows behaviour (exclusive create succeeding over a dangling link) is only exercised by the seam on Mac; only Windows CI confirms it for real.
  > - Helpers (A): a test that forgets the helper cannot be caught on a Mac (Mac allows deleting an open file). close_service_real_db_test uses lsof to show dispose() alone leaves kusunga.db open while closeAndDispose releases it, and that the tear-down runs before a folder deletion registered earlier. Only the Windows run fails for a forgetful test (errno 32). I did not add a static scan of test files: it is too heuristic (some files close the store directly). Windows CI results decide whether other sqlite-based test files still leak.
  > - Can only be confirmed by Windows CI: groups A, B, D (CRLF checkout), E, the key-timeout counts on a slow runner, `flutter build windows` (/W4 /WX) and my lsof test being skipped there.
  > Other checks done:
  > - .gitattributes: `git add --renormalize .` changes nothing. `git ls-files --eol`: 431 text files i/lf, 239 i/-text (236 png, 3 ico), none crlf or mixed. `git check-attr` shows text=auto eol=lf for dart/swift/cpp/md; png and ico show text: auto too, but Git detects them as binary by content (NUL bytes; PNG signature holds CR LF and survives autocrlf=true in my temp-repo test; also an SQLite header and TTF shapes). LICENSE: text unset. Caveat: text=auto is content sniffing, so a future binary with no NUL bytes in its first 8 KB could be converted; none tracked (no .db/.ttf tracked at all).
  > - Key time-out counts: mutation (re-read waits 5 ms instead of the key time-out) makes the counts fail (Expected 3, Actual 2; and the late-call test fails). Good. Reverted.
  > - Swift: ./tool/test_mac_login_item.sh passes (30 tests, 0 failures, ~3.5 s). With the merge-base LoginItemCore.swift put back, the guard prints "expression took 778ms to type-check (limit: 100ms)" and "FAIL: ... split it up" and the script stops before building; with the branch file restored it passes. File restored, git status clean. The guard depends on swiftc's wording ("type-check") and on a 100 ms limit on a possibly slower machine; it is a local early warning, not a replacement for the CI Xcode 16.4 build.
  > - Own-marker false green (E): p.basename fix is correct by reading; I did not add a mutation for it.
  > Production code changed: none
  > Suite: 3890 passing / 0 failing / 11 skipped on the last full ./tool/check.sh (was 3863 passing / 1 failing / 10 skipped on the branch before my tests; the one failing was BUG-T1). The suite remains exposed to BUG-T1 flakiness under load.
  > Blockers: none

  Lead: BUG-T1 and BUG-C1 go back to the developer (opus, same branch) before the reviewer; BUG-C1 is in the function this item changes (W2 A), so it is fixed here, not deferred.
- Gates: developer round 3 (BUG-T1, BUG-C1) · tester pass with 2 bugs · reviewer, QA open · PM merge not asked
- Open findings: BUG-T1 medium (flaky test), BUG-C1 low (export race)
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7

## 2026-11-19 — Windows CI green — developer round 2; pushed; tester started
- Changed: developer (opus) round 2 on fix/windows-ci: feb11b6 fix(macos) LoginItemCore.swift closure-in-ternary split into `private static func reached(_:on:)`, same checks, plus a type-check-time guard (`-warn-long-expression-type-checking=100`) in tool/test_mac_login_item.sh — old expression took 860 ms locally on Swift 6.4.2, guard failed first; 11c85b7 test(data) key_delete_timing counts time-outs in a Zone (3, and 1 for memory-only) instead of the 1.2 s wall-clock bound; open() moved out of the stopwatch; "never waits for ever" as a 4 s time-out. Failing first: simulated slow runner gave 1.352 s (matches CI 1.326 s); mutation runs fail as expected. check.sh: "+3864 ~10: All tests passed!"; tool/test_mac_login_item.sh 30/30; `flutter build macos --debug` built locally (not launched). Deviation: the CI Swift step uses `xcodebuild test`, which the rules forbid locally; developer ran the same LoginItemCoreTests via tool/test_mac_login_item.sh. Lead pushed 54fa956..11c85b7 to fix/windows-ci (PR 9). Tester dispatched on the branch while CI runs.
- Gates: developer handed off (CI run 2 pending) · tester in progress · reviewer, QA open · PM merge not asked
- Open findings: CI run 2 pending
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7

## 2026-11-19 — M1.9f DPIA — draft written
- Changed: lead drafted docs/design/dpia.md (ICO template structure): screening (new technology and invisible processing possible; no other trigger), on-device processing table, beta processing table, necessity and proportionality, risks R1–R9 and measures. App facts checked against main by a scout lookup: the log holds only time, event code and an optional number (lib/log/app_log.dart); limit 10–5,000, default 200 (history_store.dart:24-25); concealed/transient/auto-generated copies skipped on Mac and excluded copies on Windows, no setting (ClipboardWatcher.swift:29-33, clipboard_policy.h); export dialog says "The file isn't encrypted" (your_data_section.dart:33-34); tray icon at launch; typed shortcuts off by default (migrations.dart:112); password and secure-input fields skipped (TypedShortcutCore.swift:215, typed_shortcut_policy.h:354-365); no network code in lib/ or the runners.
- Gates: n/a — a document; the PM signs it (AC)
- Open findings: none
- Decisions: waiting for the PM (DPIA section 7): lawful basis and retention for tester contact details and for feedback; the feedback email address; acceptance of residual medium risks R1, R5, R9; sign-off.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — DPIA section 7

## 2026-11-19 — M1.9 Signed installers and first beta — deck approved
- Changed: the PM approved the M1.9 deck docs/slides/signed-installers-and-beta.html and its decisions as recommended. Design note status, ADR 0006 and ADR 0007 set to accepted; plan D5 (Windows) closed. Build order (design note): parts a (About and licences), b (Mac release build) and f (DPIA draft, lead) first. Developer work on M1.9 starts after "Windows CI green" hands off, so check runs never overlap.
- Gates: design approved · developer not started · tester, reviewer, QA open · PM merge n/a yet
- Open findings: none
- Decisions: PM decision (2026-11-19): D1 A — Microsoft Store (MSIX), SignPath Foundation as the fall-back; D2 A — keep the SHA-256-pinned sqlite3mc prebuilt; D3 A — Apple silicon only; D4 A — 5–20 invited testers, GitHub Releases pre-release; D5 A — version 0.9.0; D6 A — release script on the PM's Mac (ADR 0006); D7 A — feedback by email to an address the PM chooses — PM said: "approve decisions, am going to sleep you can continue". Not decided: the lawful basis and the retention for tester contact details and feedback (needed before the beta; M1.9f).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — lawful basis and retention for tester data; feedback email address; Apple Developer Program

## 2026-11-19 — Windows CI green — PR 9 CI run 1: Windows 1 failure, Windows build passes; Mac build fails
- Changed: CI run 44590610889 on fix/windows-ci (54fa956). windows: check.ps1 "3808 tests passed, 1 failed, 69 skipped" — the 84 other failures are gone; the failure is test/data/key_delete_timing_test.dart:222 "a re-read that hangs is given up on after one time-out… stuck, in about three time-outs": Expected < 0:00:01.200000, Actual 0:00:01.326100 (timing). `flutter build windows --debug` passed: "Built build\windows\x64\runner\Debug\kusunga.exe" — the first MSVC build of Kusunga. macos: check.sh passed; `flutter build macos --debug` failed on the runner's Xcode 16.4: macos/Runner/LoginItemCore.swift:58:9 "the compiler is unable to type-check this expression in reasonable time" (the closure-in-ternary `let done`); the PM's Xcode 27.2 builds it. The Swift and C++ steps after it were skipped. Logs: scratchpad pr9_win.log, pr9_mac.log. Developer re-dispatched on the same branch for both.
- Gates: developer round 2 · tester, reviewer, QA open · PM merge not asked
- Open findings: 1 Windows timing test failure; Mac CI build failure
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.9 deck (D1–D7)

## 2026-11-19 — Windows CI green — developer hand-off; branch pushed; PR open
- Changed: developer (opus) handed off fix/windows-ci, 8 commits on main e64ca0e (00bd126 A close-then-dispose helper in 8 files; e14ec91 B stuck files after show(); cd18c05 C export writes in place when anything is at the temp name, with an optional createTemp test seam; e023904 + ae65c68 D `* text=auto eol=lf`, renormalize changed nothing, readSource() for guard tests; 97f7317 E package:path, own_marker false green fixed; 2d20fc7 Mac log test: per-writer order instead of the 90% floor, BUG-L5 note; 54fa956 CI builds Windows with `if: ${{ !cancelled() }}`). check.sh run alone: "+3864 ~10: All tests passed!", exit 0. Failing-first evidence for A, C, D, E, Mac and CI; B needs Windows CI (Mac sqlite3mc replaces the fake file). Needs Windows CI: A, B, E, the eol checkout and the build step. Developer observation (not fixed, BUG-L5 area): in local runs `.1` held only 2 lines. Lead pushed fix/windows-ci (PM decision of 2026-11-19) and opened https://github.com/Thamzy265/kusunga/pull/9. The branch also carries the 8 local docs commits on main that were not pushed (status entries, M1.9 design, Windows CI design and deck).
- Gates: developer handed off (CI pending) · tester, reviewer, QA open · PM merge not asked
- Open findings: Windows CI result pending
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for the PR #9 CI run · PM — M1.9 deck (D1–D7)

## 2026-11-19 — Windows CI green — deck approved; build started
- Changed: PM approved the deck docs/slides/windows-ci-green.html with the recommended options. Plan: W1–W3 recorded on the item; W3 added to M1.9 as an AC for part d. Developer briefed on fix/windows-ci.
- Gates: design approved · developer in progress · tester, reviewer, QA open · PM merge n/a yet
- Open findings: 85 Windows test failures, 1 Mac CI timing failure
- Decisions: PM decision (2026-11-19): W1 A — fix the tests only; W2 A — fix the export over a dangling link in this item; W3 A — single instance on Windows in M1.9d, before the beta — PM said: "Yes, as recommended"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.9 deck (D1–D7)

## 2026-11-19 — Windows CI green — diagnosis done; design and deck ready
- Changed: developer (opus) diagnosis, no code changed; branch fix/windows-ci made from main 6bfb385 with 0 commits. Report: Windows 85 = A 73 (tests clean up with HistoryService.dispose(), which never closes the store, history_service.dart:831-841; Windows refuses to delete the open kusunga.db, errno 32) + B 3 (1-byte fake kusunga.db, your_data_edge_test.dart:388-391; Windows SQLite "file is not a database", Mac sqlite3mc replaces it) + C 1 (product, minor: export temp createSync(exclusive) succeeds over a dangling link on Windows, then _refuseLink fails the export, your_data_service.dart:67,:117) + D 6 (guard tests vs CRLF checkouts) + E 2 (guard tests assume `/`; also a false green at own_marker_edge_test.dart:264). Mac 1: file_error_log_handle_test.dart:240-258, 90% floor vs non-atomic append (BUG-L5), load-dependent. Delete everything on Windows: works with one Kusunga running (developer about 85% sure; the full-erase tests passed on windows-latest); a second Kusunga process (no single-instance guard on Windows) would leave kusunga.db, shown by the existing partial message. Risk: native Windows code never compiled with MSVC, /W4 /WX (windows/CMakeLists.txt:39). Lead wrote docs/design/windows-ci-green.md and docs/slides/windows-ci-green.html.
- Gates: design ready · developer build not started (waits for deck approval) · tester, reviewer, QA open · PM merge n/a yet
- Open findings: 85 Windows test failures, 1 Mac CI timing failure
- Decisions: waiting for the PM: W1 group A fix (tests only, or also dispose() closes the store), W2 export over a dangling link (fix now or Later), W3 single instance on Windows (M1.9d or Later). Lead decisions: CI runs `flutter build windows` even when tests fail; the Mac test change goes to the reviewer to judge whether it weakens the test.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — Windows CI green deck (W1–W3); M1.9 deck (D1–D7)

## 2026-11-19 — Windows CI green — PM decision on the verification route; diagnosis started
- Changed: new plan item "Windows CI green", before M1.9d. Size: large (spans many test modules and may touch Delete everything on Windows, which deletes personal data). Step 1 is a diagnosis by the developer (no commits): the root cause of each failure group in CI run 44550682517 and whether any product code is wrong on Windows. The lead then writes the design and the deck for the PM before any fix is built.
- Gates: developer diagnosis in progress · tester, reviewer, QA open · PM merge n/a yet
- Open findings: 85 Windows test failures, 1 Mac CI timing failure
- Decisions: PM decision (2026-11-19): the Windows CI fix goes on its own pushed branch with a pull request, so CI tests it on Windows before it reaches main — scope: the "Windows CI green" item only; other branches stay local — PM said: "Yes, branch and PR"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.9 deck approval

## 2026-11-19 — CI — first full run on GitHub-hosted runners: both jobs fail
- Changed: CI run 44550682517 (main 7e9baf5, re-run after the repo went public) finished. macos: check.sh 3854 passed, 1 failed, 10 skipped — the failure is test/log/file_error_log_handle_test.dart "per-line open, real concurrency (two isolates) two writers x 3,000 lines with rotations…" (timing under CI load; it passes locally). windows: check.ps1 3715 passed, 85 failed, 69 skipped — the first time Kusunga's tests ran on Windows; `flutter build windows` did not run. Windows failures by cause (lead's first look at the log, not a diagnosis): (1) temp-folder clean-up fails with "being used by another process" (errno 32) in your_data_section (30), your_data_edge (17), your_data_round2 (13), key_delete_timing (6), data_eraser (5), export_erase_edge (3), open_app_history, your_data_service, round2_fixes — files still open when the test deletes its folder; may also hide a real Windows problem in Delete everything (files open while deleting); (2) guard tests that assume `/` paths (`runner\app_id_test.cpp`); (3) guard tests that read files checked out with CRLF (`#include? "Local.xcconfig"\r`); .gitattributes covers only LICENSE. Logs: scratchpad ci_win.log, ci_mac.log.
- Gates: n/a — CI result; a fix item goes through every gate
- Open findings: 85 Windows test failures, 1 Mac CI timing failure
- Decisions: none yet. Lead: new plan item "Windows CI green" before M1.9d; verifying it needs Windows runs, and the standing rule is "push only main" — PM decision needed on how the fix is verified.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — verification route for the Windows fix; M1.9 deck approval

## 2026-11-19 — M1.9 Signed installers and first beta — design and deck ready
- Changed: PM said "Yes, start M1.9". Size: large (release; new trust boundaries: signing keys and the download channel; moves the Mac history key). Lead wrote the design note `docs/design/signed-installers-and-beta.md`, ADR 0006 (release signing on the PM's machine, proposed), ADR 0007 (Mac key in the data-protection keychain, proposed), the UI spec `docs/ui/about-and-licences.md` and the deck `docs/slides/signed-installers-and-beta.html`. Work split: M1.9a About/licences, M1.9b Mac release build, M1.9c key move, M1.9d Windows packaging, M1.9e release script, M1.9f DPIA. Facts from a scout lookup of main at 02369fb. Windows signing facts from Microsoft Learn "Code signing options" (updated 2026-11-10): Store MSIX is free and Microsoft signs it; Azure Artifact Signing for individuals is limited to the USA and Canada; OV certificate about $150–300 a year; EV no longer skips SmartScreen; SignPath Foundation is free for open-source projects (eligibility not confirmed).
- Gates: design ready · developer not started (waits for deck approval) · tester, reviewer, QA open · PM merge n/a yet
- Open findings: none
- Decisions: waiting for the PM: deck approval and D1 Windows signing, D2 sqlite3mc prebuilt or source, D3 Mac architectures, D4 beta size and download place, D5 version, D6 release process, D7 feedback channel plus the lawful basis and retention for tester data.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — deck approval and D1–D7

## 2026-11-19 — Repo — public; main protected
- Changed: the PM made Thamzy265/kusunga public (gh: visibility PUBLIC). CI run 44550682517 re-run: both jobs started this time. Main had no branch protection and no rulesets. Lead created the ruleset "Protect main" (id 27648779, active, default branch, no bypass): rules deletion and non_fast_forward (blocks force pushes and deletion). Normal pushes to main still work.
- Gates: n/a — repo settings
- Open findings: none new
- Decisions: PM said: "go public then re run the ci"; "block force pushes and deletion on main" (2026-11-19)
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Repo — PM decision: make the repo public
- Changed: the PM decided to make Thamzy265/kusunga public and then re-run CI. The PM changes the visibility on GitHub themselves (standing rule). The lead re-runs CI once the PM confirms.
- Gates: n/a — decision
- Open findings: none new
- Decisions: Risk accepted by PM (2026-11-19): accepted: the repo's commit history becomes public, including the PM's Gmail address in the commit metadata, the Apple team ID in commits 6269a6a and 7311e39, and the home path /Users/williamnasoni in docs/qa/m1.md and test/ui/m16_real_font_layout_test.dart (history check, 2026-11-18: no secrets) — scope: the whole repo history at the time it is made public — expiry/review: none — PM said: "go public then re run the ci". Condition kept: the homelab Windows runner must not be attached while the repo is public (docs/ci/windows-runner.md).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — change the visibility on GitHub

## 2026-11-19 — Repo — main pushed
- Changed: main pushed to origin (8648169..7e9baf5, 28 commits, including the licence merge 96551bb). origin/main was not ahead before the push. Repo still private.
- Gates: n/a — push of already-gated work
- Open findings: CI run 44550682517 on 7e9baf5: both jobs (macos and windows) not started — GitHub: "recent account payments have failed or your spending limit needs to be increased". F5 (billing) now blocks the macOS job too. Local check evidence stands.
- Decisions: push approved by PM (2026-11-19). PM said: "Yes, push main"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — GitHub billing (Settings → Billing & plans)

## 2026-11-19 — Licence (GPL-3.0) — merged
- Changed: chore/licence merged into main with a local `git merge --no-ff` (96551bb): LICENSE (SHA-256 3972dc97…, matches the pin), .gitattributes, README Licence section (GPL-3.0-only), docs/licences.md, test/ci/licence_test.dart. On merged main: licence_test.dart "+15: All tests passed!". Plan box ticked. Not pushed.
- Gates: developer pass · tester pass · reviewer approve with notes · QA n/a — no user-runnable change · PM merge approved
- Open findings: cleanup only: N2, L4, R6d.
- Decisions: merge approved by PM (2026-11-19). PM said: "Yes, merge it"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push (not asked yet)

## 2026-11-19 — Licence (GPL-3.0) — reviewer check of L5: approve with notes; merge approval asked
- Changed: reviewer re-check f1a3bfd..38d7518: approve with notes. L5 fixed; doc matches the reviewer's sweep of all upstream .c/.h files (headerless: 12 Ascon files, libargon2.c, mystdint.h in flag 6; extensionfunctions.c in flag 1); "14" agrees in row 19, flag 1 and flag 6. Guard fails on the f1a3bfd text and on flag 1 reverted to "13". Run alone with no flutter_tester running: dart format 0 changed, flutter analyze "No issues found!", licence_test.dart "+15: All tests passed!". Full suite: developer's solo run on 38d7518, 3855 passed, 10 skipped, exit 0. The reviewer's PLAN AC note was done on main in 664a342 (the branch predates it). Lead asks the PM to approve a local `git merge --no-ff chore/licence` into main.
- Gates: developer pass · tester pass · reviewer approve with notes · QA n/a — no user-runnable change · PM merge waiting
- Open findings: cleanup only, none blocking: N2 (the mystdint.h assertion does not check the table row; the flag still names the file), L4 (optional note on the ascon-c repo's CC0 licence), R6d (test tidy-up).
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — merge approval

## 2026-11-19 — Licence (GPL-3.0) — developer fixes L5
- Changed: chore/licence 38d7518. mystdint.h verified upstream (27 lines of typedefs under `_MSC_VER < 1600`, no licence text, included by sha1.c, fastpbkdf2.h, chacha20poly1305.c, sqlite3mc_vfs.c); added to flag 6 and the table as inferred MIT (project LICENSE); "13" → "14" in row 19, flag 1, flag 6; N1 guard asserts mystdint.h and "14 files". First failing run: `Expected: contains 'mystdint.h'` (14 passed, 1 failed). check.sh alone (pgrep 0 before start): 3855 passed, 10 skipped, exit 0. Developer correction of last round's evidence: of "2 failed", one was the L1 overclaim test on the old text and the other the L2 guard on a planted line; the L3 assertions passed on the old text; "L3 failed too" was wrong.
- Gates: developer pass · tester pass · reviewer check of L5 open · QA n/a — no user-runnable change · PM merge waiting
- Open findings: L4, R6d optional. Developer did not sweep other upstream files; the reviewer's sweep last round found only extensionfunctions.c and mystdint.h headerless outside flag 6.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — reviewer quick re-check: approve with notes
- Changed: reviewer re-check 1f4522d..f1a3bfd: approve with notes. L1, L2, L3 fixed. Reviewer did not run the full check.sh (one doc and one test file changed); ran with no flutter_tester running: dart format on licence_test.dart 0 changed, flutter analyze "No issues found!", flutter test licence_test.dart "+15: All tests passed!". Full-suite figure is the developer's solo run (3855 passed, 10 skipped, exit 0). Recount: 12 headerless Ascon files + libargon2.c = 13, correct. Reviewer note: against the 1f4522d text only the overclaim test fails; the L2 and L3 guards pass on the old text by design (they guard future edits), so the developer's "2 failed" needs explaining (not a finding). The PLAN AC wording note is already done on main (664a342).
- Gates: developer pass · tester pass · reviewer approve with notes · QA n/a — no user-runnable change · PM merge waiting
- Open findings: L5 Low (doc accuracy): upstream src/mystdint.h (27 lines of stdint typedefs, MSVC < 2010 only, included by sha1.c, fastpbkdf2.h, chacha20poly1305.c, sqlite3mc_vfs.c) has no licence text and is missing from flag 6, so flag 1's "the rest has a stated licence" is not true. Lead: developer fixes L5 before the merge (add mystdint.h to flag 6, 13 → 14, test assertion). L4, R6d optional.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — developer fixes L1–L3
- Changed: chore/licence f1a3bfd. L1: licences.md SQLite3MC row now "Yes; extensionfunctions.c is unclear (flag 1) and 13 files' licence is inferred (flag 6)"; flag 1 points to flag 6. L2: the later-version guard scans every non-table licences.md line that mentions Kusunga (planted line "Kusunga may also be used under GPL-3.0 or later." failed it, then removed). L3: N1 guard asserts permutations.c, round64.h and the flag 6 text. New guard: the row and flag 1 never say "every part". First failing run: 13 passed, 2 failed (L1 and L3 guards on the old text). check.sh alone (no flutter_tester before start): 3855 passed, 10 skipped, exit 0.
- Gates: developer pass · tester pass · reviewer quick re-check open · QA n/a — no user-runnable change · PM merge waiting
- Open findings: L4 and R6d optional cleanup. Developer: the count "13" (12 Ascon files + libargon2.c) not re-counted this round.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — reviewer re-check: approve with notes
- Changed: reviewer re-check 84892be..1f4522d: approve with notes. check.sh alone (13:02:37–13:11:05 GMT, on 1f4522d, after waiting until no flutter_tester was running): 3854 passed, 10 skipped, exit 0; an earlier reviewer run may have overlapped the developer's background check.sh and is not used. R5 fixed (README:35 and licences.md:3 "version 3 only (SPDX: GPL-3.0-only)"; no "or later" for Kusunga anywhere outside LICENSE; LICENSE hash unchanged; guard fails on the 84892be text and on "or later" and "only dropped" variants). N1 fixed. Developer flags ruled: "public domain" Ascon wording matches the v2.5.0 headers; the 12 headerless Ascon files and argon2/libargon2.c recorded as an inference is acceptable (both candidate licences, MIT and public domain/CC0, are GPL-3.0-only compatible). Lead: plan AC for this item updated to the R5 wording (reviewer note).
- Gates: developer pass · tester pass · reviewer approve with notes · QA n/a — no user-runnable change · PM merge waiting
- Open findings: L1 Low (licences.md:19 and flag 1 still say every part is clear; contradicts flag 6 and the extensionfunctions.c row); L2 Low (the "or later" scan in licences.md reads only "Kusunga is licensed" lines); L3 Low (N1 guard does not name a headerless file or flag 6); L4 cleanup (optional note on the ascon-c repo's CC0 licence, not checked); R6d optional. Lead: L1–L3 go to the developer now, on this branch, before the merge; L4 and R6d stay optional.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — developer fixes R5, N1
- Changed: chore/licence a95f794 (R5: README "version 3 only (SPDX: GPL-3.0-only)"; docs/licences.md title, intro and "Compatible with" headers say GPL-3.0-only; guard tests; first failing run "Expected: contains 'GPL-3.0-only'"), 1f4522d (N1: rows for aes_hardware.c and memory_secure.c (MIT headers), nine Ascon files with MIT headers "Based on: Public domain Ascon reference implementation", argon2/libargon2.c; guard test; first failing run "Expected: contains 'aes_hardware.c'"). LICENSE unchanged. check.sh alone: 3854 passed, 10 skipped, exit 0.
- Gates: developer pass · tester pass · reviewer re-check open · QA n/a — no user-runnable change · PM merge waiting
- Open findings: R6d optional cleanup. Developer flags: the Ascon upstream is "public domain", not CC0 (doc says public domain); 12 Ascon files and argon2/libargon2.c (a 30-line wrapper) have no licence header, recorded as covered by the project's MIT LICENSE, marked as an inference (new flag 6 in docs/licences.md); no binary inspected for which files are compiled in.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — PM decision R5 (GPL-3.0-only)
- Changed: D8 in docs/PLAN.md now says GPL-3.0-only. Lead advice before the decision: "only" keeps the choice of future GPL versions with the copyright holder; moving to "or later" is easy later, moving back is not for copies already released. Developer to update the README wording and the SPDX id in docs/licences.md, and fix N1.
- Gates: developer open (R5, N1) · tester pass · reviewer re-check open · QA n/a — no user-runnable change · PM merge waiting
- Open findings: N1 Low doc; R6d optional cleanup.
- Decisions: R5 — GPL-3.0-only (2026-11-19). PM said: "go with only"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-19 — Licence (GPL-3.0) — reviewer approve with notes
- Changed: reviewer re-check at 84892be: approve with notes. check.sh alone 3852 passed, 10 skipped, exit 0. R1 confirmed (CRLF archive 230184f6…/35823 bytes at 14d4c3c, 3972dc97…/35149 at 84892be; check-attr "text: unset"). R2 confirmed against upstream source in scratchpad/s3mc (MIT LICENSE; SQLite 3.53.4 source id matches the binary; AES MIT vs LGPL-3.0-or-later WITH WxWindows exception compatible either way; extensionfunctions.c absent from both macOS binaries, arm64 b237b5ba… and x64 7ea6e7d2…). R3, R4, R6a–c confirmed. Reviewer agrees with the lead's extensionfunctions.c ruling (M1.9 AC).
- Gates: developer pass · tester pass · reviewer approve with notes · QA n/a — no user-runnable change (a licence file, a README section, a doc and repo guard tests; nothing in the app changes) · PM merge waiting
- Open findings: R5 Low (PM decision: GPL-3.0-only or -or-later); N1 Low doc (name aes_hardware.c, memory_secure.c MIT; the Ascon helper files under the MIT LICENSE, from CC0 reference; argon2/libargon2.c wrapper) — developer to fix with R5; R6d optional cleanup.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — R5

## 2026-11-19 — Licence (GPL-3.0) — developer fixes R1–R4, R6
- Changed: chore/licence ae74b42 (R1: .gitattributes `LICENSE -text`, test via git check-attr; failed first "text: unspecified"; CRLF archive hash 230184f6… at 14d4c3c, 3972dc97… at ae74b42), 7e73123 (R2–R4, R6a–c), 84892be (one doc line). R2: upstream utelle/SQLite3MultipleCiphers v2.5.0 read (read-only, scratch folder s3mc): own code MIT; AEGIS MIT; Ascon MIT; ChaCha20/Poly1305, SHA-1, MD5 public domain; SHA-2 BSD-3-Clause; fastpbkdf2 CC0-1.0; Argon2 CC0-1.0 OR Apache-2.0; AES MIT (filelist says LGPL-3.0-or-later WITH WxWindows exception; compatible either way); miniz MIT; SQLite and extensions blessing; all GPL-3.0-compatible. Unclear: extensionfunctions.c has no licence text; only built with SQLITE_ENABLE_EXTFUNC; not in the macOS arm64 binary (strings); Windows, iOS, Android binaries not checked. SQLite public-domain dedication confirmed at sqlite.org/copyright.html. check.sh alone on 7e73123: 3852 passed, 10 skipped, exit 0. Not verified on a real Windows checkout.
- Gates: developer pass (fixes) · tester pass · reviewer re-check open · QA open · PM merge waiting
- Open findings: R5 (PM decision); R6d optional. Lead ruling: the extensionfunctions.c check of the Windows binary becomes part of the M1.9 licence-screen AC (no shipped binary yet; macOS binary is clear), unless the reviewer objects.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — R5: GPL-3.0-only or GPL-3.0-or-later

## 2026-11-19 — Licence (GPL-3.0) — reviewer block
- Changed: reviewer (branch mode, 2d50b6b..14d4c3c): verdict block. check.sh alone 3848 passed, 10 skipped, exit 0. Security and privacy: no findings (sqlite3 hook pins every prebuilt sqlite3mc binary by SHA-256; both local downloads match). Reviewer read every direct dependency's LICENSE and all 85 pubspec.lock entries: all permissive (BSD-3-Clause, MIT, Apache-2.0, zlib); no GPL-2.0-only, LGPL, AGPL, SSPL, MPL code or proprietary licence. Flutter engine bundles Apache-2.0, MPL-2.0 data, FTL, ICU, zlib, libpng, CC0; Material Icons CC-BY-4.0; all compatible.
- Open findings: R1 Medium — LICENSE pinned-hash tests fail on Windows with core.autocrlf=true (CRLF checkout: 35823 bytes, hash 230184f6…), so check.ps1 and Windows CI fail; fix: .gitattributes `LICENSE -text`. R2 Medium — SQLite3 Multiple Ciphers 2.5.0 licence and its bundled cipher sources (AEGIS, Ascon, ChaCha20, AES, SHA, PBKDF2, RC4, others) not read; AC not met; needs the upstream repo at tag v2.5.0. R3 Low — Flutter row should mention the engine's third-party components and the Material Icons font. R4 Low — licences.md flags: transitive packages now checked; notices needed for any binary given to anyone (the beta too); NOTICES.Z lacks the sqlite3mc/SQLite notice; SQLite SPDX id is `blessing`. R5 Low — PM decision: GPL-3.0-only or GPL-3.0-or-later. R6 Low/cleanup — test gaps (non-lock rows' versions, removed-dependency rows, "direct overridden", repeated assertions).
- Gates: developer pass · tester pass · reviewer block (R1, R2) · QA open · PM merge waiting
- Decisions: none. Lead: the developer may fetch the public upstream repo utelle/SQLite3MultipleCiphers at v2.5.0 (read-only, a public page like the gnu.org fetch; no data sent). Lead: the Later line "In-app licence screen" moves to an M1.9 acceptance criterion (reviewer note: its trigger is an event, not a metric, and notices are a legal duty for any shipped binary).
- Blockers: Developer none · Tester none · Reviewer R2 needs the upstream licence (lead has cleared the fetch) · QA none · Marketer none · Lead none · PM — R5: GPL-3.0-only or GPL-3.0-or-later

## 2026-11-19 — Licence (GPL-3.0) — tester pass
- Changed: tester commit 14d4c3c on chore/licence: 6 offline guard tests in test/ci/licence_test.dart (pinned LICENSE SHA-256 and size, LF endings, README links, every direct dependency has a row, pubspec.yaml vs pubspec.lock, table versions match the lock). Mutation runs failed as expected and pass on the branch. Developer claims verified: LICENSE hash matches a fresh gnu.org download; README only gains the Licence section; vs the merge base 2d50b6b the diff is only LICENSE, README.md, docs/licences.md, test/ci/licence_test.dart (git diff main also shows docs/PLAN.md and docs/status.md because main moved on with 8b9979d). check.sh alone: 3848 passed, 10 skipped, exit 0. The tester once started a second check.sh by mistake; the clean third run alone is the evidence.
- Gates: developer pass · tester pass · reviewer open · QA open · PM merge waiting
- Open findings: none. Not testable: dependency licence correctness (reviewer), transitive dependencies.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-18 — Licence (GPL-3.0) — developer hand-off
- Changed: size small (no code, UI or data). Developer commit 0add0c2 on chore/licence (not pushed): LICENSE = gnu.org gpl-3.0.txt unchanged, 35149 bytes, SHA-256 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986; README "Licence" section with "Kusunga is licensed under the GNU GPL v3.0" and "Copyright (C) 2026 William Nasoni"; docs/licences.md table of 14 direct dependencies (BSD-3-Clause or MIT, SQLite public domain); guard test test/ci/licence_test.dart (failed first, +0 -2; then check.sh 3842 passed, 10 skipped, exit 0). Deviation: test in test/ci, not test/repo (lead accepts: the repo's guard tests live there).
- Gates: developer pass · tester open · reviewer open · QA open · PM merge waiting
- Open findings: none. Developer flags: SQLite3 Multiple Ciphers licence (MIT) not read from a file and its per-cipher code not checked; only direct dependencies checked; BSD/MIT notices must ship with binaries (no in-app licence screen yet).
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-18 — Repo — PM decision D8 (licence)
- Changed: D8 added to docs/PLAN.md as decided; plan item "Licence (GPL-3.0)" (small) added before M1.9. Lead advice given before the decision: GPL-3.0 keeps the code open and stops closed copies; the PM as sole copyright holder can still publish to the app stores and sell sync (D6); a contributor agreement is needed only once outsiders contribute.
- Gates: n/a — decision; the licence item will go through every gate
- Open findings: none
- Decisions: PM said: "go with GPL-3.0" (2026-11-18), in answer to "what licence do you recommend to have for this one?" (lead recommended GPL-3.0).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead — my-tech-team role agents may be unavailable in this session · PM — public or private; Windows runner if private; join the Apple Developer Program; D5 Windows part; M1.4–M1.8 PM checks; delete the stray QA export in Documents

## 2026-11-18 — Repo — pre-publication check of the full history (lead)
- Changed: lead scanned all 671 commits on all branches (every added line, commit messages, files ever added, deleted files, ignored files, files over 2 MB) before the PM decides whether to make the repo public. No secrets found: no API keys, tokens, private keys, certificates or provisioning profiles; Local.xcconfig never committed; no git-ignored file ever committed; no videos; no file over 2 MB. Test data uses reserved fake values only (07700 900123, 4111 1111 1111 1111, example.com addresses, the standard example IBAN). The 2 screenshots deleted from history were viewed: QA test data only. The 236 current screenshots were checked when committed; not re-viewed now.
- Found (PM decision needed before going public): (1) the PM's personal Gmail address is the author email of 668 commits (metadata only, not in any file); (2) the local Apple team ID is in the history of docs/qa/m1.md (commits 6269a6a and 7311e39; redacted in cdc3949, absent from main now); (3) the PM's Mac user folder path appears in docs/qa/m1.md and test/ui/m16_real_font_layout_test.dart on main; (4) the PM's name and the id com.wnasoni.kusunga appear in docs and code (the publisher name, public anyway once released). No licence file.
- Gates: n/a — read-only check
- Open findings: none for code; the 4 items above are PM decisions
- Decisions: PM said: "yes, run the check" (2026-11-18), in answer to "Should I run that check before you decide?".
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — public or private (and, if public: the email in history, the team ID in history, a licence); set up the Windows runner if staying private; join the Apple Developer Program; D5 Windows part; M1.4–M1.8 PM checks; delete the stray QA export in Documents

## 2026-11-18 — F5 Windows CI — homelab runner chosen
- Changed: lead wrote docs/ci/windows-runner.md, the PM's setup guide for a self-hosted Windows runner (label kusunga-windows). Workflow not changed yet; the developer changes runs-on on a branch once the runner shows Idle.
- Gates: n/a — guide only; the workflow change will go through every gate
- Open findings: none
- Decisions: PM said: "Yes, a Windows VM" (2026-11-18), in answer to "Do you have a Windows machine or VM in the homelab for the runner?".
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead — my-tech-team role agents not available in this session; needed for the workflow change · PM — set up the Windows runner (docs/ci/windows-runner.md); join the Apple Developer Program; D5 Windows part; M1.4–M1.8 PM checks; delete the stray QA export in Documents

## 2026-11-13 — M1.9 — PM decision D4 (name)
- Changed: D4 decided; D4 row in docs/PLAN.md updated. The recommended trademark and app-store name check is not done yet.
- Gates: n/a — decision, no code
- Open findings: none
- Decisions: PM said: "we are keeping the name" (2026-11-13). PM also asked whether the Windows CI can run on the PM's homelab (a self-hosted runner); answered, no decision yet.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — trademark and app-store name check (optional); join the Apple Developer Program; D5 Windows part; Windows CI (billing or homelab runner); M1.4–M1.8 PM checks; delete the stray QA export in Documents

## 2026-11-13 — M1.9 — PM decision D5 (Mac part)
- Changed: D5 Mac part decided; D5 row in docs/PLAN.md updated. Windows part still open (lead recommendation: no Windows certificate for the beta; choose Microsoft Store or Azure Trusted Signing before the public release).
- Gates: n/a — decision, no code
- Open findings: none
- Decisions: PM said: "i will get the apple developer account" (2026-11-13), after the lead explained that without it the Mac app can't be notarised, and that updates would likely reset Accessibility and may lose keychain access to the key.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — join the Apple Developer Program; D5 Windows part; D4 (name); F5; M1.4–M1.8 PM checks; delete the stray QA export in Documents

## 2026-11-13 — main — pushed to GitHub
- Changed: main pushed to origin (github.com/Thamzy265/kusunga), including M1.8 and this log entry. Only main pushed; no branch, no tag.
- Gates: n/a — push of already-merged work
- Open findings: none
- Decisions: PM said: "Push main" (2026-11-13), in answer to "Push main to GitHub now?".
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.8 PM checks; delete the stray QA export in Documents; M1.7 PM checks; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5; D4 and D5 before M1.9

## 2026-11-13 — M1.8 Your data: export and delete — merged to main (done)
- Changed: feat/your-data merged into main with --no-ff as b0d7763. Checks on merged main, run one after another: check.sh "Formatted 287 files (0 changed)", "No issues found!", 3840 passed, 10 skipped ("All tests passed!"); test_mac_capture.sh 40/0; test_mac_shortcuts.sh 165/0; test_mac_shortcuts_release.sh 153/0; test_mac_login_item.sh 30/0; test_windows_policy.sh all passed. M1.8 ticked in docs/PLAN.md. Not pushed.
- Gates: developer pass · tester pass · reviewer approve with notes (closed) · QA pass · PM merge approved
- Open findings: none. Lead observation (debug builds only): in a test profile the Delete everything dialog still lists "Kusunga's key" and "Launch at login is turned off".
- Decisions: PM said: "Approve the merge" (2026-11-13), in answer to "Approve merging M1.8 into main on this Mac (no push)?". No push: push needs the PM's approval at the time.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.8 PM checks (docs/qa/m1.md#pm-check-m18: export, Delete everything on your own build, re-import, VoiceOver); delete the stray QA export ~/Documents/kusunga-export-2026-11-13.json; push of main; M1.7 PM checks; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5; D4 and D5 before M1.9

## 2026-11-13 — M1.8 Your data — QA pass; waiting for PM merge approval
- Changed: QA commit bdf4de9 (docs/qa/m1.md "M1.8 Your data", 18 screenshots m1.8-*.png). Debug build, qa profile only, label checked before each step; default profile never started (only stat). PASS AC1: section copy; export dialog defaults; export with and without history (approved fields only, no temp file left); Delete all history; import (counts, toast, history back); re-import "Nothing was imported." with already-here sentences; bad file refused, importRejected 3; Delete everything cancelled with Escape; fresh start after Delete everything; re-import with settings ticked (;qa1 shortcut back, auto-delete from file); keyboard order, focus rings, Escape; 360 px; log codes only. AC2 partial: Delete all history verified; Delete everything in the qa profile removed profiles/qa only — default kusunga.db and kusunga.log unchanged in size and time, launch at login unchanged; real key deletion and D6 need the PM on an installed build. Save/Open panels driven by keyboard only. Videos qa-artifacts/m1.8/ (export, import, delete everything; git-ignored). Stray QA export left at ~/Documents/kusunga-export-2026-11-13.json (qa test data only; QA's shell can't delete there). Lead spot-checked m1.8-import-toast.png and m1.8-delete-everything-dialog.png: no PM data. Lead observation: in a test profile the Delete everything dialog still lists "Kusunga's key" and "Launch at login is turned off", which a profile doesn't do (debug builds only).
- Gates: developer pass · tester pass · reviewer approve with notes (closed) · QA pass (AC1; AC2 except the real key and D6, which need the PM) · PM merge waiting
- Open findings: none (lead observation above, debug only)
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — merge approval; M1.8 PM checks (docs/qa/m1.md#pm-check-m18); delete the stray QA export in Documents; M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — R6 test added, QA starts
- Changed: Developer added the R6 regression test with a narrow open() seam in 5954c92 (fails with the read moved after COMMIT; passes at HEAD). check.sh 3840 passed, 10 skipped (all older); native suites all pass. Reviewer's R6-test note closed by the lead on this evidence (test-only seam, no behaviour change). QA briefed: qa profile only; exports under qa-artifacts/m1.8/; Delete everything only in the qa profile; never start the default profile.
- Gates: developer pass · tester pass · reviewer approve with notes (note closed) · QA running · PM merge —
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — reviewer re-check: approve with notes
- Changed: Reviewer re-reviewed 2f547c8..110d391 with mutation checks in a scratch worktree: R1–R5, R7a, R7b and the cleanup fixed (each test fails when its fix is reverted or mutated); R8–R11 verified; R1 traced: no path removes an existing row, preview equals import, cached limit set only after commit. Security 0, privacy no issues. All six checks pass (check.sh 3839 passed, 10 skipped).
- Findings: R6-test Low — the R6 fix (limit read inside the transaction) has no regression test.
- Gates: developer adding the R6 test · tester pass · reviewer approve with notes · QA — · PM merge —
- Open findings: 1 Low (R6-test)
- Decisions: none. Lead: tests are never deferred, so the developer adds the R6 regression test (a fault seam) before QA.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — R11 fixed, reviewer re-check
- Changed: Developer fixed R11 in 110d391 (an imported setting is compared with the value in use: the stored row, or the app's default). BUG-R11 repro passes unedited; no M1.8 test skipped. check.sh 3839 passed, 10 skipped (all older); native suites all pass. Tester gate closed by the repro passing. Reviewer asked to re-check 2f547c8..110d391 (R1–R11).
- Gates: developer pass · tester pass · reviewer re-check running · QA — · PM merge —
- Open findings: none open in code; waiting for the reviewer
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — tester re-check: R10 closed, 1 Low
- Changed: Tester commit f08ee61: the three R10-skipped tests rewritten and un-skipped; R10 matrix added. check.sh 3837 passed, 11 skipped (10 older + BUG-R11); native suites all pass.
- Findings: R11 Low — a setting at its default with no stored row (e.g. paste_mode auto on a fresh database) counts as a change, so the toast says settings were imported when nothing visible changed.
- Gates: developer fixing R11 · tester open (1 Low) · reviewer re-check after · QA — · PM merge —
- Open findings: 1 Low (R11)
- Decisions: none from the PM. Lead: compare with the value in use (the stored row, or the default when there is none).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — R10 fixed
- Changed: Developer fixed R10 in 83c6466 (settingsApplied only when a stored value changes or an app is added; "Nothing was imported." when nothing at all changed). BUG-R10 repro passes unedited. Three tester tests skipped for rewrite (lead agreed, option A). check.sh 3824 passed, 13 skipped; native suites all pass. HEAD 83c6466.
- Gates: developer pass · tester re-check started (rewrite 3 tests) · reviewer re-check after · QA — · PM merge —
- Open findings: R10 fixed, waiting for re-checks
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — tester re-check: R8, R9 closed, 1 Low
- Changed: Tester commit ba9d2cf: the two R9-skipped tests rewritten and un-skipped; older tests tightened so shown rows must be exactly unchanged; preview-equals-import sweep extended. check.sh 3825 passed, 11 skipped (10 older + BUG-R10); native suites all pass.
- Findings: R10 Low — when the only settings in the file were kept, the toast says "Imported the settings and ignored apps in this file." and then "Your history limit wasn't changed…", which contradict.
- Gates: developer fixing R10 · tester open (1 Low) · reviewer re-check after · QA — · PM merge —
- Open findings: 1 Low (R10)
- Decisions: none from the PM. Lead ruling: settingsApplied only when at least one setting or app actually changed; when nothing at all changed, the toast starts "Nothing was imported." followed by the sentences that apply.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — R8 and R9 fixed
- Changed: Developer fixed R9 (2304b77: an import never changes an item already shown; counted as already here; toast "{n} history {item was/items were} already here.", lead copy) and R8 (2126ca1: "Imported the settings and ignored apps in this file." followed by every sentence that applies, lead agreed). Both repros pass unedited. Two tester tests asserting the old merge times skipped for rewrite (R9). check.sh 3814 passed, 12 skipped; native suites all pass. HEAD 2126ca1.
- Gates: developer pass · tester re-check started (rewrite 2 tests) · reviewer re-check after the tester · QA — · PM merge —
- Open findings: R8, R9 fixed, waiting for re-checks
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — tester re-check: R1–R7 closed, 2 Low
- Changed: Tester commits c770495, b96e0c5: the three skipped tests rewritten and un-skipped; 48-case R1 sweep (no existing row ever removed; preview equals import); R2–R7 edge tests. check.sh 3813 passed, 12 skipped (10 older + 2 repros); native suites all pass.
- Findings: R9 Low — merges into shown items change their times (and can reorder the list), so "Nothing you have now will be changed or removed." isn't strictly true. R8 Low — a settings-only import ends with "Imported 0 snippets and 0 history items." and never says the settings were applied.
- Gates: developer fixing R8, R9 · tester open (2 Low) · reviewer re-check after · QA — · PM merge —
- Open findings: 2 Low (R8, R9)
- Decisions: none from the PM. Lead rulings: R9 — an import leaves items already shown unchanged (counted as already here), so the confirm line stays true; R8 — a settings-only import toast reads "Imported the settings and ignored apps in this file.", followed by any kept-setting sentences.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — developer fixes for reviewer round 1
- Changed: Developer fixed R1 (30504ba; import never deletes history; fills free room newest first; a lower limit or shorter auto-delete in the file is kept as it is), R6 (6d8ee23), R2 (e0f1724), R3 (85b1644), R4 (0f19130), R5 (13d46ef), R7b (27f9c73), R7a (e72aeae), cleanup (310d86f). HEAD 310d86f. check.sh 3726 passed, 13 skipped (10 older + 3 tester tests skipped for rewrite: two R1, one R7a; lead agreed); native suites all pass. During the round the lead agreed: skip the R7a tester test; a leftover -shm and memory-only with a failed key delete get the plain message.
- Deviations reported: "Change it in Settings." for one kept setting; "shown" = not hidden by auto-delete; dataImportSkipped also counts items that didn't fit; merges into shown items still update their times, so "changed" in the confirm isn't strictly true.
- Gates: developer pass · tester re-check started (rewrite 3 skipped tests) · reviewer re-check after the tester · QA — · PM merge —
- Open findings: R1–R7 fixed, waiting for re-checks
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-13 — M1.8 Your data — PM decisions on the review round
- Changed: Developer re-dispatched for R1–R7 and the cleanup.
- Gates: developer fixing · tester pass · reviewer block (R1) · QA — · PM merge —
- Open findings: 1 Medium (R1), 6 Low (R2–R7)
- Decisions: PM said: "Never remove (Recommended)" (2026-11-13), in answer to how import should behave: import never deletes existing history; imported items fill only the free space up to the limit, and the summary says how many didn't fit; a file's lower limit or shorter auto-delete isn't applied if it would delete items, and the summary says to change it in Settings. PM said: "Same developer (Recommended)" (2026-11-13), in answer to how the fixes go ahead (opus, xhigh). Lead rulings for the Lows: R4 a settings-only file can be imported (confirm "This file has settings and ignored apps, but no snippets or history." with the tick box; Import works only when it is ticked); R7a the partial message drops "but it can't be read any more" when any leftover is not an encrypted database file.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — reviewer round 1: block (R1)
- Changed: Reviewer (Mode: branch, accdfb3..2f547c8). All six checks pass (check.sh 3700 passed, 10 skipped); `flutter build macos --debug` built (only an upstream deprecation warning); built entitlements app-sandbox, allow-jit, get-task-allow, network.server, user-selected.read-write. Security review: 0 findings. file_selector 1.1.0 and its transitive packages (cross_file, platform_interface, http, http_parser) are BSD-3; nothing does network I/O. Export fields are exactly the approved set; no key delete in a profile; links never followed; T5 logic correct; import checks match the app's rules.
- Findings: R1 Medium — an import can delete existing history with no warning (the trim to the limit removes the user's oldest items; ticked settings with a lower limit or shorter auto-delete delete most history at once), while the dialog says "Nothing you have now will be changed or removed" (against D3 and the M1.7 confirm rule). R2 Low — Delete all history from Settings doesn't drop History's pending Undo, so Cmd+Z brings a deleted item back. R3 Low — the sandbox direct write deletes an existing read-only file it never opened. R4 Low — a settings-only export can't be imported ("nothing to import"). R5 Low — an export can hold more than 5,000 history items (waiting copies), which import refuses. R6 Low — a read error after COMMIT reports "Nothing was changed". R7 Low — (a) leftover log files are called unreadable; (b) Windows CredDeleteW errors are logged with no number. Cleanup: setting value sets checked in three places.
- Gates: developer — · tester pass · reviewer block (R1) · QA — · PM merge —
- Open findings: 1 Medium (R1), 6 Low (R2–R7)
- Decisions: none yet. Taken to the PM: how R1 is fixed, and the escalation (the developer is already on opus at xhigh after one failed round).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — R1 approach; developer escalation; M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — T10 fixed, review starts
- Changed: Developer fixed T10 in 2f547c8 with the lead's wording for a debug profile: "Everything is deleted. {n} {file/files} in this test profile couldn't be removed." (B2, chosen so the tester's repro passes unchanged). The unused _repro declaration removed (lead agreed). check.sh 3700 passed, 10 skipped (all older, none M1.8); native suites all pass. Tester gate closed by the repro passing.
- Gates: developer pass · tester pass · reviewer started (Mode: branch, accdfb3..2f547c8) · QA — · PM merge —
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — tester re-check: T1–T9 closed, 1 new Low
- Changed: Tester commits 9506969, 869ecda, b751919: BUG-T5 repro rewritten to ruling B and un-skipped; key_delete_timing_test (13) and recheck_fixes_test (33) added; three timestamp tests renamed to decoder or store level. T1–T9 closed; the developer's edits to tester tests reviewed and accepted. check.sh 3696 passed, 11 skipped (10 older + BUG-T10 repro); native suites all pass.
- Findings: T10 Low — in a debug data profile the partial message says leftover files "can't be read any more", which is false (the profile shares the key).
- Gates: developer fixing T10 · tester open (1 Low) · reviewer — · QA — · PM merge —
- Open findings: 1 Low (T10)
- Decisions: none from the PM. Lead copy for a profile's partial message: "Everything in this test profile is deleted. {n} {file/files} couldn't be removed."
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — developer fixes for tester round 1
- Changed: Developer (opus, xhigh) fixed T7 (3572c09), T8 (2289108), T6 (d589309), T5 (5255eef, ruling B; stuck → capture stopped, note, OK quits), T1 (844fcab), T2 (fb75e2f), T3 (a5ded61), T9 (b9543c8), the timestamp ruling (79b4c83, in checkImportTimes after decodeImport), T4 (143bade, counts from a rolled-back preview; confirm text follows the settings tick box); docs c55a2e2. HEAD c55a2e2. check.sh 3646 passed, 11 skipped (BUG-T5 repro left skipped for the tester's rewrite, plus 10 older skips); native suites all pass. Lead approved during the round: option A for one assertion in the 5,000-item export test.
- Deviations reported: tester-test edits beyond un-skipping (removed unused _repro helpers; option A assertion); T7 removes Kusunga's own leftover temp files; T8 and T6 applied to both default and profile folders; T2 also covers ignored apps; T9 accepts only the UTC form; three tester tests now describe only the decoder or store (timestamps). Worst case 90 s of "Deleting…" when the keychain hangs. In a debug profile the partial message's "can't be read any more" isn't true (shared key).
- Gates: developer pass · tester re-check started · reviewer — · QA — · PM merge —
- Open findings: T1–T9 fixed, waiting for the tester; BUG-T5 repro to be rewritten
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — lead answer on T5
- Changed: Developer reported the BUG-T5 repro can't pass under the lead's ruling (it expects the key to survive a late successful delete).
- Gates: developer fixing · tester open · reviewer — · QA — · PM merge —
- Open findings: 1 Medium (T5), 8 Low (being fixed)
- Decisions: none from the PM. Lead: option B — no write-back; a late successful key delete stands, because the user asked for it. After the time limit with the key still present, Kusunga waits; if the call never returns, capture stays stopped and the note "Kusunga couldn't confirm whether its key was deleted, so it has stopped recording and will now quit. Open Kusunga again. If your snippets and history are still there, try Delete everything again." shows with OK, which quits. The tester rewrites the T5 repro to this ruling after the developer's hand-off.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — tester round 1: 9 bugs
- Changed: Tester commits 542c1f9, 7c0e571, 1d009fb, 6a9cbc6: 120 tests (111 pass; 9 repros skipped unless KUSUNGA_REPRO=1). Abuse cases 11/11; UI states 11/11 automatable rows. check.sh 3578 passed, 19 skipped; native suites all pass.
- Findings: T5 Medium — a key delete abandoned after 30 s isn't cancelled; if it completes late, recording has resumed with the key gone, so the next launch can't read snippets or history. T7 Low — predictable export temp name written through a planted symlink. T8 Low — a profile folder that is itself a symlink has its target's contents deleted. T6 Low — an unlistable data folder after the key is gone reports "Everything is deleted." T1 Low — whitespace-only history accepted on import. T2 Low — lone surrogates accepted and stored as U+FFFD. T3 Low — typed_shortcuts_on 1.0/0.0 accepted. T9 Low — impossible dates roll over. T4 Low — import counts are file lines, not rows added. Observation: far-future last_copied_at sorts first and never expires.
- Gates: developer fixing · tester open (1 Medium, 8 Low) · reviewer — · QA — · PM merge —
- Open findings: 1 Medium (T5), 8 Low
- Decisions: none from the PM. Lead rulings: timestamps more than 24 h after the import time refuse the file; last_copied_at before created_at is stored with created_at set to last_copied_at. Escalation: the developer is re-dispatched on opus at xhigh.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — developer hand-off
- Changed: feat/your-data, 13 commits on accdfb3. Export/import (plain JSON, history only when ticked, four settings per G1, whole-file refusal, one-transaction merge, file times kept per G5, settings and ignored apps only when ticked); KeyStore.delete on Mac and Windows (a data profile's key store refuses); Delete all history = Clear history + VACUUM (Settings only); Delete everything (stop capture, key, close, log, files, login item off, quit; a debug profile deletes only its folder); Settings › Your data section; file_selector 1.1.0 added; Mac user-selected read-write entitlement; 11 new log codes. check.sh 3467 passed, 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed. Later line added by developer: import of exports over 20 MB.
- Deviations reported: key deleted before the database closes (accepted 2026-11-12); multi-number log codes split into single-number codes; import summary toast 8 s; CloseAtZero fix; VACUUM only from Settings; commit 69a76dd fails the zone guard alone (fixed in 9f47303).
- Unverified: no build run, so file_selector native parts not compiled; a real sandboxed save; real key deletion; VACUUM time at 5,000 items; Windows build (F5).
- Gates: developer pass · tester started · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — lead answers G6 and the delete order
- Changed: Developer raised G6 and a delete-order change.
- Gates: developer building · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: none from the PM. Lead: G6 A — a file left after Delete everything is handled by today's M1.2 path (moved aside as unreadable, banner once, removed by the next Clear history or Delete everything); the design note is corrected. Order accepted as a deviation: stop capture and timers, delete the key (restart them if it fails), close the database, then delete files; a test checks no copy is written between the key delete and the close.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data — lead answers to the developer's spec gaps
- Changed: Developer raised 5 spec gaps while building the key delete, Delete everything and the validator.
- Gates: developer building · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: none from the PM. Lead rulings within the approved design: G1 export history_limit, history_expiry_days, typed_shortcuts_on, paste_mode (never history_paused_until or picker_shortcut); G2 Import… disabled in memory-only, incompatible and backup-failed sessions, with a help line; G3 in a debug profile Delete everything leaves launch at login alone (it may share the real app's login item), D6 covered by unit tests and a PM step; G4 Import… button shows "Checking the file…", refusal as a toast; G5 imported history keeps the file's times, duplicates merge like Undo, items already past auto-delete are not added and are counted in the toast. Developer conventions accepted: 1,000-snippet cap fails the import; a rejected-profile session deletes nothing.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data: export and delete — deck approved, build starts
- Changed: The PM said: "the deck is empty" (2026-11-12). Cause: every deck hid its slides until its script ran, and the PM's viewer runs no scripts. Lead fixed all 8 decks (a9786f0) so slides show without scripts, and re-sent the M1.8 deck. Design note and UI spec marked approved; two Later lines added (password-protected export; import from other clipboard apps). Branch feat/your-data created from main. Developer briefed on opus (personal data, key deletion, several modules).
- Gates: developer started · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: PM said: "Approve as recommended" (2026-11-12), in answer to "Approve the M1.8 deck with the recommended options?". This decides D1 A (plain JSON export with a warning; approves the file_selector package and the Mac user-selected read-write entitlement), D2 A (history off by default), D3 A (import merges, never overwrites), D4 A (Delete all history = Clear history plus VACUUM, key kept), D5 A (settings and ignored apps exported; applied on import only if ticked), D6 A (after Delete everything: launch at login off, quit). The assumptions in the deck stand: lawful basis n/a, no ADR, size large.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.8 Your data: export and delete — design drafted, waiting for the PM
- Changed: PM said: "ok, proceed and start M1.8" (2026-11-12). Lead resized M1.8 from small to large (export moves personal data out of the encrypted file; import reads an untrusted file; Delete everything removes the keychain key, which no code does today). Scout lookup of main 914b75b: no file dialogs or file entitlement, no JSON code, KeyStore has no delete, Clear history keeps snippets, settings and key. Wrote docs/design/your-data.md, docs/ui/your-data.md and docs/slides/your-data.html. No branch and no developer brief yet.
- Gates: developer not started (waiting for deck approval) · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: open for the PM — D1 export encrypted? (rec. A, plain JSON with a warning; approves file_selector and the Mac user-selected file entitlement); D2 history in export by default (rec. A, off); D3 import (rec. A, merge, never overwrite); D4 Delete all history (rec. A, today's Clear history plus VACUUM, key kept); D5 settings and ignored apps in the export (rec. A, yes, applied on import only if ticked); D6 after Delete everything (rec. A, launch at login off and quit). Assumed unless the PM objects: lawful basis n/a; no ADR; the resize to large.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — approve the M1.8 deck and D1–D6; M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — main — pushed to GitHub
- Changed: main pushed to origin (github.com/Thamzy265/kusunga) 5170b08..c75b6c0 (149 commits: M1.5, M1.6, M1.7 and their docs). Only main pushed; no branch, no tag.
- Gates: n/a — push of already-merged work
- Open findings: none
- Decisions: PM said: "Push main" (2026-11-12), in answer to "Push main to GitHub now?".
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — merged to main (done)
- Changed: feat/settings-expiry merged into main with --no-ff as cdf7076 (44 commits). Checks on merged main, run one after another: check.sh "Formatted 260 files (0 changed)", "No issues found!", 3301 passed, 10 skipped ("All tests passed!"); test_mac_capture.sh 40/0; test_mac_shortcuts.sh 165/0; test_mac_shortcuts_release.sh 153/0; test_mac_login_item.sh 30/0; test_windows_policy.sh all passed ("all login item checks passed", "login_item_policy_edge_test: all passed"). M1.7 ticked in docs/PLAN.md. Not pushed.
- Gates: developer pass · tester pass · reviewer approve · QA pass · PM merge approved
- Open findings: none
- Decisions: PM said: "Approve the merge" (2026-11-12), in answer to "Approve merging M1.7 into main on this Mac (no push)?". No push: push needs the PM's approval at the time.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks (docs/qa/m1.md#pm-check-m17: launch at login on/off, needs approval, log-out with it on, no note on an installed build, VoiceOver); push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5 (Windows CI; M1.7 Windows bridge never compiled on Windows)

## 2026-11-12 — M1.7 Settings and expiry — QA session 2: pass; waiting for PM merge approval
- Changed: QA commit 400239d (docs/qa/m1.md "M1.7 session 2", 3 screenshots m1.7-s2-*.png) at e73b0d1, rebuilt Debug, qa profile. PASS: normal launch opens the window; Settings opened 5 times (incl. hide/show) shows the switch off with no note (QA-M17-1 re-verified); log has one loginItemFailed with no number (launch status read) and codes only; Auto-delete menu saves with no dialog; Tab order and focus rings unchanged; Privacy link works. qa profile left as found; Kusunga quit. Lead spot-checked m1.7-s2-settings-tab.png: no PM data. Branch: 44 commits ahead of main.
- Gates: developer pass · tester pass · reviewer approve · QA pass (AC1 and AC2 for what can be shown without the PM; launch at login on/off, needs approval, login start (D5), installed build, VoiceOver, 200% text, light mode and Windows not run) · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — merge approval; M1.7 PM checks (docs/qa/m1.md#pm-check-m17); push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — reviewer: approve; QA re-check
- Changed: Reviewer re-checked 9e29fcb..e73b0d1: P1, P2, N4 fixed (tests fail on the old lib); R4, "Where it was", TN2 and QA-M17-1 hold; log codes and numbers only. All six checks pass (check.sh 3301 passed, 10 skipped). Verdict: approve, no open finding. QA asked to re-check QA-M17-1 in the running app.
- Gates: developer pass · tester pass · reviewer approve · QA re-check running · PM merge —
- Open findings: none in code; QA-M17-1 waiting for QA
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — N4 fixed, reviewer re-check
- Changed: Developer fixed N4 in e73b0d1 (a notFound answer sets the last OS-reported position to off; still a failing read for logging). Tester's repro passes unedited. check.sh 3301 passed, 10 skipped; native suites all pass. Tester gate closed by the tester's repro passing unedited. Reviewer asked to re-check 9e29fcb..e73b0d1 (P1, P2, N4).
- Gates: developer pass · tester pass · reviewer re-check running · QA re-check after the reviewer · PM merge —
- Open findings: P1, P2, N4 fixed, waiting for the reviewer
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — tester re-check of P1, P2: 1 Low
- Changed: Tester added test/settings/login_item_last_position_test.dart (24 tests; 23 pass, 1 repro). Last-position memory, "Where it was", log counts and nine bad channel replies (all treated as errors, never notFound) hold. check.sh 3300 passed, 1 failed (the repro), 10 skipped; native suites all pass.
- Findings: N4 Low — a notFound plain read doesn't count as an OS report, so on → notFound (off) → error read flips the switch back on with no OS report in between.
- Gates: developer fixing N4 · tester open (1 Low) · reviewer — · QA — · PM merge —
- Open findings: 1 Low (N4)
- Decisions: none from the PM. Lead's ruling: a notFound answer counts as an OS report of off, so a later error or timeout read keeps off.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — P1, P2 fixed
- Changed: Developer fixed P1 and P2 in 3ad09ac (LoginItemAnswer gains a failure reason notFound / error / timeout; a plain read failing with an error or timeout keeps the last OS-reported position with no note; the first failing plain read in a row logs loginItemFailed, notFound included with no number). UI spec and design note updated. No tester test edited. check.sh 3277 passed, 10 skipped; native suites all pass.
- Gates: developer pass · tester re-check started · reviewer re-check after the tester · QA re-check after the reviewer · PM merge —
- Open findings: P1, P2 fixed, waiting for re-checks
- Decisions: none. Lead accepts that a notFound plain read is logged once per run of failures (it is a failing read; numbers only).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — reviewer: QA-M17-1 and TN2 fixed; P1, P2 Low
- Changed: Reviewer re-checked b4c4b16..9e29fcb: QA-M17-1 and TN2 fixed (tests fail on the old lib), "Where it was" holds. All six checks pass (check.sh 3264 passed, 10 skipped). Verdict: approve with notes.
- Findings: P1 Low (R4) — a plain read that fails with an error or timeout after the OS said on shows the switch off with no note, while the OS may still have it on (caused by the lead's QA-M17-1 ruling, which covered "notFound or an error"). P2 Low — a plain read that fails is not logged.
- Gates: developer fixing P1, P2 · tester pass · reviewer approve with notes · QA re-check pending · PM merge —
- Open findings: 2 Low (P1, P2)
- Decisions: none from the PM. Lead refines its own ruling of 2026-11-12: a plain read answering notFound shows off with no note; a plain read failing with an error or timeout keeps the last position the OS reported (off if there was none), with no note; the first failing plain read in a row logs loginItemFailed with its number. No new copy.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — TN2 fixed, reviewer re-check
- Changed: Developer fixed TN2 in 9e29fcb (keep the failed direction only when the re-read failed or differs from the request). The tester's two repros pass unedited; check.sh 3264 passed, 10 skipped; native suites all pass. Tester gate: closed by the tester's own repro tests passing unedited. Reviewer asked to re-check b4c4b16..9e29fcb (QA-M17-1 and TN2).
- Gates: developer pass · tester pass (repros pass) · reviewer re-check running · QA re-check after the reviewer · PM merge —
- Open findings: QA-M17-1 and TN2 fixed, waiting for the reviewer and QA
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — tester re-check of QA-M17-1: 1 new Medium
- Changed: Tester added test/settings/login_item_note_rule_test.dart (10 tests; 8 pass, 2 are repros). The note rule works for every case probed. check.sh 3262 passed, 2 failed (the repros), 10 skipped; native suites all pass.
- Findings: TN2 Medium (R4) — after a failed change whose re-read already shows what the user asked, the stale failed target is kept; a later plain failed read then shows the switch on with "Couldn't turn this off. Try again." although the OS last said off. Low twin for turn-on: a stale "Couldn't turn this on" note with no user action.
- Gates: developer fixing TN2 · tester open (1 Medium) · reviewer — · QA — · PM merge —
- Open findings: 1 Medium (TN2)
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — QA-M17-1 fixed
- Changed: Developer fixed QA-M17-1 in c8df41d per the lead's ruling: a plain status read answering notFound or an error shows off with no note; a failed user change keeps its note. UI spec and design note updated. Three of the developer's own earlier tests changed to get their note from a failed change; no tester test edited. check.sh 3251 passed, 10 skipped; native suites all pass.
- Gates: developer pass · tester re-check started · reviewer — (re-check after the tester) · QA re-check of the Settings screen after the reviewer · PM merge —
- Open findings: QA-M17-1 fixed, waiting for re-checks
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks; push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — QA session 1: 1 Minor finding
- Changed: QA commit b4c4b16 (docs/qa/m1.md "M1.7 Settings and expiry (2026-11-12)", 15 screenshots m1.7-*.png). Debug build, qa profile, label checked before every step and before the Delete. PASS: normal launch opens the window (first launch and relaunch; the visibleAtLaunch risk is clear); tabs History, Snippets, Privacy, Settings; History keeps title, count line and ⋯; Settings layout and copy; Launch at login off by default (AC2); migrated qa profile shows Never; longer/Never saves with no dialog; "After 1 day" dialog "200 older items will be deleted. Snippets aren't affected." with focus on Cancel; Cancel keeps Never; Delete → toast "200 items deleted", History and picker empty, both qa snippets kept, log historyExpired 200; setting survives relaunch; Tab order per spec; 2 px focus ring on the switch and menu; arrow keys move tabs; Privacy link focuses "Pause history"; shortcut change from Settings works and ⇧⌘V restored; no sideways scroll at 360 px; log codes only. Video qa-artifacts/m1.7/m1.7-auto-delete-flow.mp4 (git-ignored). Not run: "Change in Settings" banner (the Mac doesn't report a shortcut clash), a timed expiry with items on both sides, 200% text, light mode, VoiceOver, Windows. Not done (PM away): turning Launch at login on, log-out, System Settings. qa profile restored (auto-delete Never, ⇧⌘V); qa history emptied by the test; qa Kusunga quit. Lead spot-checked m1.7-settings-tab.png: no PM data.
- Findings: QA-M17-1 Minor — with Launch at login off and nothing touched, every opening of Settings shows "Couldn't turn this on. Try again." Likely SMAppService .notFound for the debug build run from the build folder, which the design maps to that note; no loginItemFailed logged.
- Gates: developer fixing QA-M17-1 · tester pass · reviewer approve · QA open (1 Minor) · PM merge —
- Open findings: 1 Minor (QA-M17-1)
- Decisions: none. Lead's spec ruling: a failure note shows only after a change the user asked for fails; a plain status read that returns notFound or an error shows the switch off with no note. The developer updates the UI spec and design note.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — M1.7 PM checks (login item on/off, needs approval, log-out with it on, QA-M17-1 on an installed build, VoiceOver); push of main; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-12 — M1.7 Settings and expiry — reviewer: approve; QA starts
- Changed: Reviewer re-checked 99d578d..34c60de: RN1 and RN2 fixed (tests fail on the old lib), F6 and F11 still hold. All six checks pass (check.sh 3248 passed, 10 skipped). Whole review: F1–F9, F11, F12, RN1, RN2 fixed; F10 no change needed. QA briefed (qa profile only; no real login item, no log-out, no System Settings change while the PM is away).
- Gates: developer pass · tester pass · reviewer approve · QA running · PM merge —
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — RN1 and RN2 fixed
- Changed: Developer fixed RN1 (22b646c: the minute check passes its reload to the clean-up run, so listeners hear it) and RN2 (34c60de: an unchanged run re-arms the history expiry timer through a cheap callback, reading the store only when the list must change). The two asserts edited in bc8ec16 restored; reviewer's probes pass unchanged. HEAD 34c60de. check.sh 3248 passed, 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed.
- Gates: developer pass · tester pass · reviewer re-check of RN1, RN2 started · QA — · PM merge —
- Open findings: RN1, RN2 fixed, waiting for the reviewer
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — PM away overnight
- Changed: none in code. Developer fixing RN1 and RN2.
- Gates: developer fixing RN1, RN2 · tester pass · reviewer approve with notes · QA — · PM merge —
- Open findings: 2 Low (RN1, RN2)
- Decisions: PM said: "am going to sleep, you can proceed" (2026-11-11). Lead reads this as: continue the gates (developer, reviewer re-check, QA in the qa profile). No merge, push or risk acceptance without the PM. QA will not turn on a real login item, log out, or change System Settings; those steps wait for the PM.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — reviewer re-check: approve with notes
- Changed: Reviewer re-reviewed 4ae5516..99d578d. F1–F9, F11, F12 fixed (each fix's tests fail on the old lib, checked in a scratch worktree); F10 no change needed (PM "Where it was"). F4 deviation (unknown setting shows Never, read again at each check) accepted provided RN1 is fixed; F5 in HistoryService accepted; LoginItemService refreshing on resume and show accepted. Shared close_at_zero and section_heading: no regression. Checks: first check.sh run had 1 speed-test failure (data_profile_slips_test 2M chars, 3292 ms vs 3000 ms; not changed on this branch; slow machine); passes alone and on the full rerun (3246 passed, 10 skipped); native suites all pass.
- Findings: RN1 Low — once a thrown setting read is finally read at the minute check, listeners aren't told if nothing is deleted, so the menu stays on Never and the expiry refresh timer isn't armed (from F11). RN2 Low — a clean-up that deletes nothing no longer re-arms the history's expiry timer, so after a wake an expiring item can stay visible up to 15 min (from F11); two older asserts were edited to fit. Both display only; paste is blocked. Reviewer recommends fixing both before merge.
- Gates: developer fixing RN1, RN2 · tester pass · reviewer approve with notes · QA — · PM merge —
- Open findings: 2 Low (RN1, RN2)
- Decisions: none. Lead: RN1 and RN2 are fixed before QA, as the reviewer recommends.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — developer fixes for reviewer round 1
- Changed: Developer fixed F1 (a008460, 2 px focus ring on the switch and the menu, widget and pixel tests light and dark), F2 (026c3ec), F3 (36c1db9), F4 (2a7366e), F5 (4e34294), F6 (5b1aeb5), F7 (395dc7c), F8 (03d7017), F9 (04682c9, "Change in Settings"), F10 (99d578d, docs and a turn-on twin test; no code change needed), F11 (bc8ec16), F12 (3c5245e, shared CloseAtZero and SectionHeading). HEAD 99d578d. check.sh 3246 passed, 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed. Lead corrected the same Ctrl+Tab line in the M1.6 spec docs/ui/sensitive-content.md on main.
- Deviations reported: F4 — while the setting can't be read, nothing is hidden or deleted and the menu shows Never; it is read again at each check and clean-up, and a time the user saves meanwhile becomes the setting. F5 fixed in HistoryService.countRemovedBy. F11 changed two of the developer's own tests to trigger a refresh by a copy. LoginItemService still refreshes on both resume and show.
- Gates: developer pass · tester pass · reviewer re-check started · QA — · PM merge —
- Open findings: F1–F12 fixed, waiting for the reviewer's re-check
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — PM decisions on the review round
- Changed: Developer dispatched for F1–F9, F11, F12 with the decisions below.
- Gates: developer fixing · tester pass · reviewer block (F1) · QA — · PM merge —
- Open findings: 1 Medium (F1), 9 Low (F2–F10), 2 cleanup
- Decisions: PM said: "Same developer (Recommended)" (2026-11-11), in answer to how the fixes go ahead (the developer stays on opus at xhigh). PM said: "Where it was (Recommended)" (2026-11-11), in answer to what the switch shows when a change fails and the read-back also fails: a failed turn-off stays on, a failed turn-on stays off, each with its "Couldn't turn this off/on. Try again." note (closes the open question and F10). PM said: "Add a link (Recommended)" (2026-11-11), in answer to whether the shortcut-taken warning in History links to Change: a text button "Change in Settings" that opens the Settings tab with focus on Change (F9).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — reviewer round 1: block (F1)
- Changed: Reviewer (Mode: branch, b6c66f5..4ae5516). All six checks pass (check.sh 3222 passed, 10 skipped). Extra: swiftc -typecheck of macos/Runner/*.swift for macOS 12.0 passed; clang++ -fsyntax-only -Wall -Wextra -Werror of login_item_bridge.cpp against the Flutter wrapper headers and a stub windows.h passed. Security review: 0 findings. Privacy: retention shorter, AC2 and D3 B defaults hold, R2 holds, secure_delete on, logs codes and numbers only.
- Findings: F1 Medium — the Launch at login switch and the Auto-delete menu have no visible focus ring (surfaceHover tint 1.12:1 light, 1.20:1 dark; WCAG 1.4.11; spec). F2 Low — the expiry refresh timer is not armed after launch, so an item can stay visible up to 15 min past its cutoff (paste is still blocked). F3 Low — a failing store read reschedules every 1 s, logging readFailed each time, and keeps the expired preview. F4 Low (privacy) — a thrown setting read makes auto-delete Never for the session, never retried. F5 Low — the Keep dialog counts expired hidden rows. F6 Low (privacy) — expired unsaved copies are written at the next flush. F7 Low — design note says older builds ignore the key (a v5 build in fact goes memory-only) and "two calls" (three). F8 Low — the UI spec says Ctrl+Tab cycles tabs; not built. F9 Low — the History shortcut-taken banner doesn't point to Change, now in Settings. F10 Low — turn-on twin of the open "both calls fail" question. F11, F12 cleanup.
- Gates: developer fixing · tester pass · reviewer block (F1) · QA — · PM merge —
- Open findings: 1 Medium (F1), 9 Low (F2–F10), 2 cleanup (F11, F12)
- Decisions: none. Lead: F8 — the spec is amended to match the app (tabs by Tab and arrow keys, as the M1.6 Privacy tab; no Ctrl+Tab in the main window today). F10 goes to the PM with the "both calls fail" question. F9 goes to the PM (new copy). Escalation: the developer is already on opus at xhigh; a third failed round goes to the PM.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — "both calls fail" rule (with F10); F9 link copy; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — N1 fixed, review starts
- Changed: Developer fixed N1 in 4ae5516: while a change runs, no earlier failure note shows; notes about the OS state (needs approval, Task Manager) stay. UI spec and design note updated. Tester's repro passes unedited. check.sh 3222 passed, 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed (run one after another).
- Gates: developer pass · tester pass (B1–B4 and N1 closed) · reviewer started (Mode: branch) · QA — · PM merge —
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the "both calls fail" switch behaviour; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — tester re-check: B1–B4 closed, 1 new Low
- Changed: Tester added 28 tests (test/settings/login_item_recheck_test.dart 18, test/history/expiry_stale_id_test.dart 14 on both stores); no production code changed. B1, B2, B3, B4 and the stale-id gap closed. check.sh 3219 passed, 1 failed (the N1 repro), 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed.
- Findings: N1 Low (cosmetic) — after a failed turn-off with an unreadable OS, a retry shows "Couldn't turn this on. Try again." while the turn-off call runs; it corrects itself when the call returns.
- Gates: developer fixing N1 · tester open (1 Low) · reviewer — · QA — · PM merge —
- Open findings: 1 Low (N1)
- Decisions: none. Lead: the fix goes back to the same developer (opus, xhigh); a further failed round goes to the PM as a blocker under the escalation rule.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the "both calls fail" switch behaviour; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — PM keeps the developer's three spec-gap choices
- Changed: none in code. Tester re-check of the round 1 fixes is running.
- Gates: developer pass · tester re-check running · reviewer — · QA — · PM merge —
- Open findings: B1–B4 fixed, waiting for the tester's re-check
- Decisions: PM said: "Keep all three" (2026-11-11), in answer to "Keep the developer's three choices for the spec gaps?". Scope: M1.7, feat/settings-expiry — (1) the shortcut-taken banner and the Mac permission card stay in the History tab, only the shortcut row moves to Settings; (2) the auto-delete dialog closes as Cancel if its count drops to 0 while open; (3) a memory-only session starts auto-delete at Never. Still open for the PM: when a turn-off fails and the read after it also fails, the switch stays on with "Couldn't turn this off. Try again.".
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the "both calls fail" switch behaviour; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — developer fixes for tester round 1
- Changed: Developer (opus, xhigh) fixed B3 (9a54252: read the OS again after a failed change; "Couldn't turn this off. Try again."), B4 (0dc004a: 2 s limit on every login-item call, late answers ignored), B1 (aa0a712: a good save resets the failure count), B2 (2fd8c63: dialog counts every item older than the new time), stale ids (9e5591f: textOf/copy honour the cutoff); docs e95d476 (UI spec and design note). Tester's tests not edited; the 4 repros pass. check.sh 3188 passed, 10 skipped; test_mac_capture 40; test_mac_shortcuts 165; test_mac_shortcuts_release 153; test_mac_login_item 30; test_windows_policy passed. Run one after another.
- Deviations reported: when a turn-off fails and the read after it also fails, the switch stays on with "Couldn't turn this off. Try again." (follows R4); the failure note shows only while the switch is not where the user asked or the read failed.
- Gates: developer pass · tester re-check started · reviewer — · QA — · PM merge —
- Open findings: B1–B4 fixed, waiting for the tester's re-check
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the developer's three spec-gap choices; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — tester round 1: 4 bugs
- Changed: Tester added about 150 tests (6 Dart files, 12 Swift tests in LoginItemCoreTests.swift, windows/runner/login_item_policy_edge_test.cpp) on feat/settings-expiry; no production code changed. New Dart tests fail on b6c66f5. check.sh 3153 passed, 4 failed (the repros below), 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item 30/0; test_windows_policy passed. Abuse cases 5/5; UI states 18/18 automatable rows. Gaps for QA: real SMAppService, registry and login start; VoiceOver; 300% text overflow at 320 px (beyond spec, not counted).
- Findings: B1 Low — choosing Never does not clear the "Couldn't remove old items" banner. B2 Low — the dialog count leaves out expired items not yet cleaned up, so the toast can say more items were deleted than the dialog said. B3 Medium — a failed turn-off shows the switch off while the OS may still have it on (R4), with "Couldn't turn this on" wording. B4 Low/Medium — the login-item channel has no timeout, so a native call that never answers locks the switch until restart. Also noted: textOf/copy still return an expired, not yet cleaned-up item by a stale id.
- Gates: developer fixing · tester open (4 findings) · reviewer — · QA — · PM merge —
- Open findings: 1 Medium (B3), 1 Low/Medium (B4), 2 Low (B1, B2)
- Decisions: none. Lead: per the escalation rule, the developer is dispatched again on opus at xhigh effort. Lead filled two small spec gaps in the UI spec on the branch: a failed turn-off note "Couldn't turn this off. Try again." and the existing 2 s native-call limit (M1.6) for login-item calls.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the developer's three spec-gap choices; push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — developer hand-off
- Changed: feat/settings-expiry, 9 commits on b6c66f5, HEAD c0bc0cf, 70 files, +4537/−219. Schema v6 (`history_expiry_days`: 30 new, 0 on upgrade); ExpiryService (read filter, clean-up at launch, every 15 min, on wake/clock jump, on resume, after a shorter time; 3-failure banner); Settings tab (Launch at login, Picker shortcut, Keep, Auto-delete with confirm dialog, Privacy link); launch at login on Mac (SMAppService, macOS 12 unsupported) and Windows (HKCU Run `--login`, StartupApproved read only); a login start opens no window. Checks run one at a time: check.sh 3038 passed, 10 skipped; test_mac_capture 40/0; test_mac_shortcuts 165/0; test_mac_shortcuts_release 153/0; test_mac_login_item (new) 18/0; test_windows_policy 9 programs passed. An earlier run failed 3 speed tests while the native suites ran in parallel; they pass alone. The developer was cut off once by a usage limit and resumed after the PM said: "Try again".
- Deviations reported: (1) third channel call `openLoginItemsSettings` (no arguments); (2) the shortcut-taken banner and the Mac permission card stay in History, only the shortcut row moved; (3) the auto-delete dialog closes as Cancel if its count drops to 0 while open (Clear history convention, PM 2026-11-08); (4) an invalid `history_expiry_days` is logged with the existing readFailed code; (5) a memory-only session starts at Never; (6) no new Ctrl+Tab, Settings joins the existing arrow-key cycling; (7) layout test widths raised to 880/840 px for the Ahem font, real-font test still checks 600 px; (8) commits 31fbe95 and cc97221 have two analyzer infos fixed in 65e115e.
- Unverified: whether macOS marks an SMAppService login launch with keyAELaunchedAsLogInItem (needs a real log-out and log-in); a normal launch with the window now hidden in the xib (never launched); the Windows bridge never compiled (F5).
- Gates: developer pass · tester started · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: none. For the PM: deviations 2, 3 and 5 answer spec gaps the developer raised.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — deviations 2, 3, 5 (questions); push of main; VoiceOver; optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-11 — M1.7 Settings and expiry — deck approved, build starts
- Changed: Design note and UI spec marked approved; decisions recorded in docs/PLAN.md; two Later lines added (auto-delete after 1 hour; auto-delete per app). Branch feat/settings-expiry created from main. Developer briefed on opus (personal-data retention, a schema change and several modules).
- Gates: developer started · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: PM said: "Approve as recommended" (2026-11-11), in answer to "Approve the M1.7 deck with the recommended options?". This decides D1 A (a new Settings tab, Keep and the picker shortcut moved there), D2 A (last copied time starts the clock), D3 B (30 days for new installs, Never for existing data), D4 B (macOS 12: switch disabled, "Needs macOS 13 or later"), D5 A (login start in the menu bar or tray only). The assumptions in the deck stand: lawful basis n/a, no ADR, size large.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver (M1.6 PM check 3, M1.5 items); optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-10 — M1.7 Settings and expiry — design drafted, waiting for the PM
- Changed: Lead resized M1.7 from small to large (personal-data retention; login items on Mac and Windows; controls move across tabs). Wrote docs/design/settings-and-expiry.md, docs/ui/settings-and-expiry.md and docs/slides/settings-and-expiry.html. Facts from a scout lookup of main: clip_items has created_at and last_copied_at; secure_delete is on; rollback journal, not WAL; snippets in their own table; no launch-at-login code; macOS target 12.0. No branch and no developer brief yet.
- Gates: developer not started (waiting for deck approval) · tester — · reviewer — · QA — · PM merge —
- Open findings: none
- Decisions: open for the PM — D1 where settings live (rec. A, a new Settings tab); D2 which time starts the clock (rec. A, last copied); D3 default auto-delete (rec. B, 30 days for new installs, Never for existing data); D4 login on macOS 12 (rec. B, disabled with a note); D5 window at login (rec. A, menu bar or tray only). Assumed unless the PM objects: lawful basis n/a; no ADR; the resize to large.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — approve the M1.7 deck and D1–D5; push of main; VoiceOver (M1.6 PM check 3, M1.5 items); optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5

## 2026-11-10 — M1.6 Sensitive-content protection — merged to main (done)
- Changed: feat/sensitive-content merged into main with --no-ff as 685eccf (50 commits). Checks on merged main: check.sh 2916 passed, 10 skipped ("All tests passed!"); test_mac_capture.sh 40/0; test_mac_shortcuts.sh 165/0; test_mac_shortcuts_release.sh 153/0; test_windows_policy.sh all 8 programs passed. M1.6 ticked in docs/PLAN.md. Not pushed.
- Gates: developer pass · tester pass · reviewer approve with notes · QA pass · PM merge approved
- Open findings: none
- Decisions: PM said: "Approve the merge" (2026-11-10), in answer to "Approve merging M1.6 into main on this Mac (no push)?". Later the PM said: "am going to sleep, carry on" (2026-11-10). No push: push needs the PM's approval at the time.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — push of main; VoiceOver (M1.6 PM check 3, M1.5 switch, status and chips); optional R5; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items; F5 (Windows CI billing)

## 2026-11-10 — M1.6 Sensitive-content protection — QA session 3: tray menu pass, AC1 and AC2 pass
- Changed: QA commit aee8825 (docs/qa/m1.md "M1.6 session 3 (tray menu)", AC2 row updated, 10 screenshots m1.6-s3-*.png). PM allowance used through two pid-bound helper commands (status item of the qa pid only; menu clicks only in windows owned by that pid); no permission prompt refused it; helper restored to Kusunga/TextEdit only afterwards. PASS: menu while not paused (Open picker, Open Kusunga, Pause history ▸ For 15 minutes / For 1 hour / Until I resume, Quit); tray "Until I resume" → "Resume history" in the menu, tooltip, paused icon, banner, Privacy tab, TextEdit copy not kept, log capturePaused -1; "Resume history" → copy kept; tray "For 15 minutes" → tooltip and banner "until 20:12", then resumed; tray pause survives a restart; log codes only. Video qa-artifacts/m1.6/m1.6-s3-tray-pause-resume.mp4 (git-ignored); restart video not recorded (ffmpeg hung), covered by screenshot and log. qa profile cleaned: Typed shortcuts Off, QA's TextEdit document closed, qa Kusunga quit, not paused. Lead spot-checked the tray screenshots: menu only, no PM data. Lead checked: no Kusunga, ffmpeg or log stream left.
- Gates: developer pass · tester pass · reviewer approve with notes · QA pass (AC1, AC2; VoiceOver, R5, 200% text, light mode, real password manager and Windows not run) · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — merge approval; optional R5; VoiceOver; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — PM allows QA to click Kusunga's menu-bar icon
- Changed: QA session 3 briefed for the tray menu check only.
- Gates: developer pass · tester pass · reviewer approve with notes · QA session 3 running (tray menu) · PM merge waiting
- Open findings: none
- Decisions: PM said: "Let QA click it" (2026-11-10), in answer to "Who checks the tray menu?" with the option "QA clicks it: you allow QA to click Kusunga's own menu-bar icon, and only that icon". Scope: clicks on the qa Kusunga's own status item and its menu items only, M1.6 QA, this session.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — optional R5; VoiceOver; the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — QA session 2: AC1 pass, AC2 partial (tray menu not run)
- Changed: QA commit 13874cd on the branch (docs/qa/m1.md "M1.6 session 2" + 17 screenshots in docs/qa/m1/screens/m1.6-s2-*.png). qa profile, label read before every step; no dialog. AC1 PASS: preset list incl. "Keeper (App Store)", TextEdit added → copy skipped (captureSkippedIgnoredApp), remove/Undo/remove, Restore preset list. AC2 PARTIAL: pause for 15 min / 1 h / until resumed from the Privacy tab, tooltip, paused icon, copies while paused not kept, resume, History banner (Resume before the list), pause survives a restart, a real 15-min pause ended on its own (captureResumed 1 at 18:23:56). NOT RUN: the tray menu itself (submenu, "Resume history") — it opens only on a real click on the status item; the request to widen QA's click guard was denied, so QA did not click it. Also not run: R5 (needs a System Settings change), a real password manager, empty list, 200% text, light mode, VoiceOver, Windows; the restart video was lost when the screen locked at about 18:24. Log check PASS: only codes and numbers, no app names or copied text. Keyboard order, 600 px and 360 px PASS. Videos (git-ignored): qa-artifacts/m1.6/m1.6-s2-ignored-app-copy-skipped.mp4, m1.6-s2-pause-resume.mp4. Lead spot-checked the History and restart screenshots: qa profile items only.
- Gates: developer pass · tester pass · reviewer approve with notes · QA partial — tray menu needs the PM (PM check 1) · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA — tray menu needs a real click on the status item (PM) · Marketer none · Lead none · PM — tray check (PM check 1 in docs/qa/m1.md); optional R5; VoiceOver; qa-profile clean-up (Typed shortcuts left On, TextEdit "Untitled 9" open); the banner for a failed Privacy-tab pause; the read-error pause behaviour; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — PM unlocked the Mac; QA session 2 started
- Changed: QA re-briefed with the same brief as session 1.
- Gates: developer pass · tester pass · reviewer approve with notes · QA running · PM merge waiting
- Open findings: none
- Decisions: PM said: "Unlocked, go ahead" (2026-11-10), in answer to "Can you unlock the Mac and leave it to QA for the run?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — QA session 1 blocked: screen locked
- Changed: QA built the debug app and launched it in the qa profile (log: dataProfileActive, permissionSnapshot 7, shortcutTableSize 2; no dialog). The screen was locked (CGSSessionScreenIsLocked 1, idle about 1,300 s), so screenshots failed and the "Test profile: qa" label could not be confirmed; QA clicked and typed nothing and stopped the qa instance with kill on its own pid. 0/2 criteria checked. No evidence committed; docs/qa/m1.md unchanged. The qa profile was migrated to schema v5; its settings were not changed. Lead checked: no Kusunga or log stream process left.
- Gates: developer pass · tester pass · reviewer approve with notes · QA blocked (screen locked) · PM merge waiting
- Open findings: none
- Decisions: none. QA: R5 (pause while a macOS "Ask" paste alert is up) cannot be reached without a System Settings change, so it will be NOT RUN unless the PM changes that setting themselves.
- Blockers: Developer none · Tester none · Reviewer none · QA — screen locked, needs the PM to unlock the Mac · Marketer none · Lead none · PM — unlock the Mac; the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — PM: Mac free for QA
- Changed: QA briefed on feat/sensitive-content at 66e8f53, test profile qa only.
- Gates: developer pass · tester pass · reviewer approve with notes · QA running · PM merge waiting
- Open findings: none
- Decisions: PM said: "Mac is free" (2026-11-10), in answer to "Can QA use your Mac now to run Kusunga in the test profile?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — reviewer: T1 and T2 closed, approval stands at 66e8f53
- Changed: Reviewer checked faffbc5..66e8f53 (bd5042a T1, 66e8f53 T2; test-only). Format 0 changed, analyze clean, both files "+104: All tests passed!". T1 traced against pause_service.dart: exactly 3 native calls, sharing really exercised. T2: absolute bound restores the "quickly" guard. Full check.sh not re-run by the reviewer (test-only; tester reports 2916 passed, 10 skipped at 66e8f53).
- Gates: developer pass · tester pass · reviewer approve with notes (stands at 66e8f53) · QA waiting for PM's OK to use the Mac · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — OK for QA to use the Mac; the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — tester fixes T1 and T2 (tests only)
- Changed: T1 (pause_service_timeout_edge_test.dart): the launch send fails first, the next call hangs, 20 ticks wait behind it, and exactly one shared send goes out after the timeout (3 native calls). Mutation check: with the sharing branch removed, Expected 3 Actual 22; restored. T2 (data_profile_slips_test.dart): the growth ratio stays, plus fastest-of-three 1 MB run under 2 s for each of the six lead characters; 5/5 runs under 8 CPU burners passed. check.sh 2916 passed, 0 failed, 10 skipped.
- Gates: developer pass · tester pass · reviewer approve with notes; confirmation of the T1/T2 commits requested · QA waiting for PM's OK to use the Mac · PM merge waiting
- Open findings: T1 and T2 fixed, pending reviewer confirmation
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — OK for QA to use the Mac; the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — reviewer verdict: approve with notes (faffbc5)
- Changed: Reviewer re-reviewed c75f8da..faffbc5 (tester 90963b1, developer faffbc5): approve with notes. check.sh 2916 passed, 10 skipped, format 0 changed, analyze clean. Fail-on-old-code: the dispose test fails with the c75f8da pause_service.dart (Expected <1> Actual <3>) and passes at faffbc5. Fix check: no caller left waiting, no listener or timer after dispose, no double complete, user path unchanged before dispose. Side effect noted, not a finding: a user pause that is the running call at quit is applied in native but not saved or shown in Dart; it ends at quit and errs toward privacy. Tester's 90963b1 tests sound, except T1. 0 code, design, security or privacy findings in the fix.
- Gates: developer pass · tester pass · reviewer approve with notes · QA not started (waiting for PM's OK to use the Mac) · PM merge waiting
- Open findings: T1 cleanup — pause_service_timeout_edge_test "20 ticks behind a stuck call add at most one call" passes with 0 sends, so it never exercises the sharing (covered elsewhere by pause_service_timeout_test.dart). T2 Low (test quality) — data_profile_slips_test "a megabyte of spaces or dashes..." no longer catches a uniformly slow linear parse; add a loose bound, e.g. fastest 1 MB run under 2 s. Lead: both go to the tester to fix (test-only), not skipped.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — OK for QA to use the Mac; the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer fix round 4 (P1)
- Changed: Developer commit faffbc5 (lib/history/pause_service.dart only): dispose drops every queued native call (caller gets false), accepts no new call, and a call already running finishes without changing state or notifying listeners. Failing run at 90963b1: tester's "dispose with calls running and queued..." Expected <1> Actual <3>; passes after the fix. check.sh 2916 passed, 10 skipped, format 0 changed, analyze clean. test_mac_capture.sh 40/0, test_mac_shortcuts.sh 165/0, test_mac_shortcuts_release.sh 153/0, test_windows_policy.sh 8/8.
- Gates: developer pass · tester pass (round 4) · reviewer re-check of faffbc5 requested · QA not started · PM merge waiting
- Open findings: P1 fixed, pending reviewer re-check
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — tester round 4 (fix round 3)
- Changed: Tester added 15 Dart tests in 90963b1 (test/history/pause_service_timeout_edge_test.dart, 8; test/privacy/apply_error_while_paused_edge_test.dart, 7): late answers after the timeout ignored, a late-applied user pause put right by the next tick, a user pause behind a stuck background call waits at most one timeout, 20 ticks behind a stuck call add at most one send, the waiting send reads state when it starts; one banner only, the error shown once and cleared by the next good pause or resume, no re-announcement on ticks, focus order tabs → banner Resume → rows, 360 px at 200% and 300% text without overflow. Timing rewrites (c47696f, a43227f, c75f8da) still guard what they did; the Release-build test is stricter; the megabyte-lead test no longer catches a linear but very slow build (the old 5 s budget did). Five runs of both files under 8 CPU burners: no failures. check.sh: format 0 changed, analyze clean, 2915 passed / 1 failed (P1) / 10 skipped. test_mac_capture.sh 40/0, test_mac_shortcuts.sh 165/0, test_mac_shortcuts_release.sh 153/0, test_windows_policy.sh 8/8. Abuse cases 6/6, UI states 8/8. E2E n/a — launching the app is not allowed for the tester.
- Gates: developer fix for P1 · tester round 4 done · reviewer re-check after P1 · QA not started · PM merge waiting
- Open findings: 1 Low — P1: PauseService.dispose does not stop the job queue; queued calls still reach native after dispose (expected 1, actual 3). No visible effect. Repro: pause_service_timeout_edge_test, "dispose with calls running and queued: no more native calls start...". Observation: with native fully stuck, a user's second call can wait two timeouts (4 s); not a bug.
- Decisions: none. Lead: P1 goes to the developer to fix (not skipped).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — reviewer verdict: approve
- Changed: Reviewer re-reviewed HEAD c75f8da: approve. check.sh 2900 passed, 10 skipped (working tree, which may include the tester's two uncommitted round-4 files). Fail-on-old-code shown for N2 and N1. Queue review: no stale send, starvation bounded by user clicks, a late answer is resolved by the next send, dispose is safe, the R1 resync holds, and load is still sent before listen. The rewritten timing tests still guard what they did; the Release test is stronger. 0 code, design, security or privacy findings.
- Gates: developer pass · tester round 4 running · reviewer approve · QA not started · PM merge waiting
- Open findings: none
- Decisions: none. Reviewer note for QA: try a pause while a macOS "Ask" paste alert is up (it may hold the main thread for more than 2 s; the safe direction)
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer fix round 3
- Changed: Developer fixed the pause-chain timeout (0289920: a native call with no answer in 2 s counts as failed (option b); an explicit job queue where a user call goes ahead of a waiting background send; at most one waiting background send; a late answer is ignored and native counts as unknown) and the hidden apply error (52c8597: "Couldn't apply the pause. Try again." also shows while paused, under the paused line in the Privacy tab and inside the paused History banner). Flaky timing tests fixed in test-only commits: c47696f (counts list reads), a43227f (growth ratio from 100k to 1M), c75f8da (picker work counted; the 50 ms target kept on the fastest of three runs, because it is the design's latency target). HEAD c75f8da, 5 new commits on the tester's a9fb684, no history rewritten. The tester's rewritten repros pass unchanged. Results: check.sh 2900 passed, 10 skipped; test_mac_capture.sh 40/0; test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh 8/8; flutter build macos --debug built. One sentence added to the design note's failure plan.
- Gates: developer pass · tester re-check to come · reviewer re-check to come · QA not started · PM merge waiting
- Open findings: none open in code
- Decisions: none
- Blockers: Developer none (Windows compile still F5) · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer blocker on the pause timeout, lead decision
- Changed: Developer raised a blocker. The tester's never-answers repro expects pause() to return true when every native call hangs, but the approved spec and existing tests say a failed native pause changes nothing and returns false. Options: (a) a timed-out user pause still applies in Dart, with the error shown; (b) a timeout counts as a failure and the repro changes. Lead chose (b): it keeps the approved UI spec ("native call failed: Couldn't apply the pause. Try again. under the buttons, buttons stay") and failure plan. Option (a) would change approved behaviour and need the PM. Tester asked to rewrite the repro: a stuck native call makes pause() return false with the apply error within a few seconds; once native answers, a new pause works; at most one queued background send. Developer continues with items 2 (error shown while paused) and 3 (flaky timing tests).
- Gates: developer fixes in progress · tester repro rewrite in progress · reviewer block · QA not started · PM merge waiting
- Open findings: N1 (timeout), N1-reviewer (hidden error), flaky timing tests
- Decisions: lead: option (b), inside the approved spec; no PM decision needed
- Blockers: Developer none now · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — reviewer re-check of fix round 2: block
- Changed: Reviewer re-reviewed 78597f1 (HEAD now ce308b4 with the tester's test commit). R1, R3 to R9 fixed; R2 partly fixed. Fail-on-old-code shown for R1 to R4. app_id.h read for compile problems; none found (not compiled). 0 security vulnerabilities; no new privacy issues. All 7 deviations judged acceptable. check.sh red at ce308b4 only because of the tester's never-answers repro; picker_search_test "under 50 ms a keystroke" also failed once under heavy load (passes alone).
- Gates: developer fixes needed · tester pass, findings open · reviewer block · QA not started · PM merge waiting
- Open findings: reviewer N2 = tester N1, Low: pause_service.dart _call/_send (210-238) has no timeout, so one native call that never answers blocks every later pause and resume, and the queue grows each tick; fix with a timeout that counts as a failure. Reviewer N1 Low (design drift): privacy_screen.dart:218 and history_screen.dart:1136-1140 hide the apply error while paused, so a failed launch send or a settings read error shows no error. Tester N2: flaky wall-clock tests (data_profile_slips_test; also picker_search_test seen by the reviewer)
- Decisions: none. Escalation: second failed round for the developer; the developer is already on opus at high effort, so the same agent continues. If this round fails again, the lead raises a blocker to the PM. To PM (reviewer's note): a database read error at launch now pauses history until the user resumes
- Blockers: Developer N1, N2, flaky tests · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; the read-error pause behaviour; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — tester round 3 (fix round 2)
- Changed: Tester added 33 tests (22 Dart, 1 Swift, about 12 C++ checks) in one test commit; no production code changed. R2 to R8 hold. The rewritten R7 guard is as strict as before; the tester closed one gap (app_id.h was outside the logging bans). The B2 tray retry is still proved: removing the `ticks` listener makes it fail. Results: check.sh (under heavy load) 2885 passing, 2 failing, 10 skipped; test_mac_capture.sh 40/0; test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh 8/8. The tester's note that the Swift edge file is not in RunnerTests is out of date (the lead checked project.pbxproj earlier).
- Gates: developer fixes needed (N1, N2) · tester pass, findings open · reviewer re-check running · QA not started · PM merge waiting
- Open findings: N1 Low-Medium: PauseService._send chains every native call with no timeout, so one call that never answers blocks every later pause and resume (repro "a native call that never answers: the user can still pause within a few seconds" fails). N2 flaky test: data_profile_slips_test wall-clock budgets (5000 ms and 50 ms) fail under machine load (1 in 5 runs alone; once in the full run)
- Decisions: none
- Blockers: Developer N1, N2 · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer fix round 2 (review findings)
- Changed: Developer (opus, high effort) fixed R1 (65c3c6b, native pause calls run one at a time; after a user pause or resume Dart re-sends its state if native differs), R2 (0816554, a launch, timer or re-send still out of step after a retry shows the apply error and retries on every tick; a settings read error at launch means paused until resume with the error), R3 (930b894, a superseded list retry is dropped), R4 (ab2327f, a list read failure at start sends the presets, not an empty list), R5 (8fd041d, the Mac source marker is read only when paste access is "Allow" or macOS is older than 15.4), R6 (c1cf303, Windows skips a paused copy before opening the clipboard), R7 (8bfa891, shared windows/runner/app_id.h), R8 (9125933, fd507d7, a tick notifies only on a visible change; the tray listens to a new `ticks` counter so the B2 retry still works; the shortcut .catchError stays because a tester test needs it). HEAD fd507d7, 9 commits after 5add2b7, two unpushed commits rewritten with --fixup/--autosquash so each commit passes alone. Results: check.sh 2860 passed, 10 skipped; test_mac_capture.sh 39/0; test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh 8/8; flutter build macos --debug built. One guard test changed for R7 (still as strict). Deviations: a user's own failed call still retries once (design failure plan); the launch/timer error stays until the user's next pause or resume; on Windows a paused, secret-marked copy now sends nothing instead of "concealed". The lead updated the design note's failure plan to match. The shared timing test data_profile_slips_test failed once on one commit under load and passed on re-run.
- Gates: developer pass · tester re-check to come · reviewer re-check to come · QA not started · PM merge waiting
- Open findings: none open in code (R1 to R8 marked fixed, R9 fixed by the lead)
- Decisions: none
- Blockers: Developer none (Windows compile still F5) · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — tester re-check of fix round 1
- Changed: Tester judged the developer's one-line change to the B1 repro correct (the first look's empty read is legitimate; it still fails on the old watcher). Added a stronger held-text Swift test (fails on the 284f5d9 watcher with "a held copy was sent after a pause") and 7 Dart tests for O2, O5 and O6 (6e2bd97, 5add2b7). B1 to B4 repros pass. check.sh 2837 passing, 0 failing, 10 skipped; test_mac_capture.sh 36/0; test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh all 7 pass. The tester's note that CaptureGateEdgeTests.swift is not in the RunnerTests target is out of date: the lead checked project.pbxproj, which has 4 entries for it (added by the developer in fix round 1).
- Gates: developer fixes needed (R1 to R8) · tester pass · reviewer block · QA not started · PM merge waiting
- Open findings: R1 Medium; R2 to R5 Low; R6 to R8 cleanup (see the reviewer entry)
- Decisions: none
- Blockers: Developer R1 to R8 · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — reviewer verdict: block
- Changed: Reviewer (opus, branch mode) reviewed HEAD 3828b74, with the tester's uncommitted edit to CaptureGateEdgeTests.swift in the run. check.sh 2830 passed, 10 skipped; test_mac_capture.sh 36/0; test_windows_policy.sh all 7 pass. Security review: 0 vulnerabilities. Privacy: no PII in logs, events, stored rows or gate fields. Windows code read for compile errors and API misuse, with none found (not compiled). Later lines ok. Lead fixed R9 on the branch (the plan said "ADR 0005 (proposed)").
- Gates: developer fixes needed · tester re-check running · reviewer block · QA not started · PM merge waiting
- Open findings: R1 Medium (privacy/correctness): pause_service.dart tick() can run while pause() or resume() awaits its native call, so native can end up unpaused while every UI says paused (copies read and sent to Dart, which drops them), or paused while the UI says recording. R2 Low: a failed native pause at launch shows no error; a settings read error at start silently drops "until I resume". R3 Low: the O2 retry resends an old list and can override a newer one. R4 Low: a read failure at start sends an empty ignore list. R5 Low: the Mac source-marker read may raise its own paste alert under "ask" (QA to check). R6 cleanup: Windows opens the clipboard while paused. R7 cleanup: duplicated exe-to-id code in clipboard_bridge.cpp and typed_shortcut_bridge.cpp. R8 cleanup: a dead .paused branch, a tick that notifies every 15 s, an unneeded catchError. R9 fixed by the lead.
- Decisions: none. Escalation: the developer failed a review round, so the developer is dispatched again on opus at high effort
- Blockers: Developer R1 to R8 · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner for a failed Privacy-tab pause; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer fix round 1
- Changed: Developer fixed B1 (5053144, the Mac watcher checks the pause against the wall clock before every read or send of a waiting copy), B2 (adac593, the tray state counts as shown only after every port call works), B3, O5 and O6 (c827fdc: "won't last" clears on a later good save; a tick retry keeps the error until the user's next pause or resume; announcements only on a user pause, user resume or timed end), B4 (6809e3a, History warning banner "Couldn't apply the pause. Try again.", hook history-pause-failed) and O2 (c632e0b, one retry, then new code-only log code captureIgnoredSendFailed, added to LogCode, DiagLog, the design note and the guard test). CaptureGateEdgeTests.swift added to the RunnerTests target only. Results: check.sh 2830 passed, 10 skipped; test_mac_capture.sh 35/0; test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh all pass; flutter build macos --debug built. The developer changed one line of the tester's B1 repro (it counted the first look's read, which happens before the pause); it still fails on the old code. Deviations: the History banner shows for any failed pause, not only one from the tray (Dart can't tell the source); no Dismiss button; one earlier developer test rewritten to follow the PM's O5 rule. O4: the M1.2 runner deletes the `.bak` once a migration succeeds (M1.2 design, dcae256); the lead corrected docs/design/sensitive-content.md and docs/design/typed-shortcuts.md to match (no code change).
- Gates: developer pass · tester re-check of the changed B1 repro to come · reviewer to be briefed · QA not started · PM merge waiting
- Open findings: none open in code; O1 and O3 fail open, as the design accepts
- Decisions: none. To PM: the banner also shows when a pause from the Privacy tab fails
- Blockers: Developer none (Windows compile still F5) · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the banner question above; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — tester report
- Changed: Tester added 99 Dart tests (9 files), 14 Swift XCTests (macos/RunnerTests/CaptureGateEdgeTests.swift, run by tool/test_mac_capture.sh) and a C++ check file (windows/runner/capture_gate_edge_test.cpp) on feat/sensitive-content, 8 test commits from 12c09a0. No production code changed. Fail-then-pass shown against 9eacb4d. Results: check.sh 2820 passing, 4 failing on purpose, 10 skipped; test_mac_capture.sh 34 tests, 1 failing on purpose (B1); test_mac_shortcuts.sh 165/0; release 153/0; test_windows_policy.sh all 7 pass. The developer's 680 px and 520×440 test changes hide no regression: with Roboto the three tabs and New snippet share one row at 600 px (Roboto is a proxy for SF and Segoe UI). Abuse cases 6/6 at logic level; UI states 8/8 rows (B4 fails).
- Gates: developer pass, fixes needed · tester pass (findings open) · reviewer, QA not started · PM merge waiting
- Open findings: B1 Medium (privacy): Mac ClipboardWatcher.swift:156-171 checks the gate once per copy, so a pause started during the text retry window (about 2 s) still reads and sends the text. B2 Low-Medium: tray_service.dart _update sets _shown before the port calls succeed, so a failed tray update is never retried. B3 Low: pause_service.dart _saveFailed is never cleared. B4 spec gap: the PM's failed-tray-pause History banner is not built. Observations O1 (fail-open start-up reads), O2 (failed setCaptureIgnored not retried or logged), O3 (Mac bundle-id match is case-sensitive), O4 (design note says the .bak stays; sqlite_history_store.dart:164 deletes it), O5 (a tick retry clears the error though the user's pause never applied), O6 (clock-back clamp can announce again). CaptureGateEdgeTests.swift is not in the Xcode RunnerTests target.
- Decisions: none
- Blockers: Developer — B1 to B4 · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — PM decisions on two spec gaps; tester briefed
- Changed: Tester briefed on feat/sensitive-content (abuse cases, states matrix, pause clock edges, start-up race, schema v5, privacy guard gaps, the 680 px and 520×440 test changes). UI spec updated on the branch: a failed tray pause shows "Couldn't apply the pause. Try again." in the History warning banner until the next pause or resume. The developer builds this with the tester's findings, so the tester's run is not disturbed.
- Gates: developer pass (banner change to come) · tester running · reviewer, QA not started · PM merge waiting
- Open findings: none yet
- Decisions: PM (2026-11-10), tray pause error place: "Banner in History (Recommended)". PM (2026-11-10), preset name: "Keeper (App Store) (Recommended)"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — developer hand-off
- Changed: Developer (opus) built M1.6 on feat/sensitive-content: 7 commits after 9eacb4d (5ff27c1, 53dd013, f45b640, 0b7d5b1, 2c9214d, 5f8a8fc, 284f5d9), 62 files, not pushed. Native capture skips on Mac (macos/Runner/CaptureSkipCore.swift) and Windows (windows/runner/capture_gate.h) check secret markers, then the pause, then the ignore list, before reading text. New channel calls setCaptureIgnored and setCapturePause; the text event gains no field; new events ignoredApp and (Windows) sourceUnknown carry only a type. PauseService owns history_paused_until (clamp to now + 60 min, 15 s tick, one retry). Schema v5 adds 12 verified preset rows with INSERT OR IGNORE. Tray: Pause history submenu, Resume history, tooltip and paused icon. Privacy tab, paused History banner, read-only chips with "Edit ignored apps" in the typed-shortcuts section. Developer results: check.sh 2723 passed, 10 skipped; test_mac_shortcuts.sh 165/0; test_mac_shortcuts_release.sh 153/0; new test_mac_capture.sh 20/0; test_windows_policy.sh all pass with the new capture_gate_test; flutter build macos --debug builds. CI guard test/ci/capture_skip_guards_test.dart. Failing runs recorded in the hand-off; capture_ignored_sync_test and ignored_apps_moved_test were not strictly test-first. Deviations: no native wake hook (native checks the wall clock on each copy; Later line); tray Pause/Resume appear only once the history has opened; paused copies send no event; the Mac marker value is read only when the type is present and the list is not empty; new preset name "Keeper (App Store)"; tests changed for the third tab ("600 px: still one row" now runs at 680 px; one History text-size test at 520×440); f45b640 alone fails flutter analyze (fixed in 2c9214d). 3 Later lines added (Safari companion apps; Windows MSIX package match for Keeper and Proton Pass; native wake hook). Unverified: Windows not compiled or run; Kusunga never launched; possible extra macOS paste prompt when reading the source marker under "Ask"; RunnerTests entries for CaptureGateTests.swift until CI.
- Gates: developer pass · tester to be briefed · reviewer, QA not started · PM merge waiting
- Open findings: none
- Decisions: none. To PM: the tray pause-error place in the History tab (spec gap); the "Keeper (App Store)" preset name
- Blockers: Developer none (Windows compile still needs CI or a Windows PC, F5) · Tester none · Reviewer none · QA none · Marketer none · Lead none · PM — the two spec gaps above; VoiceOver on the M1.5 switch, status and chips; M1.4 items

## 2026-11-10 — M1.6 Sensitive-content protection — design approved by PM
- Changed: PM approved the M1.6 deck (docs/slides/sensitive-content.html) with every recommendation. ADR 0005 accepted. Design note and UI spec marked approved; the plan's M1.6 AC now says "preset with common password managers"; 5 Later lines added. Developer to be briefed (opus — personal data, capture changes on two platforms, several modules).
- Gates: design approved · developer to be briefed · tester, reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-10): "Approve as recommended". This approves: option A, capture skips decided in native code before reading, the source app never leaves native code (ADR 0005); D1 A, one ignore list for history and typed shortcuts; D2 A, password-manager presets only, banking apps a Later line, AC wording changed; D3 A, a pause survives a restart; D4 A, a Privacy tab holds pause and the list; D5 A, on Mac the pasteboard source marker counts first, otherwise the front app; lawful basis n/a while nothing leaves the device (as plan D7); DPIA screening: no new trigger
- Blockers: PM — VoiceOver on the M1.5 switch, status and chips; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-10 — M1.6 Sensitive-content protection — design ready for PM
- Changed: Design note docs/design/sensitive-content.md, ADR 0005 (proposed: capture skips decided in native code before reading; the source app never leaves native code), UI spec docs/ui/sensitive-content.md, deck docs/slides/sensitive-content.html, on feat/sensitive-content. Recommended option A. Scope: ignore list stops capture (shared with typed shortcuts), new verified password-manager presets (schema v5), Pause history 15 min / 1 h / until resumed from the tray and a new Privacy tab, a History banner and tray tooltip while paused. Five Later lines proposed.
- Gates: design waiting for PM approval · developer not briefed · tester, reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: open for PM: D1 one list or two; D2 banking app presets (recommend password managers only, AC wording change); D3 pause survives restart; D4 Privacy tab; D5 Mac source marker; lawful basis (likely n/a); DPIA screening: no new trigger
- Blockers: PM — deck approval and D1-D5; VoiceOver on the M1.5 switch, status and chips; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-10 — M1.6 Sensitive-content protection — started
- Changed: PM said "Yes, start M1.6". Size: large — personal data (which apps the user copies from, a capture-pause state) and changes to clipboard capture on Mac and Windows. Branch feat/sensitive-content from main 5170b08. Lead is writing the design note, privacy section, UI spec and deck; the developer is not briefed until the PM approves the deck.
- Gates: design in progress · developer not briefed · tester, reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-10): "Yes, start M1.6"
- Blockers: PM — VoiceOver on the M1.5 switch, status and chips; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — merged to main and pushed
- Changed: feat/typed-shortcuts merged into main locally with `git merge --no-ff` (merge commit aa801d1). On merged main: ./tool/check.sh format, analyze and +2624 ~10 all tests passed; test_mac_shortcuts.sh 165, 0 failures; test_mac_shortcuts_release.sh 153, 0 failures; test_windows_policy.sh all passed. M1.5 ticked in docs/PLAN.md. main pushed to origin/main. The feat/typed-shortcuts branch is not pushed and not deleted.
- Gates: developer done · tester pass (round 7) · reviewer approve with notes · QA pass (session 2; card by widget tests, PM 2026-11-09; light-appearance ring by widget tests under the standing approval) · PM merge approved
- Open findings: none. Notes carried: N-R1 (M1.9 release-binary check), Windows native code never compiled (F5), OS-level Windows checks QA-only
- Decisions: merge and push under the PM's standing approval (2026-11-09): "You can merge and push, run recommended actions"
- Blockers: PM — VoiceOver on the M1.5 switch, status and chips; optional real-keyboard check; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — QA session 2: pass
- Changed: QA session 2 on 435d174 in the qa profile with the debug-only switch (log showed shortcutSyntheticKeysAllowed). Evidence cc80941 (docs/qa/m1.md "M1.5 session 2", 14 screenshots m1.5-s2-*); videos qa-artifacts/m1.5/m1.5-s2-{ac1-replace-timing,shift-held,two-quick,timing-10-trials}.mp4 and the filtered log (not committed). Pass: AC1 (`;email` replaced, "hello" back, ⌘V pastes "hello", qa history gains nothing over about 35 replacements); Shift held on the last key (software-held Shift; pasted once, no picker, no stray characters); two quick shortcuts delete only shortcut text; a click partway cancels; 6 s pause cancels, under 5 s fires; rich-text copy leaves the snippet (PM decision); AC2 password field in a local Safari test page (secure input, nothing typed or logged) and ignored app (shortcutSkippedIgnoredApp); AC3 switch Off does nothing; replacement median 17 ms, max 50 ms (target 150 ms); Secure Keyboard Entry pauses and recovers; log has codes only. QA-M15-1 fixed in dark (8.1:1). Not run: light appearance (needs System Settings), real keyboard without the switch (optional PM check), card (B2, accepted by PM), VoiceOver, password-manager auto-clear, Windows. Slip, no harm: 10 trial runs went to a windowless Terminal first; redone with TextEdit in front. Cleanup done.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA pass · PM merge approved (standing approval, 2026-11-09)
- Open findings: none
- Decisions: Under the PM's standing approval of 2026-11-09 ("You can merge and push, run recommended actions"), lead's recommendation taken: the focus ring in light appearance is covered by widget tests (tester round 7: light and dark, 3:1) and not checked on the real app, because switching appearance needs System Settings — scope: M1.5, QA-M15-1 light appearance — review: next QA session with light appearance available
- Blockers: PM — VoiceOver on the switch, status and chips; optional real-keyboard check; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — PM standing approval while away
- Changed: PM decision recorded. No code change. QA session 2 still running.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA in progress · PM merge: pre-approved below, used only after QA passes and every gate is green
- Open findings: none open
- Decisions: PM (2026-11-09), while the PM is asleep: "You can merge and push, run recommended actions". Lead's reading: once every gate (developer, tester, reviewer, QA) has passed, merge feat/typed-shortcuts into main locally with `git merge --no-ff` and push main; for any decision that comes up, take the lead's recommendation and log it here with this approval. Limits the lead keeps: no merge or push before QA passes; fix findings rather than skip them; no System Settings changes; standing QA rules unchanged
- Blockers: PM — VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — PM accepts widget tests for the explanation card (B2)
- Changed: PM decision recorded. No code change. QA session 2 still running.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA in progress (card checks covered by widget tests under the decision below) · PM merge n/a yet
- Open findings: none open
- Decisions: Risk accepted by PM (2026-11-09): accepted: the Mac explanation card "Turn on typed shortcuts?" (shown each time the switch is turned on without Input Monitoring; Not now and Esc turn the switch back off and return focus to the switch; Continue asks macOS once, then opens System Settings) is not checked on the real app, because Input Monitoring was already granted for the build, and is covered only by widget tests — scope: M1.5 Typed shortcuts, feat/typed-shortcuts, QA gate, card checks (B2) — expiry/review: none — PM said: "Accept the tests"
- Blockers: PM — VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — QA session 2 started
- Changed: PM freed the Mac. QA session 2 on feat/typed-shortcuts at 435d174 in the qa profile, launched with the debug-only switch (-KusungaAcceptSyntheticKeys YES): the real-typing checks blocked in session 1, plus a re-check of QA-M15-1. Standing QA rules repeated in the brief.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA in progress · PM merge n/a yet
- Open findings: none open
- Decisions: PM (2026-11-09): "Mac is free"
- Blockers: PM — B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — N-R2 done
- Changed: Developer added a "Swift typed-shortcut core tests, compiled as Release (no DEBUG)" step running ./tool/test_mac_shortcuts_release.sh to the macOS job in .github/workflows/check.yml (435d174). The workflow parses; flutter test test/ci +64; release core 153 pass. The step runs once CI runs (billing). No app code changed.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA session 2 waiting for the Mac · PM merge n/a yet
- Open findings: none open; N-R1 is an M1.9 task
- Decisions: none
- Blockers: PM — the Mac for QA session 2; B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — reviewer: approve with notes (focus ring, debug switch, guards)
- Changed: Reviewer reviewed 2436a5b..84e6c70. Checks pass (check.sh +2624 ~10; Debug core 165; release core 153; Windows policy). The switch can't reach a Release or Profile build or the real data by any checked-in path: DEBUG is set only in the Debug configuration, no checked-in xcconfig sets a Swift flag, every use is inside `#if DEBUG`, an -O compile without DEBUG has 0 strings and 0 symbols; when the switch is on, Dart runs the qa/dev profile or memory-only, never the real folder; it reads CommandLine.arguments only. ADR 0004 intact. QA-M15-1, G1, G2 fixed. BUG-H4 row count accepted as a trade-off.
- Gates: design approved · developer done · tester round 7 done · reviewer approve with notes · QA session 2 next (needs the Mac) · PM merge n/a yet
- Open findings: N-R1 Low — the git-ignored Local.xcconfig is included in all configurations; a DEBUG condition there plus a Release build would compile the switch in. Lead: dated plan task added to M1.9 (release-binary strings check and a Local.xcconfig.example guard; owner developer; due with M1.9, before the first beta). N-R2 Low — add tool/test_mac_shortcuts_release.sh to the macOS CI job; lead: developer adds it now; until CI runs (billing) the lead runs it at each gate
- Decisions: none
- Blockers: PM — the Mac for QA session 2; B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — developer fixed G1, G2 and the BUG-H4 flake
- Changed: Test-only commits. A shared classifier test/support/swift_conditional.dart is now used by the synthetic-keys guard, the data-profile guard (which had the same G1 hole) and the tester's edge tests. G1 (7269dc3): only a bare `#if DEBUG` counts. G2 (5635ab6): comments and string literals are blanked before directives are read (nested comments, multi-line strings; raw `#"..."#` strings not handled, none in the sources). The tester's repros now run as normal tests; failing runs first. BUG-H4 (84e6c70): counts HistoryRow builds instead of wall time (4991 plain / 5114 with copies on 4 runs; the assert is fewer than 3× rows); wall times still printed. It no longer catches a regression that only makes each row slower. ./tool/check.sh +2624 ~10; test_mac_shortcuts.sh 165; test_mac_shortcuts_release.sh 153; test_windows_policy.sh all pass.
- Gates: design approved · developer done · tester round 7 done (repros now pass) · reviewer re-check of 2436a5b..84e6c70 to be briefed · QA session 2 after that · PM merge n/a yet
- Open findings: none open
- Decisions: none
- Blockers: PM — B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — tester round 7 (focus ring, debug switch)
- Changed: Tester tested 2f79116 and 356be28 and added d4e801e (Swift edge tests, 2 Release-only Swift tests, Dart focus-ring and switch edge tests, and tool/test_mac_shortcuts_release.sh, which compiles the core without DEBUG). Mutation runs on the gates, the shipping bypass and the ring were caught. The gates stay off for the real profile and every look-alike profile, YES variant, `=` form, duplicate and order the tester tried; with the switch on, every other skip and reset rule still applies. Release-mode core: 153 tests pass, software keys always skipped, no "synthetic" state or type. Only the Debug configuration defines DEBUG. Focus ring: keyboard focus only, light and dark, reduce motion, 3:1, 360 px at 200% text, disabled, no size change. ./tool/check.sh 2621 passed, 12 skipped (second run); test_mac_shortcuts.sh 165; release script 153; test_windows_policy.sh all pass. No production code changed. BUG-H4 (M1.4 timing test) failed again on the first full run on a loaded machine and passed on re-runs.
- Gates: design approved · developer to fix G1, G2 and stabilise BUG-H4 · tester findings (round 7) · reviewer re-check after the fixes · QA session 2 after that · PM merge n/a yet
- Open findings: G1 Low — the source guard reads `#if DEBUG || true` as a DEBUG block, so a leak under it passes; G2 Low — a `#if DEBUG` line inside a block comment makes the guard treat the following code as DEBUG. BUG-H4 is flaky: it has failed twice on a loaded machine, so the check command isn't reliable
- Decisions: none
- Blockers: PM — B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — developer: focus ring and debug-only switch
- Changed: Developer fixed QA-M15-1 in 2f79116 (the switch gets the shared 2 px focus ring, outside the switch, keyboard focus only, light and dark; reduce motion unchanged) and added the PM's debug-only switch in 356be28: Mac only, all inside `#if DEBUG`; on only with both `-KusungaAcceptSyntheticKeys YES` and `-KusungaDataProfile qa|dev`, each once; bypasses only the D5 software-key rule; logs shortcutSyntheticKeysAllowed at tap start (added to LogCode, DiagLog, the design note and the CI guard); design note rule 4 records the exception. CI guard: the switch's symbols, argument and log call appear only inside `#if DEBUG`. The data-profile guard now also allows the profile name in TypedShortcutCore.swift inside `#if DEBUG`. Failing runs first. ./tool/check.sh +2601 ~10; test_mac_shortcuts.sh 155 (now compiled with -D DEBUG); test_windows_policy.sh all pass; Debug build ok. Release: not built in full (Release builds already fail on macOS 27 with Flutter 3.44.6, lipo, as in the plan); the core compiled without DEBUG shows 0 symbols and 0 strings for the switch.
- Gates: design approved (D5 debug-only exception, PM 2026-11-09) · developer done · tester re-check to be briefed · reviewer re-check after the tester · QA session 2 after that · PM merge n/a yet
- Open findings: none open
- Decisions: none
- Blockers: PM — B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — PM chooses a debug-only switch for QA typing
- Changed: PM decision recorded. Developer briefed: a launch option accepted only in Debug builds (compiled out of Release) and only with a qa or dev data profile, that lets the Mac typed-shortcut tap accept software-sent keys so QA can run the real-typing checks; logged with a code when active; guard tests that Release has no path to it. Mac only (QA has no Windows). Design note D5 to record the debug-only exception. Tester and reviewer check it before QA session 2.
- Gates: design approved (D5 debug-only exception) · developer in progress (QA-M15-1, debug switch) · tester and reviewer to re-check · QA blocked until then · PM merge n/a yet
- Open findings: QA-M15-1 Major (with the developer)
- Decisions: PM (2026-11-09), on how QA runs the real-typing checks (B1): a debug-only switch that accepts software-sent keys, instead of the PM typing. PM said: "Add a debug switch"
- Blockers: PM — B2 (accept widget tests for the card, or revoke Input Monitoring); VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — QA session 1 report
- Changed: QA (my-tech-team:qa, sonnet) ran session 1 on a3e3433 in the qa profile; evidence committed in 88fc219 (docs/qa/m1.md "M1.5 session 1", 28 screenshots m1.5-s1-*; one screenshot showing the PM's running apps was deleted, not committed). Videos qa-artifacts/m1.5/m1.5-s1-{editor-debounce,switch-card,ignore-list-undo}.mp4 and the filtered log (not committed). Pass: editor field, hint, placeholder, every live error and clash message with exact copy, tip, 32-character cap, about 0.6 s delay; C8; `;email` in monospace; picker row and search; section Off by default; Space toggles; Off hides status and chips and stops the tap; ignore list (toast and Undo, Undo at the end, two quick removals, Restore preset list, Add app "Added", Esc, no Cancel); Secure Keyboard Entry gives the Paused status; AX role, names, focus order; contrast 6.7:1 to 10:1; 360 px layout; log holds only codes. Not run: B1 — every key QA can send (7 methods, including CGEvent with pid forced to 0, IOHIDPostEvent, System Events) was skipped as software-sent (7 × shortcutSkippedInjected; D5 works as designed), so every real-typing check needs the PM's keyboard; B2 — Input Monitoring was already granted for this build (permissionSnapshot 7), so the card, Not now, Esc and "each time" were not seen on the real app (widget tests cover them). No dialog appeared; System Settings untouched. Cleanup done; the PM's Kusunga was not running.
- Gates: design approved · developer to fix QA-M15-1 · tester pass (round 6) · reviewer approve with notes · QA blocked (B1, B2) · PM merge n/a yet
- Open findings: QA-M15-1 Major — the Typed shortcuts switch focus indicator is a faint halo, about 1.25:1, below the 3:1 WCAG focus contrast (docs/qa/m1/screens/m1.5-s1-focus-switch.png). Spec gaps: QA's log show --last 30m returns nothing for info codes (QA used log stream instead; lead updates the step); after a Save fails on Name and Shortcut, focus goes to Name, the first error (lead: clarification, focus goes to the first field with an error in tab order)
- Decisions: none
- Blockers: QA — B1 real typing needs the PM's keyboard (or a debug-only switch accepting software keys, which weakens D5); B2 the card on the real app needs the PM to revoke Input Monitoring, or the PM accepts widget tests · PM — those two; VoiceOver; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — QA session 1 started
- Changed: PM freed the Mac. QA (my-tech-team:qa agent, sonnet) started on feat/typed-shortcuts at a3e3433 in the qa test profile. Steps that need no permission first; at the macOS Input Monitoring prompt QA stops and the PM grants it. Standing QA rules repeated in the brief.
- Gates: design approved · developer done · tester pass (round 6) · reviewer approve with notes · QA in progress · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-09): "Mac is free"
- Blockers: PM — Input Monitoring grant when QA reaches the prompt; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — PM keeps text-only restore
- Changed: PM decision recorded. Later line added on feat/typed-shortcuts: restore formatted copies after a typed shortcut, trigger ≥ 5 beta reports of losing a formatted copy. No code change.
- Gates: design approved · developer done · tester pass (round 6) · reviewer approve with notes · QA next (needs a free Mac and the PM's Input Monitoring grant) · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-09) on rich copies after a shortcut: keep the approved design — the previous copy is put back only when it was plain text (with privacy markers); otherwise the snippet stays on the clipboard. PM said: "Keep as designed"
- Blockers: PM — a free Mac and the Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — reviewer re-check (L3): approve with notes
- Changed: Reviewer re-checked 4fdfb3c..2436a5b. Checks pass (check.sh +2589 ~10; 151 XCTests; Windows policy suites). L3 confirmed fixed (OwnClear removed in a scratch copy, policy test failed). The Windows locked case (another app's clear, then Kusunga's clear, then SetClipboardData failing) is acceptable with no fix and no Later line: it needs a near out-of-memory failure at the same moment as a password manager's auto-clear, the text goes back with all three don't-keep marks, and the Mac has the same window in microseconds. Mac lastOwnClear set by the restore path is correct. Optional later hardening noted by the reviewer (read the sequence number while the previous text is read, then a "+1 since the read" rule once Windows runs).
- Gates: design approved · developer done · tester pass (round 6) · reviewer approve with notes · QA not started (needs the PM's Input Monitoring grant and the Mac) · PM merge n/a yet
- Open findings: none. Notes: Windows native code never compiled (F5); OS-level parts QA-only (N7); D2 restore rarely applies after rich copies
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format), before QA; Input Monitoring grant and a free Mac for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — tester round 6 (L3): pass
- Changed: Tester re-checked c0885a4 and added 2436a5b (5 Swift tests; 1 C++ function, about 50 assertions with a 15-combination loop). 6 mutation runs; one first went uncaught (ClipboardEmpty dropped on Windows), the tester added a partial-write case and it is now caught. The developer's edits to the tester's locks keep the tester's intent. Covered: each Mac condition (exactly +1, our clear, empty) is necessary; another app's clear alone, before or after ours; ownership without a sequence move; earlier restore none/valid/stale with each; Windows sequence wrap; Mac counter near Int.max (Int.max itself would trap, not reachable in practice); copy-only paths unchanged. Locked: on Windows, another app empties first and then Kusunga clears and its write fails: the text is written back (Windows has no exact-count rule). BUG-H4 passed this round. ./tool/check.sh 2589 passed, 10 skipped; test_mac_shortcuts.sh 151; test_windows_policy.sh all pass. No production code changed.
- Gates: design approved · developer done (L3) · tester pass (round 6) · reviewer re-check of c0885a4 to be briefed · QA not started · PM merge n/a yet
- Open findings: none. The Windows "another app emptied first, then our clear" lock goes to the reviewer to judge
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — developer fixed L3
- Changed: Developer fixed L3 in c0885a4: after a failed write the text goes back only onto Kusunga's own clear. Windows: sequence moved, ClipboardEmpty() and OwnClear() (GetClipboardOwner() == Kusunga's window). Mac: change count moved by exactly +1, clipboardIsEmpty() and lastChangeWasOwnClear() (the count Kusunga's clearContents returned is still current; added by the developer to also close "write failed before our clear, then another app cleared"). Design note step 2 updated. Failing run first (C++ 3 failed lines; Swift 7 failures). The tester's locks were changed as the lead asked ("any movement" is now +1 only; "indistinguishable" now expects no write-back; the C++ extra-moves block still restores when Kusunga owns the clipboard). ./tool/check.sh +2589 ~10 (one earlier full run failed on the M1.4 timing test history_scroll_round3_test BUG-H4 "End in 5,000 rows … no more than 3x as long", Expected < 59952, Actual 79404, on a loaded machine; the file passed alone and the full re-run passed); test_mac_shortcuts.sh 146; test_windows_policy.sh all pass; macOS debug build ok. Windows GetClipboardOwner behaviour not checked on a real machine.
- Gates: design approved · developer done (L3) · tester re-check of c0885a4 to be briefed · reviewer approve with notes, re-check after the tester · QA not started · PM merge n/a yet
- Open findings: none open. Note: the BUG-H4 timing test can fail on a loaded machine (flaky)
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — reviewer re-check (L2): approve with notes, L3
- Changed: Reviewer re-checked 6a47610..4fdfb3c. Checks pass (check.sh +2589 ~10; 143 XCTests; Windows policy suites). L2 confirmed fixed (mutation check failed as expected; on a private pasteboard clearContents leaves no types or items and moves the change count by exactly 1).
- Gates: design approved · developer to fix L3 · tester pass (round 5) · reviewer approve with notes · QA not started · PM merge n/a yet
- Open findings: L3 Low (privacy) — the remaining gap: another app that empties the clipboard (e.g. a password manager's EmptyClipboard auto-clear) during a failed write can't be told from Kusunga's clear, so the password comes back. The reviewer says privacy is never deferred, so fix now (or a PM decision). Fix: Windows also require GetClipboardOwner() == Kusunga's window; Mac require changeCount == before + 1. Lead: fix now (developer), no skip
- Decisions: none
- Blockers: Developer — L3 · PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-09 — M1.5 Typed shortcuts — tester round 5 (L2): pass
- Changed: Tester re-checked ef74f74 and added 4fdfb3c (6 Swift tests including a 12-case matrix; 1 C++ function, about 45 assertions). 6 mutation runs, each caught. The developer's edits to the tester's fakes and the N9 lock keep the tester's intent. Covered: earlier restore none/valid/stale against nothing moved, our clear, another app's write, clear then write; sequence wrap with and without an empty clipboard; emptiness checked after the write; copy-only paths unchanged. Locked as the accepted remaining gap: another app that empties the clipboard during the failed write can't be told apart from Kusunga's clear, so the text is written back over the empty clipboard. ./tool/check.sh 2589 passed, 10 skipped; test_mac_shortcuts.sh 143; test_windows_policy.sh all pass. No production code changed.
- Gates: design approved · developer done (L2) · tester pass (round 5) · reviewer re-check of ef74f74 to be briefed · QA not started · PM merge n/a yet
- Open findings: none. Remaining gap above goes to the reviewer
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer fixed L2
- Changed: Developer fixed L2 in ef74f74: after a failed snippet write the previous text goes back only if the change number moved AND the clipboard is empty now (Mac no types or items; Windows CountClipboardFormats() == 0); otherwise the other app's change wins, the text is forgotten, and an earlier waiting restore doesn't overwrite it. Design note step 2 updated. Failing run first (Swift 4 failures; C++ 3 failed lines). The tester's N9 lock was changed to the new behaviour (a user copy in the gap now wins), as the lead asked. ./tool/check.sh +2589 ~10; test_mac_shortcuts.sh 137; test_windows_policy.sh all pass; macOS debug build ok. Remaining gap: if another app empties the clipboard during the failed write, the text is still written back over the empty clipboard. Windows bridge not compiled.
- Gates: design approved · developer done (L2) · tester re-check of ef74f74 to be briefed · reviewer approve with notes, re-check after the tester · QA not started · PM merge n/a yet
- Open findings: none open; the remaining gap goes to the tester and reviewer to judge
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — reviewer re-check (L1): approve with notes, L2
- Changed: Reviewer re-checked 0968851..6a47610. Checks pass (check.sh +2589 ~10; 133 XCTests; Windows policy suites). L1 confirmed fixed (mutation check failed as expected). N8 accepted, no change (copy-only paths match M1.3; non-text copies are never saved under C4). N9 logged as L2.
- Gates: design approved · developer to fix L2 · tester pass (round 4) · reviewer approve with notes · QA not started · PM merge n/a yet
- Open findings: L2 Low (correctness and privacy) — the "change number moved" check can't tell Kusunga's own clear from another app's write; on Windows a failed OpenClipboard while another app (e.g. a password manager's auto-clear) changes the clipboard makes Kusunga write the old text, possibly a password, back over it. Fix: write back only if the clipboard is empty now. Lead: fix now (developer), no skip
- Decisions: none
- Blockers: Developer — L2 · PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — tester round 4 (L1): pass
- Changed: Tester re-checked f37243f and added 6a47610 (11 Swift tests, 1 C++ function with about 40 assertions). 8 mutation runs, each caught. Covered: sequence wrap 0xFFFFFFFF to 0; moves larger than 1; an earlier pending restore valid, stale or failing; privacy markers kept on the write-back; non-text previous clipboard; the copy-only paths unchanged. ./tool/check.sh 2589 passed, 10 skipped; test_mac_shortcuts.sh 133; test_windows_policy.sh all pass. No production code changed.
- Gates: design approved · developer done (L1) · tester pass (round 4) · reviewer re-check of f37243f to be briefed · QA not started · PM merge n/a yet
- Open findings: none. Notes: N8 on the copy-only paths and for a non-text previous clipboard nothing is saved, so a write that fails after the clear still loses the previous clipboard (pre-existing, same as M1.3); N9 a user copy during the few milliseconds of a failed write is overwritten by the saved text
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer fixed L1
- Changed: Developer fixed L1 in f37243f: before the snippet write the flow notes the clipboard change number (Mac change count, Windows sequence number); if the write fails and the number moved, the saved text is written back once with its privacy marks, then forgotten. Logic in the Swift core and C++ policy header; the shared M1.3 clipboard_bridge.cpp and the Mac bridge write are unchanged; design note step 2 has one added sentence. Failing run first (C++ 4 failed lines; Swift 5 tests, 6 failures). ./tool/check.sh +2589 ~10; test_mac_shortcuts.sh 121; test_windows_policy.sh all pass; macOS debug build ok. Not changed: copy-only paths (Mac without post permission, Windows modifiers held) read no previous text, as M1.3. Windows sequence-number behaviour on EmptyClipboard not checked on a real machine.
- Gates: design approved · developer done (L1) · tester re-check of f37243f to be briefed · reviewer approve with notes, re-check of f37243f after the tester · QA not started · PM merge n/a yet
- Open findings: none open
- Decisions: none
- Blockers: PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — reviewer re-check: approve with notes
- Changed: Reviewer re-checked ffecef4..0968851 read-only. Checks pass (check.sh +2589 ~10; 116 XCTests; Windows policy suites). R1, S1, C1-C9 confirmed fixed, several by reverting the fix in a scratch copy and seeing the test fail; C6 confirmed with a standalone build on a private pasteboard. ADR 0004 holds with matchId (a counter, nothing typed; guard pins the key sets). Developer deviations accepted by the reviewer. Later lines ok.
- Gates: design approved · developer round 3 done · tester pass (round 3) · reviewer approve with notes · QA not started · PM merge n/a yet
- Open findings: L1 Low (new) — the clipboard is cleared before the snippet write (Mac clearContents before writeObjects; Windows EmptyClipboard before SetClipboardData); if the write then fails, the user's previous clipboard text is lost. Lead: fix now (developer), no skip. Notes: the Windows code is still not compiled (F5); under C4 copies with rich formats (most browser and rich-editor copies) are not put back, so D2's restore mostly applies to plain-text and password-manager copies — to the PM; QA checks: Windows hook-health with touch/pen and an elevated window, UIA IsPassword in Chrome/Edge/Firefox on the first shortcut, Mac paste with Shift held, password-manager auto-clear after the restore
- Decisions: none
- Blockers: Developer — L1 · PM — rich copies (keep as designed or restore every format); Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — tester round 3: pass
- Changed: Tester re-checked ffecef4..bd4642d and added 0968851 (10 Dart, 16 Swift, 8 C++ functions with about 190 assertions). 15 mutation runs, each caught (timeout boundary, HookLooksRemoved boundary, restore marks, restorable formats, match-id wrap on both platforms, saved-text forget, idle deadline, pending restore on write failure); the guard test catches an extra key in matched (Swift, C++) and replace (Dart). Restore marks cover every IsSecret path (16 flag combinations) and the Mac kept markers equal secretTypes. Every C3 exit path clears the saved text. ./tool/check.sh 2589 passed, 10 skipped (8 baseline + T1, T1b); test_mac_shortcuts.sh 116; test_windows_policy.sh all pass. No production code changed. The report's line that U1, U2 and T2 repros still fail is out of date: those repros became normal passing tests in round 2 (skip count confirms).
- Gates: design approved · developer round 3 done · tester pass (round 3) · reviewer re-check to be briefed · QA not started · PM merge n/a yet
- Open findings: none new. Notes: N5 a second match during a Windows modifier wait is cancelled with the first (the user retypes); N6 a match while Dart waits for the previous replace is dropped; N7 the real hook thread, UIA worker, timers and Mac run-loop timer are testable only by QA on a real Mac and Windows
- Decisions: none
- Blockers: Developer — Windows not verified (CI Windows build needs GitHub billing, or a Windows PC) · PM — Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer round 3 fixed R1, S1, C1-C9
- Changed: Developer (opus, high) fixed every reviewer finding, one commit each: R1 e744aba (Windows hooks on their own thread with their own message loop; UIA on a long-lived worker with a cached object, over 100 ms counts as "can't tell"; hook health check every 2 s with reinstall, a failed reinstall reports "stopped" and Dart logs shortcutHookFailed; reinstall on window activation); S1 1706d2d (restored text always marked exclude-from-monitors, no history, no cloud); C1 bd4642d (wait up to 300 ms on a timer for held modifiers, else copy only); C2 a0215bf + design note 0b6651a (matchId counter in matched and replace, only the newest match can be replaced; CI guard allows exactly this one integer key); C3 71bad0b (write the snippet first, then delete; saved text cleared on every exit); C4 37deea5 (restore only if the previous clipboard was all text); C5 67f0c18 (a click after a match cancels); C6 f221558 (Mac writes snippet and markers as one item); C7 0ff9ac3; C8 3069cc6; C9 84f8745 (clear exactly 5 s after the last key). Failing runs are in the hand-off. ./tool/check.sh +2579 ~10; test_mac_shortcuts.sh 99, 0 failures; test_windows_policy.sh all pass; flutter build macos --debug builds. Deviations: when the snippet can't be written the answer is "failed" with no toast (nothing was copied; the code stays); held modifier key-downs on Windows don't count as typing after a match; a reinstalled hook isn't logged (no Windows native log, existing Later line); UIA connection and transaction timeouts set to 1 s; a second match during a replacement is dropped. Unverified: the Windows bridge is not compiled or run (hook thread, UIA worker, health heuristic, clipboard marks); the Mac bridge compiles but was not run; the C6 RunnerTests case runs only in CI.
- Gates: design approved (design note updated for R1, C1, C2, C3) · developer round 3 done · tester re-check to be briefed · reviewer re-check after the tester · QA not started · PM merge n/a yet
- Open findings: none open on the developer's side; reviewer to confirm R1, S1, C1-C9
- Decisions: none
- Blockers: Developer — Windows not verified (CI Windows build needs GitHub billing, or a Windows PC) · PM — Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — PM: Windows Add app list shows names only
- Changed: PM decided Q4. UI spec updated on feat/typed-shortcuts (Mac: name and icon; Windows: name only). Later line added: app icons in the Windows Add app list, trigger ≥ 5 beta requests. The code already sends names only on Windows (nullable icon, stub RunningAppIcon()). No code change.
- Gates: design approved (spec updated) · developer round 3 in progress (R1, S1, C1-C9) · reviewer block · QA not started · PM merge n/a yet
- Open findings: R1 High; S1, C1, C2 Medium; C3-C9 Low (all with the developer)
- Decisions: PM (2026-11-08) on Q4, Windows "Add app…" icons: "Names only for now"
- Blockers: Reviewer — R1 · PM — Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — PM accepts the 3 spec changes
- Changed: PM decision recorded. docs/ui/typed-shortcuts.md updated on feat/typed-shortcuts to match. No code change.
- Gates: design approved (spec updated) · developer round 3 in progress (R1, S1, C1-C9) · reviewer block · QA not started · PM merge n/a yet
- Open findings: R1 High; S1, C1, C2 Medium; C3-C9 Low (all with the developer)
- Decisions: PM (2026-11-08) accepted three changes to the approved UI spec: the Mac explanation card shows each time the switch is turned on without permission (spec said the first time); the Add app list has no Cancel button, Esc or a click outside closes it; Undo after removing an ignored app puts it back at the end of the list (Later line exists). PM said: "Accept all three"
- Blockers: Reviewer — R1 · PM — Q4 Windows icons; Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — reviewer: block
- Changed: Reviewer (opus, high) reviewed 2f79840..ffecef4 read-only. Checks pass (check.sh +2573 ~10; 79 XCTests; Windows policy suites). ADR 0004 holds: no typed character reaches Dart, a channel message, a log, a file or a crash path; buffer bound, reset events and every skip rule present; App Sandbox on, no Accessibility API; schema v4 expand-only with bound parameters. Later lines pass. Verdict: block on R1. The reviewer's process note (no M1.5 entries in status.md) is because the log lives on main; the entries are there (fface18, 92bf9ac, a070178, 76a2d64).
- Gates: design approved · developer round 3 to be briefed · tester done for round 2 · reviewer block · QA not started · PM merge n/a yet
- Open findings: R1 High — Windows LL hooks and the 100 ms UIA wait run on the platform thread that also runs Dart and the picker paste sleeps; Windows can silently remove the hook (status still "On") and input stalls machine-wide. S1 Medium (privacy) — Windows restore re-marks the previous clipboard only when it had ExcludeClipboardContentFromMonitorProcessing; a password marked only CanIncludeInClipboardHistory=0 or Clipboard Viewer Ignore comes back unmarked to Win+V history, Cloud Clipboard and other managers. C1 Medium — Windows Backspaces and Ctrl+V ignore held Shift/AltGr (Ctrl+Shift+V opens the picker; AltGr gives Ctrl+Alt+Backspace). C2 Medium — replace() doesn't say which match it answers; a quick second match can make the first replace delete text that isn't the shortcut (both platforms). C3 Low — code deleted before the clipboard write; a failed write loses the code, and on Windows the saved previous text is never cleared. C4 Low — restore puts back plain text even when the clipboard held other types (design says leave the snippet). C5 Low — a click after a match doesn't cancel the replacement. C6 Low — Mac writes the snippet before its privacy markers. C7 Low — "Starting…" can stay on screen. C8 Low — an invalid Save wipes the live clash message. C9 Low — buffer can live about 6 s (longer on Mac while a menu is open) vs the "5 seconds" copy.
- Decisions: none. Lead: all findings go to the developer; none is skipped. Escalation: the developer's work failed a review round, so the developer is dispatched again one effort level higher (opus, high)
- Blockers: Reviewer — R1 · PM — Q4 Windows icons; 3 spec deviations; Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — PM keeps the approved shortcut rules
- Changed: PM decision recorded. No code change. The T1 and T1b repros stay skipped. Later line added on feat/typed-shortcuts for N1-N3 (emoji, combining marks and decomposed accents; trigger: the first Windows QA run of M1.5, or ≥ 1 report of a shortcut deleting text it should not). T1 already has the developer's Later line (trigger: ≥ 3 beta reports).
- Gates: design approved · developer done (round 2) · tester findings U1, U2, T2 fixed · reviewer in progress · QA not started · PM merge n/a yet
- Open findings: none open for the developer
- Decisions: Risk accepted by PM (2026-11-08): accepted: T1 (a shortcut inside another one, not at its start, fires first, so the longer one can't be typed; the editor accepts both) and notes N1-N3 (Mac and Windows differ for canonically equal Unicode; delete counts differ for emoji and combining marks, so Windows may delete text before such a shortcut; a shortcut may start with a combining mark); the D1 rule stays as approved and emoji and combining marks stay allowed — scope: M1.5 Typed shortcuts, feat/typed-shortcuts, findings T1, N1, N2, N3 — expiry/review: the Later line triggers — PM said: "Keep as approved"
- Blockers: PM — Q4 Windows icons; 3 spec deviations; Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer fixed U1, U2, T2
- Changed: Developer fixed T2 (789424c: a lone surrogate is refused with the existing "Shortcuts can't have spaces or line breaks." copy), U1 (8ee34cc: chip names shrink and end with an ellipsis; Remove stays on screen; full name in the accessible name) and U2 (ffecef4: toasts in the section queue, so each removal keeps its Undo for 5 s; "Preset list restored" still replaces the current toast). The repros are now normal tests; failing runs on the old code: T2 "Expected: not null Actual: <null>", U1 "RenderFlex overflowed by 550 pixels", U1b "by 102 pixels", U2 "Found 0 widgets with text \"Bitwarden removed\"". ./tool/check.sh 2573 passed, 10 skipped (T1 and T1b repros stay skipped); test_mac_shortcuts.sh 79, 0 failures; test_windows_policy.sh all passed. Side effect: a second removal's toast waits until the first closes (up to 5 s). Shortcut rules and native matchers unchanged.
- Gates: design approved · developer done (round 2) · tester findings U1, U2, T2 fixed · reviewer to be briefed · QA not started · PM merge n/a yet
- Open findings: T1 low and notes N1-N3, waiting for the PM
- Decisions: none
- Blockers: PM — T1 and N1-N3 (widen the clash rule; refuse emoji and combining marks); Q4 Windows icons; 3 spec deviations; Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — tester report
- Changed: Tester (sonnet) added 133 tests in eab7e73, 78466a4, f1df693 (Swift 38, C++ 8 functions with about 380 assertions, Dart 52 + 6 skipped finding repros). Mutation runs showed the tests fail when reset keys, the 5 s idle clear, the Alt reset, the ignored-app skip or the per-character injected check are removed. ./tool/check.sh 2569 passed, 14 skipped (6 are finding repros, run with KUSUNGA_REPRO=1); test_mac_shortcuts.sh 79 pass; test_windows_policy.sh all pass. No production code changed; Kusunga not launched; xcodebuild test not run. Abuse cases 5/6 (remote desktop out of scope). UI states 13/17; real tap, hooks, UIA, secure input, clipboard and timing need QA.
- Gates: design approved · developer done · tester findings · reviewer, QA not started · PM merge n/a yet
- Open findings: U1 medium — ignored-app chips are not width-limited; a long name overflows at 360 px (550 px at 200% text) and its Remove button goes off screen. U2 low — removing a second app hides the first app's Undo toast. T1 low — a shortcut inside another (not at its start), e.g. "ma" and ";email": ";email" can never be typed; the editor accepts both (developer Later line exists). T2 low — a lone UTF-16 surrogate passes the check but is stored as U+FFFD. Notes: N1 Mac and Windows match canonically equal Unicode differently; N2 delete counts differ (Mac user-visible characters, Windows code points: ";👍🏽" Mac 2, Windows 3), so Windows may delete text before an emoji shortcut; N3 a shortcut starting with a combining mark is accepted.
- Decisions: none. U1, U2 and T2 go to the developer as spec bugs; T1 and N1-N3 go to the PM
- Blockers: PM — T1 and N1-N3; Q4 Windows icons; 3 spec deviations; Input Monitoring grant for QA; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer hand-off
- Changed: Developer handed off feat/typed-shortcuts at ebc7bd6 (11 commits after 2f79840, nothing pushed). Built: schema v4 (snippets.shortcut with CHECK and unique index, ignored_apps with Mac and Windows presets, typed_shortcuts_on = 0); editor Shortcut field with live checks and the spec's error copy; shortcut in list rows (new `mono` token), picker rows and search; native buffer, matcher and skip rules in Swift and C++; Mac listen-only tap after an Input Monitoring preflight; Windows WH_KEYBOARD_LL and WH_MOUSE_LL hooks with the IsPassword check (100 ms, fails closed); replacement with clipboard restore after 0.5 s, transient + concealed (Mac) or exclude-from-monitors (Windows), cancelled if the front app changed or a key came after the match; Typed shortcuts section (switch off by default, status live region, Mac card, ignored-app chips with Undo, Restore preset list, Add app…). Tests: ./tool/check.sh 2517 passed, 8 skipped (main 2374); ./tool/test_mac_shortcuts.sh 40 XCTests, 0 failures; ./tool/test_windows_policy.sh all passed. CI guards: channel API exact, `matched` carries only snippetId and deleteCount, no typed text in messages or logs, log codes match the design, App Sandbox on, no Accessibility API (mutation-checked). Failing runs are in the hand-off; in four places code was drafted first and set aside to capture the failing run. Not run: Kusunga was never launched (the real tap, macOS prompt, a real replacement, the 150 ms and under-1 ms targets); Windows code not compiled; `xcodebuild test` not run (RunnerTests project entries unverified until CI); source pid 0 for hardware keys is an assumption. Preset ids verified: com.1password.1password, org.keepassxc.keepassxc, com.apple.Passwords, com.bitwarden.desktop; not verified: com.agilebits.onepassword7 and all Windows exe names. Deviations from the spec: the Mac card shows every time the switch is turned on without permission (spec: the first time); the Add app list has no Cancel button (Esc or a click outside closes it); Undo puts a removed app back at the end of the list; Mac without post permission copies only and sends no Backspaces; delete count in user-visible characters on Mac, code points on Windows; Continue asks macOS once, then opens System Settings (UserDefaults flag KusungaAskedInputMonitoring). Safety additions: a key typed between match and replacement cancels it; a second shortcut within 0.5 s still restores the user's own text; the restored text keeps its privacy markers. Later lines added: Windows skip codes in the log; a shortcut inside another (not at its start); Undo order of ignored apps.
- Gates: design approved · developer done · tester to be briefed · reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: none new. Spec deviations above go to the PM
- Blockers: PM — Q4 Windows icons (Windows list shows names only until then); spec deviations above; Input Monitoring grant for QA (PM only); M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — developer questions
- Changed: Developer (opus) is building step 1 and asked 5 spec questions. Lead answered Q1, Q2, Q3 and Q5 as clarifications within the approved design: channel calls runningApps, requestListenAccess, openInputMonitoringSettings and the event statusChanged added (no typed text; design note updated); app names allowed only in runningApps and the encrypted ignored_apps table, never in logs or match events; preset rows seeded for both platforms, current platform shown; Swift core tested as a standalone xctest bundle, never `xcodebuild test` (it launches Kusunga on the real data). Q4 (Windows "Add app" icons) goes to the PM because it changes the approved UI spec.
- Gates: design approved · developer in progress · tester, reviewer, QA not started
- Open findings: none
- Decisions: none yet on Q4
- Blockers: PM — Q4 Windows icons; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item)

## 2026-11-08 — M1.5 Typed shortcuts — design approved by PM
- Changed: PM approved the M1.5 deck (docs/slides/typed-shortcuts.html) with every recommendation. ADR 0004 accepted. Design note and UI spec marked approved on feat/typed-shortcuts.
- Gates: design approved · developer to be briefed (opus, xhigh — data model change, personal data, several modules) · tester, reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-08): "Approve as recommended". This approves: option A, matching in native code (ADR 0004); D1 A, a shortcut fires as soon as its last character is typed and no shortcut may be the start of another; D2 A, the previous clipboard text is put back after 0.5 s; D3 A, typed shortcuts are off until the user turns them on; D4 A, the ignored-apps list is built now with password managers preset and M1.6 reuses it; D5 A, keys sent by other software are ignored; D6 A, the DPIA for keystroke watching goes into the M1.9 DPIA; lawful basis n/a while nothing leaves the device (as plan D7).
- Blockers: PM — M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item) · Lead — the plugin role agents are not loaded; roles run as subagents that load their my-tech-team skill, with the model and effort from the role table

## 2026-11-08 — M1.5 Typed shortcuts — design ready for PM
- Changed: PM said "Yes, start M1.5". Size: large — keyboard monitoring in every app, a new trust boundary, personal data, schema v4 and new native code on Mac and Windows. Branch feat/typed-shortcuts from main 8abfcf0. Design note docs/design/typed-shortcuts.md, ADR 0004 (proposed: matching in native code, typed keys never leave it), UI spec docs/ui/typed-shortcuts.md, deck docs/slides/typed-shortcuts.html. Recommended option A (native matcher).
- Gates: design waiting for PM approval · developer not briefed · tester, reviewer, QA not started · PM merge n/a yet
- Open findings: none
- Decisions: PM (2026-11-08): "Yes, start M1.5". Open for PM: D1 when a shortcut fires, D2 clipboard afterwards, D3 default on/off, D4 ignore list now, D5 keys from other software, D6 DPIA timing; lawful basis (likely n/a)
- Blockers: PM — deck approval and D1-D6; M1.4 items (VoiceOver, paste-access revoke, slip kinds, GitHub billing or local results, leftover qa-m13 link item) · Lead — the my-tech-team role agents are not available in this session right now; dispatch needs them back or a PM decision on how to run the roles

## 2026-11-08 — M1.4 Saved snippets — main pushed
- Changed: local main pushed to origin/main (from ee54f37), including the M1.4 merge 0d57b37. The feat/saved-snippets branch is not pushed and not deleted.
- Gates: developer done · tester pass · reviewer approve with notes · QA pass · PM merge approved
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM (2026-11-08) approved the push: "Yes, push main"
- Blockers: PM — VoiceOver sign-off; paste-access revoke with a dialog open; extra uncaught slip kinds; GitHub billing or acceptance of local results (Windows uncompiled); leftover qa-m13 link item

## 2026-11-08 — M1.4 Saved snippets — merged to main
- Changed: feat/saved-snippets merged into main locally with `git merge --no-ff` (merge commit 0d57b37, 99 branch commits). ./tool/check.sh on merged main: format, analyze and 2374 tests pass (8 skipped). M1.4 ticked in docs/PLAN.md. Nothing is pushed; origin/main is still at ee54f37.
- Gates: developer done · tester pass (round 18) · reviewer approve with notes · QA pass (3a, 3b, 4c by widget tests, PM 2026-11-08) · PM merge approved
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM (2026-11-08) approved the merge route: "Yes, merge locally"
- Blockers: PM — VoiceOver sign-off; paste-access revoke with a dialog open; extra uncaught slip kinds; GitHub billing or acceptance of local results (Windows uncompiled); leftover qa-m13 link item; push of local main

## 2026-11-08 — M1.4 Saved snippets — PM accepts widget tests for 3a, 3b, 4c
- Changed: PM decision recorded. No code change.
- Gates: developer done · tester pass (round 18) · reviewer approve with notes · QA pass (3a, 3b, 4c covered by widget tests under the PM decision below) · PM merge waiting
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: Risk accepted by PM (2026-11-08): accepted: QA checks 3a (Clear dialog closes itself at 0), 3b (Keep dialog "No items will be deleted." / "Set limit") and 4c (End, then open ⋯ at once) are not run on the real app and are covered only by widget tests (be09a77, 578ee22, b9632e7) — scope: M1.4 Saved snippets, feat/saved-snippets, QA gate for these 3 checks — expiry/review: none — PM said: "Yes, accept them"
- Blockers: PM — leftover qa-m13 link item; VoiceOver sign-off; paste-access revoke with a dialog open; extra uncaught slip kinds; GitHub billing or acceptance of local results; push of local main; merge route

## 2026-11-08 — M1.4 Saved snippets — QA session 6 report
- Changed: QA session 6 on b9632e7. The run stopped once on an API sign-in error (not an app fault) and was resumed. Pass: count wording (1 item / 2 items), live dialog counts, keyboard focus D1-D4 and F-M1, footer count, D5 picker over a dialog (Escape and paste paths), AC1-AC3 smoke. Not run on the real app: 3a (Clear dialog closes at 0) and 3b (Keep dialog "No items will be deleted.") because no path deletes items while a dialog is open; 4c (End then ⋯) because End scrolls ⋯ away. These rely on widget tests (be09a77, 578ee22). Re-verified QA-M14-7. Real-data cleanup: 76 qa-m13- items deleted one at a time, 440 -> 364, Keep 500, Clear history not used. One link item that contains "qa-m13" but does not start with it is left. The "after" search screenshot is not taken (Mac was in use); confirmed from the accessibility tree only. Test-profile slips only (stray snippet deleted, one bulk item deleted, copies trimmed by Keep 200). Evidence: docs/qa/m1.md "M1.4 session 6", 13 screenshots m1.4-s6-* (commit on feat/saved-snippets), videos qa-artifacts/m1.4/m1.4-s6-flow-*.mp4 (not committed).
- Gates: developer done · tester pass (round 18) · reviewer approve with notes · QA pass with 3 checks not run on the real app · PM merge waiting
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — accept widget tests for 3a/3b/4c or ask for a picker delete; leftover qa-m13 link item; VoiceOver sign-off; paste-access revoke with a dialog open; extra uncaught slip kinds; GitHub billing or acceptance of local results; push of local main; merge route

## 2026-11-08 — M1.4 Saved snippets — QA session 6 started
- Changed: PM freed the Mac. QA session 6 on b9632e7 started: count wording, live dialog counts, "Close or relabel" at 0, keyboard focus (D1-D4, F-M1), footer count, D5 picker-over-dialog manual check, AC1-AC3 smoke, and the qa-m13-* cleanup in the real data under the 2026-11-08 decision. Standing QA rules repeated in the brief.
- Gates: developer done · tester pass (round 18) · reviewer approve with notes · QA session 6 in progress · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM (2026-11-08): "Mac is free"
- Blockers: PM — VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Reviewer re-check: approve with notes (F-M1 closed); waiting for the Mac
- Changed: reviewer re-checked 432131d..b9632e7: approve with notes, 0 new findings. F-M1 fixed (df38af8): _focusMore uses the public traversalDescendants API, so the fix no longer depends on PopupMenuButton's private structure; nothing else in lib/ changed. check.sh +2374 ~8 passed (reviewer ran it). Developer, tester and reviewer gates are done for every change since QA session 5. Next: QA session 6 on b9632e7 (wording, live dialog counts, unknown count, count-of-0 close/relabel, focus return and no reach-through behind dialogs, footer count, D5 picker-over-dialog manual check, qa-m13-* cleanup).
- Gates: developer done · tester pass (round 18) · reviewer approve with notes · QA session 6 pending (needs the Mac) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for QA session 6; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Tester round 18: F-M1 fix holds; reviewer re-check started
- Changed: tester round 18 on 432131d..df38af8 (b9632e7, tests only): 10 tests in test/ui/dialog_focus_more_target_test.dart; focus lands on the visible, traversable "More options" button after every Clear close path and menu dismissal, also with the setup card shown and at 0 items (button never disabled or absent; empty traversal list is a safe no-op). Mutation check: the guard and the new file fail on the wrap, the parent, or no focus call; the new file also catches a skipTraversal target. Old target behaves the same today, so no fail-then-pass. Round 17 file still green. No bugs. check.sh +2374 ~8 passed. Reviewer re-check of 432131d..b9632e7 started.
- Gates: developer done · tester pass (round 18) · reviewer re-check in progress · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — F-M1 fixed; tester round 18 started
- Changed: developer fixed F-M1 in df38af8: _focusMore now focuses the first of _moreWrap.traversalDescendants (the Tab-reachable node of the visible More options button) instead of _moreWrap.children.first; PopupMenuButton kept so nothing visible changes. New guard test fails if the return target is not that node (mutation run failed as expected). check.sh +2364 ~8 ×2. Tester round 18 on 432131d..df38af8 started.
- Gates: developer done · tester round 18 in progress · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Reviewer re-check: approve with notes; F-M1 (Low) to the developer
- Changed: reviewer re-checked 0f55781..432131d: approve with notes. No path takes focus from behind a dialog or menu; BUG-D1 to D4 fixed (61c8cf3, 578ee22); PM's "Close or relabel" built as recorded (be09a77); auto-close sound (listens only while mounted, closes once, in-memory count, removeRoute when another route is on top); dropped D3 requests leave no state; focus return matches docs/ui/clipboard-history.md; Tab-out trade-off accepted (WCAG 2.4.3). D5 no_change_needed. check.sh +2363 ~8 passed (reviewer ran it). New: F-M1 (Low) — _focusMore relies on PopupMenuButton's private focus node being the first child of _moreWrap; a Flutter change could make the focus return silently do nothing (fails safe). F-M1 sent to the developer.
- Gates: developer in progress (F-M1) · tester pass (round 17) · reviewer approve with notes · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: F-M1 (Low); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Tester round 17: D2-D4 fixes hold; reviewer re-check started
- Changed: tester round 17 on 60b557b..578ee22 (432131d, tests only): about 79 tests in test/ui/dialog_focus_return_edge_test.dart, 31 fail on 60b557b, 0 on HEAD. Focus returns to the opener on every open/close path over five "meanwhile" events (none, copy, burst, first row deleted, setup card); More menu dismissal; Tab-out gives no trap or loop; dropped D3 requests leave no hold and later End/Home/text-size work; _moreWrap adds no Tab stop or semantics node; nested dialogs keep focus; screen removed while a return is pending is safe. No new bugs. Picker-over-dialog observation (D5) not reproduced in 9 widget-test combinations; if real it predates this branch (M1.3) and is low; QA to check manually. check.sh +2363 ~8 passed. Reviewer re-check of 0f55781..432131d started.
- Gates: developer done · tester pass (round 17) · reviewer re-check in progress · QA re-run pending (needs the Mac; includes the D5 manual check and the qa-m13-* cleanup) · PM merge waiting
- Open findings: none open; D5 unconfirmed; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — BUG-D2, D3, D4 fixed; tester round 17 started
- Changed: developer (fable) fixed D2, D3, D4 in 578ee22 with one shared rule, canTakeFocus(context) in lib/ui/focus_order.dart (autofocus only while the route is current), used by the History rows, the Mac setup card heading and the picker permission card heading (D4). D3: pending scroll-and-focus requests are dropped (not resumed) when another route is current. D2 (spec docs/ui/clipboard-history.md line 72): on Cancel, Escape, confirm or auto-close, focus returns to the opener — Keep field for the Keep dialog, More options for Clear history; the More menu dismissed by Escape or a click outside also returns to More options. Six round-16 repros un-skipped unchanged; failing run 26 failures; check.sh +2311 ~8 ×2. Trade-off: a Tab-out commit that opens the Keep dialog returns focus to the field, so the user presses Tab again. New observation (outside the brief): pressing the picker shortcut while a dialog is open on the manage window lets the picker panel take focus; when it closes, focus lands on the route scope and Escape no longer closes that dialog. Tester round 17 on 60b557b..578ee22 started, including this observation. The developer's "How to verify" step 8 (revoke paste access in System Settings) is PM-only, not for QA.
- Gates: developer done · tester round 17 in progress · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open (D2-D4 fixed, pending test); picker-over-dialog focus observation to triage; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Tester round 16: BUG-D1 holds; BUG-D2, D3, D4 found
- Changed: tester round 16 on cbf47de..61c8cf3 (60b557b, tests only): 29 tests pass, 6 skipped repros; 15 fail on cbf47de. BUG-D1 fixed for the History rows on every entry path (mouse, Enter in the field, keyboard from the menu) through copies, deletes, bursts, 0/1/unknown toggles; original newest-row autofocus intact; picker search keeps focus. The developer's changes to the tester's 3 tests are correct and not weakened. check.sh +2284 ~14 passed. New: BUG-D4 (medium-high) — the Mac setup card heading (autofocus, history_screen.dart ~1086) takes focus out of an open dialog when paste access flips to "needs setup"; the picker permission card (picker_settings_section.dart:318) has the same pattern (not reproduced). BUG-D3 (low) — End pressed in a long list then the More menu opened in the same frame: a row takes focus from the open menu. BUG-D2 (low-medium, accessibility) — focus after a dialog closes does not return to the control that opened it and varies by path (against docs/ui/clipboard-history.md line 72). All three sent to the developer (fable).
- Gates: developer in progress (D2, D3, D4) · tester round 16 fail (D2-D4) · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: BUG-D4 (medium-high), BUG-D2 (low-medium), BUG-D3 (low); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — BUG-D1 fixed (fable); tester round 16 started
- Changed: escalated developer (fable, xhigh) fixed BUG-D1 in 61c8cf3. Cause: the first History row has autofocus (since 160afec); Enter in the Keep field unfocuses with the scope disposition, so the History route scope has no focused child; a count change makes a new first row, whose autofocus is granted although a dialog holds the route on top. Not the dialog rebuild. Clear history is affected the same way when opened after an Enter in the field. Fix: rows ask for autofocus only while the History route is current (ModalRoute.isCurrentOf). Focus lands: "Delete N items" → "Set limit" keeps focus; Delete disabled while focused → Cancel. 3 of the tester's 4 skipped tests needed assertion changes (explained in the commit). Failing run 8 failures ("Actual: 'row …'", "a row behind the dialog was deleted with the keyboard"); check.sh +2255 ~8 ×2. Notes: after the Keep dialog opened by Enter closes, focus does not return to the field (pre-existing; docs/ui/clipboard-history.md line 72 says Esc returns focus to the opener); two other autofocus widgets (Mac setup card heading in HistoryScreen; picker settings permission card in lib/picker/ui/picker_settings_section.dart) could in theory fire behind a modal. Tester round 16 on cbf47de..61c8cf3 started.
- Gates: developer done · tester round 16 in progress · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open (BUG-D1 fixed, pending test); spec gap: focus return after the Keep dialog opened by Enter; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — PM decision: QA removes the qa-m13-* items
- Changed: PM asked whether QA should also remove the old synthetic qa-m13-* test items (e.g. qa-m13-a5-timing-*) from the PM's real history; the 2026-11-06 cleanup exception covered qa-m14-* only. QA will remove them in the next QA session, one at a time, under the same rules as the qa-m14-* cleanup (only items whose text starts with "qa-m13-"; no Clear history; Keep stays 500; record counts before and after).
- Gates: developer in progress (BUG-D1, fable) · tester round 15 fail (BUG-D1) · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: BUG-D1 (high); N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM decision (2026-11-08): cleanup of qa-m13-* items from the real history — question: "Should QA also remove the old qa-m13 test items from your real history?" — PM said: "Yes, remove them"
- Blockers: PM — free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Tester round 15: BUG-D1 (high) in the Keep dialog; developer escalated
- Changed: tester round 15 on 0f55781..be09a77 (cbf47de, tests only): 18 tests pass, 4 skipped (BUG-D1 repro and 3 keyboard "Set limit" tests it blocks); 11 fail on 0f55781. Clear history auto-close holds (bursts, other paths, same-frame copy, Escape/Enter in the frame, dialog or menu on top, screen removed, no listener leaks, never closes on failed read or save, keyboard focus same as Cancel). Keep toggles 0/1/unknown agree. The 5 updated tests still test the right thing. New: BUG-D1 (high, keyboard and data; not the Windows "D1" item) — with the Keep dialog open, a count change rebuilds the dialog and focus leaves it: Escape and Enter stop working, Tab walks the History rows behind the modal, and Tab, Tab, Tab, Enter deleted a row behind the dialog. Mouse not affected. Present since 2020e85 (BUG-W1 fix); Clear dialog not affected. check.sh +2246 ~12 passed. Escalation: second failure on the dialog work by the developer already on opus xhigh, so the developer is dispatched on fable (xhigh).
- Gates: developer in progress (BUG-D1, escalated to fable) · tester round 15 fail (BUG-D1) · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: BUG-D1 (high); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; whether QA removes the qa-m13-* items; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — Count-of-0 change built; tester round 15 started
- Changed: developer built the PM's "Close or relabel" decision in be09a77 (lib/history/ui/history_screen.dart): Clear history dialog closes itself with Cancel's result when the in-memory count reaches 0 (never on a failed read or save; keeps the last count while closing; focus returns where Cancel puts it; close logic lives in a widget inside the dialog so no listener is left behind). Keep dialog at a known 0: "Keep only the newest N items? No items will be deleted." with "Set limit" (enabled, sets the limit, deletes nothing; screen-reader label matches); back to "Delete R item(s)" when the count rises; W2 unknown-count path unchanged. 6 existing tests updated to the new behaviour, 3 new; failing run +26 -8; check.sh +2228 ~8 ×2. Risk noted by developer: if another route is on top of the Clear dialog at 0, the dialog is removed with Cancel's result rather than popped (not reached by tests). Tester round 15 on 0f55781..be09a77 started.
- Gates: developer done · tester round 15 in progress · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none new
- Blockers: PM — free the Mac for the QA re-run; whether QA removes the qa-m13-* items; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-08 — M1.4 Saved snippets — PM decision: dialogs at a count of 0
- Changed: PM chose the dialog behaviour when nothing is left to delete. Options put to the PM: "Close or relabel" (the Clear history dialog closes by itself at 0; the Keep dialog's button at 0 changes from "Delete 0 items" to a non-delete label such as "Set limit") or "Keep as is". Developer briefed: Clear history dialog closes itself when the live count reaches 0; Keep dialog at a known count of 0 says "Keep only the newest N items? No items will be deleted." with the button "Set limit"; unknown count (W2) unchanged.
- Gates: developer in progress (count-of-0 change) · tester pending · reviewer pending · QA re-run pending (needs the Mac) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: PM decision (2026-11-08): dialogs at a count of 0 — PM said: "Close or relabel"
- Blockers: PM — free the Mac for the QA re-run; whether QA removes the qa-m13-* items; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; push of local main

## 2026-11-06 — M1.4 Saved snippets — Reviewer re-check: approve with notes (W2 fixed)
- Changed: reviewer re-checked b1d966d..0f55781: approve with notes, 0 new findings. W2 fixed (a0ba96d) and the limit_field opening-count case fixed in the same commit; every caller handles a null count; setLimit has one caller, only after the dialog or when nothing is removed; clear() only after the Clear dialog. Tester notes judged acceptable: no Retry button (polish, PM may ask); limit cannot be lowered while reads fail (safe direction). check.sh +2225 ~8 passed (reviewer ran it).
- Gates: developer done · tester pass (round 14) · reviewer approve with notes · QA re-run needed for changes since cc231ff (wording, live dialog count, unknown count, footer count on the real app) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0 (before the QA re-run); free the Mac for the QA re-run; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; whether to remove the qa-m13-* items from real history; push of local main

## 2026-11-06 — M1.4 Saved snippets — Tester round 14: W2 fix holds; reviewer re-check started
- Changed: tester round 14 on b1d966d..a0ba96d (0f55781, tests only): 21 tests, 12 fail on b1d966d. Fail/ok cycles, failure at open then recovery, keyboard and screen reader on the disabled Delete, confirm in the frame of a failure, write failing at confirm (nothing half done), closed history, every limit-field commit path, Clear history with failing stores (count from the in-memory list, no 0 fallback), guard on callers of countRemovedBy. The helper change still tests the same thing. No bugs. check.sh +2225 ~8 passed. Notes: "Try again" has no retry button (if the store recovers with no change, the user must Cancel and reopen); while reads keep failing the limit cannot be lowered at all (safe). Reviewer re-check of b1d966d..0f55781 started.
- Gates: developer done · tester pass (round 14) · reviewer re-check in progress · QA pass (session 5), footer real-app check open · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; whether to remove the qa-m13-* items from real history; push of local main

## 2026-11-06 — M1.4 Saved snippets — W2 fixed; tester round 14 started
- Changed: developer fixed W2 in a0ba96d: countRemovedBy returns null (unknown) on a failed read or closed history, never 0; while unknown the Keep dialog shows "Couldn't count the items. Try again." with Delete disabled (only Cancel works) and a good read brings the count back; an unknown count when lowering Keep still opens the dialog; raising the limit no longer reads the count. New strings: "Couldn't count the items. Try again." and a disabled "Delete". Zone scan also flags Future.delayed and Stream.periodic. One tester helper changed to find the Delete button inside the AlertDialog. Failing run +1 -3; check.sh +2204 ~8 ×2. Count-of-0 behaviour unchanged. Tester round 14 on b1d966d..a0ba96d started.
- Gates: developer done · tester round 14 in progress · reviewer re-check pending · QA pass (session 5), footer real-app check open · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; whether to remove the qa-m13-* items from real history; push of local main

## 2026-11-06 — M1.4 Saved snippets — Reviewer re-check: approve with notes; W2 (Low) to the developer
- Changed: reviewer re-checked cc231ff..b1d966d: approve with notes. QA-M14-7 fixed (d6cea52, 9f0e719); BUG-W1 fixed (2020e85; ListenableBuilder owns the listener, no leak, confirm deletes what the dialog states at frame granularity); BUG-F1 no_change_needed (conclusion sound); zone guard sound as a tripwire (false positives only; optional: add Future.delayed and Stream.periodic to the scan). check.sh +2200 ~8 passed. New: W2 (Low) — history_screen.dart:654 with history_service.dart:364-370: countRemovedBy returns 0 when the store read fails, so a live Keep dialog can switch to "Delete 0 items" while confirm still trims the real number; related pre-existing case limit_field.dart:88-89 skips the dialog when the opening count read fails. Privacy note: history-tab-order-tabs shows older synthetic qa-m13-a5-timing-* items still in the PM's real history (cleanup exception covers qa-m14-* only). W2 sent to the developer.
- Gates: developer in progress (W2) · tester pass (round 13) · reviewer approve with notes · QA pass (session 5), footer real-app check open · PM merge waiting
- Open findings: W2 (Low); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; whether to remove the qa-m13-* items from real history; push of local main (decisions not on origin/main)

## 2026-11-06 — M1.4 Saved snippets — Tester round 13: BUG-F1 withdrawn; reviewer re-check started
- Changed: tester round 13 (b1d966d, tests only) agrees with no_change_needed for BUG-F1 and withdraws it as an app bug: reproduced the freeze with the original setUp, confirmed the zone cause with a direct probe, and found no path in the real app that creates the timer outside the root zone (no runZoned, Zone fork, Isolate or compute in lib/; FFI is synchronous; platform-channel callbacks run in the root zone). No hollow tests: every footer assertion read and checked; a temporary zone log over the full suite was removed (git diff empty). New test/ci/zone_assumption_test.dart (3 tests): the trap shown both ways, a lib scan for zones and isolates, and a list of lib files allowed to create a Timer. check.sh +2200 ~8 passed. Reviewer re-check of cc231ff..b1d966d started.
- Gates: developer done · tester pass (round 13) · reviewer re-check in progress · QA pass (session 5), footer real-app check open · PM merge waiting
- Open findings: none open (BUG-F1 withdrawn); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4

## 2026-11-06 — M1.4 Saved snippets — BUG-F1 disputed by the developer (test setup, not app)
- Changed: developer traced BUG-F1: the tester's setUp creates the HistoryService outside the test's fake-time zone, so the footer's 2-second throttle timer is created in the real zone and never fires under tester.pump; the footer stays held. Evidence: trace (hold armed, no timer fired), 2.1 s of real time releases it, and the same steps with the service created inside the test follow every copy ("8 of 200 items"). lib/ has no custom zones. List names and the Snippets footer follow. No app change; 61b699f (tests only): corrected repro un-skipped, new test/history/ui/footer_follows_count_test.dart (14 tests). check.sh +2197 ~8 ×2. Developer option, not built: create the throttle timer in the screen's own zone so such tests behave like the app. Finding status: disputed → no_change_needed, pending the tester's agreement; real-app check by QA open.
- Gates: developer done · tester confirming the F1 dispute · reviewer re-check pending · QA pass (session 5), footer real-app check open · PM merge waiting
- Open findings: BUG-F1 disputed; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4

## 2026-11-06 — M1.4 Saved snippets — Tester round 12: W1 fix holds; BUG-F1 found (pre-existing)
- Changed: tester round 12 on 0432721..2020e85 (cbacd96, tests only): 20 tests (19 pass, 1 skipped repro); 11 fail on 0432721. Clear history and Keep dialogs follow the live count through copies, bursts of 50, deletes down to 0, toggles 1/2, crossing the limit; the click deletes what the dialog states; Cancel keeps everything; no listener leaks after 15 open/close rounds or screen removal. check.sh +2182 ~9 passed. New: BUG-F1 (medium, pre-existing, also on 707f131 and e0cbdfe) — the History footer ("N of L items", the polite status line screen readers announce) stops following the count after 2 changes and stays stale; cause not found by the tester; skipped repro "BUG-F1 (pre-existing, found here): the History footer keeps following the count". Tester's view on the dialogs at a count of 0: option 2 (close Clear at 0; Keep button says a non-delete label at 0). BUG-F1 sent to the developer; dialog-at-0 question to the PM.
- Gates: developer in progress (BUG-F1) · tester pass (round 12) · reviewer re-check pending · QA pass (session 5) · PM merge waiting
- Open findings: BUG-F1 (medium); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — dialog text at a count of 0; VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4

## 2026-11-06 — M1.4 Saved snippets — BUG-W1 fixed; tester round 12 started
- Changed: developer fixed BUG-W1 in 2020e85 (live text: while the Clear history or Keep dialog is open, its text and button label follow the live count; confirm already acts on the live state). Failing run before the fix +57 -3; check.sh +2163 ~8 ×2. If the count drops to 0 while a dialog is open (only when an item is deleted elsewhere), the dialog stays open and says "0 older items will be deleted." / "Delete 0 items" or "This deletes all 0 items."; confirm deletes nothing. Developer notes this reads oddly; closing the dialog instead would be a PM wording or behaviour call. Tester round 12 on 0432721..2020e85 started.
- Gates: developer done · tester round 12 in progress · reviewer re-check pending · QA pass (session 5) · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; dialog text at a count of 0 (keep or close the dialog)

## 2026-11-06 — M1.4 Saved snippets — QA-M14-7 fixed; tester round 11: pass with 1 low bug
- Changed: developer fixed QA-M14-7 in d6cea52 and 9f0e719 (count of 1 takes the singular in History and Snippets strings; Clear history with one item says "This deletes the 1 item. Snippets are not affected."). Tester round 11 on e061fce..9f0e719 (0432721, tests only): 48 tests + 1 skipped repro; 8 fail on e061fce (the count-of-1 cases). Keep dialog, Clear history dialog, list names, footers, picker and time labels right at 0, 1, 2, 10, 11 and 1,000; tray menu has no counts. check.sh +2159 ~9 passed. New: BUG-W1 (low) — the Clear history and Keep dialog text is fixed when the dialog opens; a copy that arrives while it is open makes the count wrong ("the 1 item" when 2 are deleted). Note: no thousands separator ("1000 snippets"); left as is. BUG-W1 sent to the developer.
- Gates: developer in progress (BUG-W1) · tester pass (round 11) · reviewer re-check pending · QA pass (session 5) · PM merge waiting
- Open findings: BUG-W1 (low); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text to check
- Decisions: none
- Blockers: PM — VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4

## 2026-11-06 — M1.4 Saved snippets — QA session 5: pass; cleanup done
- Changed: QA session 5 on cc231ff (Debug, app CDHash 3f480ddce08cea236227b43ed0f9e5388c920317, App.framework 27d97311fc0e7e6418217d99bffc432738d5ccc9, signed Apple Development (redacted)); evidence docs/qa/m1.md "M1.4 session 5", 16 screenshots, commit e061fce. AC1, AC2, AC3 pass (smoke, test profile). QA-M14-5, QA-M14-6 now pass; T1, K1 (5/5), H7 pass on the real app; T2 and History text-size are widget tests only (no allowed text-size setting). Label checked before every delete step. Cleanup under the PM's "QA removes them": real history 444 → 427 (qa-m14-s4-01..17), snippets 11 → 0, picker search "qa-m14" finds nothing, Keep 500, Clear history not used. New: QA-M14-7 (Minor, wording from M1.2): "1 older items", "Delete 1 items"; developer fixing. QA mis-clicks with no visible effect: one on the PM's Chrome window, one in the Claude app transcript, one Save as snippet discarded; QA's click helper now refuses clicks outside Kusunga and TextEdit.
- Gates: developer in progress (QA-M14-7) · tester pass · reviewer approve with notes · QA pass (session 5) · PM merge waiting
- Open findings: QA-M14-7 (Minor); N1, N2, F5 (Windows), R1 unchanged; VoiceOver: stale "moved to position" text in the AX tree to check
- Decisions: none
- Blockers: PM — VoiceOver sign-off; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4

## 2026-11-06 — M1.4 Saved snippets — Reviewer re-check: approve with notes
- Changed: reviewer re-checked 2750eb5..cc231ff: approve with notes, 0 new findings. QA-M14-5, -6, BUG-T1, T2, T3, K1 fixed. Focus order holds no state; the text-size hold is always released; no new banner text in Release; repaint change cost small. check.sh +2103 ~8 passed.
- Gates: developer done · tester pass · reviewer approve with notes · QA re-run pending (needs the PM's Mac free) · PM merge waiting
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 10 passed; reviewer re-check started
- Changed: tester round 10 on a4c06a0..a1e3e55 (cc231ff, tests only): 127 tests, 41 fail on the old code; K1 and T3 fixes hold (every key on every row control, More menu, picker unchanged, waiting focus, Undo, moved and deleted rows, paint read from pixels, no error in any frame). No bugs. check.sh +2103 ~8 passed. Reviewer re-check of 2750eb5..cc231ff started.
- Gates: developer done · tester pass · reviewer re-check in progress · QA re-run pending · PM merge waiting
- Open findings: none; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — K1, T3 fixed; tester round 10 started
- Changed: developer fixed BUG-K1 in 9206ad7 (row shortcuts act only when the row has focus; Enter and Space activate the focused button; Delete on a button no longer deletes the row) and BUG-T3 in a1e3e55 (cause: off-screen kept-alive row painted through its own repaint boundary; Snippets rows no longer get one). check.sh +1974 ~8 ×2. Tester round 10 on a4c06a0..a1e3e55 started.
- Gates: developer done · tester round 10 in progress · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: none open; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 9: K1, T3 found
- Changed: tester round 9 on e0cbdfe..d892b56 (a4c06a0, tests only): 55 tests, 26 fail on the old code; T1, T2 and History text-size fixes hold (sequences, flings, resizes, copies, trims, no leaked hold, H5 kept, disposal clean). check.sh +1949 ~11 passed. Found BUG-K1 (medium, accessibility, existed before): Enter on a focused row button (Delete, Save as snippet) runs the row's copy instead of the button. BUG-T3 (low): one-frame layout overflow in Snippets after a text-size change while scrolled. Note: History header overflows at 300% text (beyond the 200% requirement). Developer fixing K1 and T3.
- Gates: developer in progress (K1, T3) · tester round 9 done · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: BUG-K1 (Medium), BUG-T3 (Low); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — History text-size focus fixed; tester round 9 started
- Changed: developer fixed History focus after a text-size change in d892b56 (row scrolled back into view, same control refocused; waiting focus after a user scroll left alone; row owns its button focus nodes). check.sh +1897 ~8 ×2. Tester round 9 on e0cbdfe..d892b56 started.
- Gates: developer done · tester round 9 in progress · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: none new; N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — T1, T2 fixed; History text-size focus fix started
- Changed: developer fixed BUG-T1 (6edb532: Tab into a list judges in-view by the whole row) and BUG-T2 (d9d691f: Snippets keeps the focused control and row in view after a text-size change). check.sh +1887 ~8 ×2. Developer found the same text-size problem in History (focused row can end out of view, WCAG 2.4.11). Lead's call: fix it here, keeping the PM's H5 rule (a text-size change is not a user scroll; waiting focus after a user scroll is left alone).
- Gates: developer in progress (History text-size focus) · tester round 9 pending · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: History text-size focus (Low, being fixed); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 8: T1, T2 found
- Changed: developer fixed the Snippets banner wording for a rejected switch (3ed1ba8; check.sh +1804 ~8 ×2). Tester round 8 on 707f131..3ed1ba8 (e0cbdfe, tests only): 70 new tests pass, 43 fail on the old code; Tab stays in view after every scroll kind, window size, list change; keys act only on in-view rows; banners right in every profile state. check.sh +1882 ~11 passed. Found BUG-T1 (Low): Snippets Tab enters at a cut-off row's Copy button. BUG-T2 (rare): text-size change while a Snippets control has focus breaks the next Shift+Tab. Developer fixing both.
- Gates: developer in progress (T1, T2) · tester round 8 done · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: BUG-T1 (Low), BUG-T2 (Low); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — QA-M14-5 and -6 fixed
- Changed: developer fixed QA-M14-5 in 7546d52 (cause: rows built beyond the list edges came first in Tab order; now Tab goes header then panel, enters a list at the first row fully in view, and scrolls whatever it focuses into view; History had the same bug and is fixed too) and QA-M14-6 in f2c100f (rejected switch banner names the switch, Debug only). check.sh +1801 ~8 passed ×2; one earlier run had a picker-search timing failure under load (unrelated, passes alone). Follow-up: the Snippets banner gets the same wording fix.
- Gates: developer in progress (Snippets banner wording) · tester round 8 pending · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: none open beyond the follow-up; N1, N2, F5 (Windows), R1 unchanged. Note: picker search timing test can fail under full-suite load.
- Decisions: none
- Blockers: PM — free the Mac for the QA re-run (later); confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — QA test-item cleanup — PM decision
- Changed: none yet.
- Gates: developer in progress (QA-M14-5, -6) · tester pending · reviewer pending · QA re-run pending · PM merge waiting
- Open findings: QA-M14-5 (Major), QA-M14-6 (Minor); N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM said (2026-11-06): "QA removes them" — in answer to "Who should remove QA's 28 test items from your real data?" Scope: exception to the label rule for cleanup only. At the next session when the PM frees the Mac, QA deletes from the PM's real data only its own test items (history qa-m14-s4-01..17, snippets "qa-m14-s4 snip 01..11", and any other qa-m14-* items QA created), one at a time, never with Clear history. The label rule still applies to every test step.
- Blockers: PM — free the Mac for the QA re-run; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — QA session 4: fail (QA-M14-5)
- Changed: QA session 4 on 2750eb5 (rebuilt Debug, CDHash 3f480ddce08cea236227b43ed0f9e5388c920317, signed Apple Development (redacted)); evidence docs/qa/m1.md "M1.4 session 4", 12 screenshots, commit 707f131. AC1, AC2 pass; AC3 pass in the test profile (Keep 10, snippets kept). QA-M14-2 and QA-M14-4 now pass. H1–H7 pass. Four mistyped switches: memory only, dataProfileRejected 3; real data unchanged (439 items, Keep 500). Label checked before every delete step; one step stopped and redone when a dialog hid the label. New: QA-M14-5 (Major): after a wheel scroll, Tab from the Snippets tab focuses a hidden row and Enter copies it. QA-M14-6 (Minor, Debug copy): rejected switch banner blames the keychain. Developer (opus, xhigh) fixing both.
- Gates: developer in progress (QA-M14-5, -6) · tester pending · reviewer pending · QA fail, re-run needed · PM merge waiting
- Open findings: QA-M14-5 (Major), QA-M14-6 (Minor); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: QA — 28 QA test entries (history qa-m14-s4-01..17, snippets "qa-m14-s4 snip 01..11") left in the PM's real data, because the label rule blocks deletes there; PM to decide. PM — confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Reviewer re-check: approve with notes
- Changed: reviewer re-checked 9023273..2750eb5: approve with notes; 0 new findings. P1 fixed; BUG-Q1 fixed within the PM's scope. Release untouched; rejected switches reach nothing real; no false positive for normal launches. check.sh +1788 ~8 passed.
- Gates: developer done · tester pass · reviewer approve with notes · QA session 4 pending (needs the PM's Mac free) · PM merge waiting
- Open findings: none new. With the PM: slips of 4+ edits, about 1.2% of 3-edit slips, 3-way splits. N1, N2, F5 (Windows), R1 unchanged. QA data in the PM's real database to clean up.
- Decisions: none
- Blockers: PM — free the Mac for QA; confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 7 passed; reviewer re-check started
- Changed: tester round 7 on 8c071df (2750eb5, tests only): 95 tests, none skipped; 21 fail on 52dd598, all pass on 8c071df. Every 1-edit slip and 6,000 random 2-edit slips rejected; 19 dash and minus characters, spaces, quotes, two-way splits rejected; about 45 realistic launch arguments and all 22×22 pairs not rejected; rejected forms reach nothing real. check.sh +1788 ~8 passed.
- Gates: developer done · tester pass · reviewer re-check of 9023273..2750eb5 in progress · QA session 4 pending · PM merge waiting
- Open findings: none in scope. Notes: 4+ edit slips escape (about 66% of them), about 1.2% of 3-edit slips escape, 3-way splits not read together (with PM); a single argument over about 4 million characters overflows the stack (unreachable on macOS).
- Decisions: none
- Blockers: PM — confirm the extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — BUG-Q1 fixed; tester round 7 started
- Changed: developer (opus, xhigh) fixed BUG-Q1 in 8c071df: in Debug, slips within 3 edits of the switch (with or without a dash), any dash or minus, leading spaces or quotes, and a switch split across two arguments are rejected (memory only, dataProfileRejected 3). Q1a, Q1c, Q1d, Q1e, Q1f repros unskipped and pass; Q1b, Q1g stay skipped (PM risk acceptance 2026-11-06). check.sh +1693 ~8 passed ×2. No false positive in 66 realistic launch-argument sets.
- Gates: developer done · tester round 7 in progress · reviewer pending · QA session 4 pending · PM merge waiting
- Open findings: none new. Not caught (to confirm with PM under the 2026-11-06 acceptance): slips of 4 or more edits; a switch split across 3 or more arguments.
- Decisions: none
- Blockers: PM — confirm the two extra uncaught slip kinds; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — BUG-Q1 scope — PM decision
- Changed: none in code yet. Developer re-dispatched one effort level higher (opus, xhigh) after the P1 fix failed tester round 6.
- Gates: developer in progress (BUG-Q1) · tester round 7 pending · reviewer pending · QA session 4 pending · PM merge waiting
- Open findings: BUG-Q1 (Low) being fixed; N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM said (2026-11-06): "Common slips + label check" — in answer to "How far should the developer take the mistyped-switch fix?" Scope: the developer also rejects typos within a few letters of the switch, any dash or minus character, leading spaces and quotes, and the switch split across two arguments (Q1a, Q1c, Q1d, Q1e, Q1f); QA must confirm the "Test profile: qa" label with its tools before any step that deletes data, and stop if it is missing.
- Risk accepted by PM (2026-11-06): accepted: a few rare test-profile switch slips still open the real data folder in Debug builds, such as part of the switch left out (`-Profile` alone, Q1b) or look-alike letters from other alphabets (Q1g); QA's label check covers them during QA — scope: M1.4, feat/saved-snippets, BUG-Q1b and Q1g, Debug builds only — expiry/review: none — PM said: "Common slips + label check" — in answer to "How far should the developer take the mistyped-switch fix?" (the option said the remaining rare cases would be accepted as a risk)
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 6: P1 fix incomplete (BUG-Q1)
- Changed: tester round 6 on 21c17b4 (52dd598, tests only): 63 tests pass, 7 skipped repros. 22 misspelled variants are rejected and reach nothing real (real folder byte for byte unchanged, no keychain call, no log). But 76 realistic slips still open the real folder (BUG-Q1): Q1a typo inside a word (-KusungaDataProfle), Q1b part left out (-DataProfile, -Kusunga), Q1c dash forgotten, Q1d other dash or minus characters, Q1e leading space or quote, Q1f switch split across arguments, Q1g look-alike letters (low realism). check.sh +1637 ~13 passed.
- Gates: developer open (BUG-Q1) · tester round 6 done · reviewer pending · QA session 4 pending · PM merge waiting
- Open findings: BUG-Q1 (Low, part of reviewer P1); N1, N2, F5 (Windows), R1 unchanged
- Decisions: none yet — PM asked how far to take the fix
- Blockers: PM — BUG-Q1 scope; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — P1 fixed; G1 accepted — PM decision
- Changed: developer fixed reviewer P1 in 21c17b4: in Debug, a misspelled test-profile switch (dash variants, en/em dash, `/`, missing letters, mixed case) is rejected with dataProfileRejected detail 3 and runs memory only. check.sh +1574 ~6 passed ×2. Tester round 6 on 21c17b4 in progress.
- Gates: developer done · tester round 6 in progress · reviewer re-check of 21c17b4 pending · QA session 4 pending · PM merge waiting
- Open findings: G1 accepted (below); N1, N2, F5 (Windows), R1 unchanged
- Decisions: Risk accepted by PM (2026-11-06): accepted: Kusunga checks that its log file is not a link and then opens it, so a process running as the same user that swaps in a link between the check and the open makes Kusunga append one log line (a timestamp and a fixed code, no personal data) to the link's target (reviewer G1, lib/log/app_log.dart:92-106) — scope: M1.4, feat/saved-snippets, finding G1 — expiry/review: none — PM said: "Yes, accept it" — in answer to "May we leave the rare log-file link race (G1) unfixed for now?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer n/a · Lead none · PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Reviewer re-review: approve with notes
- Changed: reviewer re-reviewed bf06141..9023273: approve with notes. check.sh +1556 ~6 passed. Test profile cannot reach real data in Release (kDebugMode gate; Mac arguments only under #if DEBUG); no Apple team or certificate ID in tracked files; no PM history in the 17 new screenshots. Lead redacted a signing-identity person name in an older status entry.
- Gates: developer P1 fix in progress · tester pass (round 5) · reviewer approve with notes · QA session 4 pending · PM merge waiting
- Open findings: P1 (Low): a misspelled or en/em-dash test-profile switch is ignored, so the app opens real data; fix in progress. G1 (Low): log link check then open is a race; a symlink swapped in between gets one appended log line; needs a PM decision. N1, N2, F5 (Windows), R1 unchanged.
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer n/a · Lead none · PM — G1 decision; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — Tester round 5 passed; reviewer re-review started
- Changed: tester round 5 on d966b6f added test/history/ui/history_scroll_round5_test.dart (19 tests, 9023273, test files only): copies then wheel scroll then arrow keys, node swaps, theme and text-size rebuilds, copies while focus waits, clicks after a copy. 16 of 19 fail on the old history_row.dart (bcee93b); all pass with the fix. check.sh: No issues found; +1556 ~6, all passed (skips: 3 accepted hard-link tests, L5, 2 older). No new bugs.
- Gates: developer done · tester pass · reviewer re-review of bf06141..9023273 in progress · QA session 4 pending · PM merge waiting
- Open findings: none new; BUG-L5 skipped by PM; Low notes N1, N2, F5 (Windows), R1 unchanged
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer n/a · Lead none · PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-06 — M1.4 Saved snippets — H7 fixed; L5 skipped — PM decision
- Changed: developer fixed BUG-H7 (arrow keys did nothing after a copy and a mouse-wheel scroll in History) in d966b6f; check.sh 1,537 passed ×2. Developer did not fix BUG-L5: dart:io file locks work per process, so two Kusunga processes writing the log at the same instant can lose or garble about 1–2 lines in 1,000. Fix options were native append (FFI on Mac and Windows) or a lock file that can freeze the app if it crashes while holding the lock. Diagnostic log only; history and snippets are not affected; the risk existed before M1.4.
- Gates: developer done · tester round 5 in progress · reviewer re-review pending · QA session 4 pending · PM merge waiting
- Open findings: BUG-L5 skipped by PM decision (its test stays skipped); earlier Low notes N1, N2, F5 (Windows), R1 unchanged
- Decisions: Risk accepted by PM (2026-11-06): accepted: rare lost or garbled diagnostic log lines when two Kusunga processes write the log at the same instant (BUG-L5) — scope: M1.4, feat/saved-snippets, finding BUG-L5 — expiry/review: Later line in docs/PLAN.md — PM said: "Skip it" — in answer to "May we leave the lost log lines unfixed for now?"
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — Round-3 fixes done; End speed deferred — PM decision
- Changed: developer fixed L4, L2, L3 (4375e75: per-line log open with a link check) and H4, H6, H5 (6961ab2: focus follows the item by id; nearest item on trim; list kept in view only while the arrow keys are used). check.sh 1,505 passed ×2. Profile-build timing: End over 5,000 History rows 4.8 s (4.9 s with copies). Found: Flutter 3.44.6 profile/release macOS builds fail on macOS 27 (`lipo`); added as an M1.9 AC.
- Gates: developer done · tester round 4 in progress · reviewer · QA · PM merge waiting
- Open findings: none new beyond tester round 4
- Decisions: PM said (2026-11-05): "Go with the recommendation" — in answer to "How should we handle the 5-second End in a 5,000-item history?" (recommendation: keep variable row heights and add a Later line). Later line added to docs/PLAN.md.
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — Tester round 3; developer stuck; PM approves plan and risk
- Changed: developer fixed H1–H3, P3, late log link (a44e597, 7dcbca1, 77a2080, 52e9ddd); check.sh 1,476 passed ×2. Tester round 3 (7fbe638) found BUG-L4 (high, regression: two writers on one log overwrite lines), L2, L3 (low), BUG-H6 (high: focused History row trimmed, focus lost), BUG-H4 (End in 5,000 rows 7× slower while copies arrive), BUG-H5 (design: re-show of focused row fights mouse scrolling), BUG-P4 and two known limits (hard links created between check and open, or to files outside the default folder).
- Escalation: developer on Opus at high effort failed a third tester round; raised to the PM instead of another loop.
- Gates: developer in progress · tester round 4 pending · reviewer · QA · PM merge waiting
- Plan approved: fix L4 (back to per-line open with a link check; also fixes L2, L3), H6 (focus moves to the nearest remaining item), H4 (find the cause; measure in a real build); H5: keep the focused row in view only while the arrow keys are used, not after the user scrolls.
- Risk accepted by PM (2026-11-05): accepted: the test profile can still reach other files through a hard link created between Kusunga's check and the file open, or a hard link to files outside the default data folder (BUG-P4 and the two "KNOWN LIMIT" tests) — scope: M1.4, Debug builds only (the test profile does not exist in Release) — expiry/review: none — PM said: "You can go ahead" — in answer to "Do you approve my plan to finish this round?"
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — Tester round 2 fixed; History scroll bug added to scope — PM decision
- Changed: tester (dcf4468..683cdcd) found BUG-P1/P2 (symlinked test-profile folder or files followed into real data), BUG-U3 (arrow keys don't scroll long snippet lists), U2, U1; developer fixed all (c933c6f, 4485bb4, fd67224, 6bef2e6 mistyped switch rejected, 2ba3b1a robust timing test, 36e2a4a docs). check.sh 1,423 passed ×3; XCTest 231 passed. Developer found the History tab has the same scroll bug (WCAG 2.4.11).
- Gates: developer in progress · tester round 2 pending · reviewer · QA · PM merge waiting
- Open findings: History arrow-key scroll (being fixed); earlier Low notes N1, N2, F5 (Windows), R1 unchanged
- Decisions: PM said (2026-11-05): "Fix it here" — in answer to "Should the developer fix the History tab's arrow-key scrolling on this branch?"
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — AC3 test profile — PM decision
- Changed: none yet. The developer adds a debug-only switch so Kusunga uses a separate test data folder; QA runs the history-limit test (AC3) on throwaway data.
- Gates: developer in progress · tester · reviewer · QA · PM merge waiting
- Open findings: as in the previous entry
- Decisions: PM said (2026-11-05): "Add a test profile" — in answer to "How should QA test the history limit without losing your 411 history items?" (options: a debug-only test profile, or automated tests only).
- Blockers: PM — GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — QA session 3: fail (2 Major accessibility bugs); developer escalated
- Changed: QA-M14-1 (tabs stacked) fixed in 826938d; tester 26 tests (bf06141), no bugs; reviewer approve with notes on bf06141. QA session 3 on the rebuilt signed Debug app (CDHash 0167a366…, commit bf06141; PM said "Mac is free"): AC1 works functionally, AC2 pass (D1, D2, D3, F8, pasteSource 1), AC3 not run on the real app (setting Keep to 10 would permanently delete about 400 of the PM's history items), privacy pass. Evidence docs/qa/m1.md "M1.4 session 3" (86f6f7c, not pushed); videos in qa-artifacts/m1.4/.
- Gates: developer reopened · tester pass · reviewer approve with notes · QA fail · PM merge waiting
- Open findings: QA-M14-2 (Major) Up/Down don't move between snippet rows; QA-M14-4 (Major) keyboard focus barely visible (1.2:1) on New snippet, row actions, editor buttons; QA-M14-3 (Minor) names cut at 600–700 px. Earlier Low notes N1, N2, F5 (Windows), R1 unchanged.
- Escalation: developer re-dispatched on Opus at high effort (second QA failure on this item).
- Decisions: none
- Blockers: PM — how to test AC3 on the real app; GitHub billing or acceptance of local results for M1.4; VoiceOver sign-off

## 2026-11-05 — M1.4 Saved snippets — QA may launch Kusunga — PM decision
- Changed: QA resume found Kusunga not running (Mac restarted 09:34 for macOS 27.2; build unchanged, CDHash 6288d6c5…). Notes in docs/qa/m1.md (cc5c2dd, not pushed).
- Gates: developer done · tester pass · reviewer approve with notes · QA in progress · PM merge waiting
- Open findings: as before
- Decisions: PM said (2026-11-05): "Yes, QA may launch" — in answer to "May QA launch Kusunga itself for this test session?" Scope: this M1.4 QA session only. Dialogs stay with the PM.
- Blockers: none for QA; PM — GitHub billing or acceptance of local results for M1.4

## 2026-11-05 — M1.4 Saved snippets — QA blocked by a keychain prompt
- Changed: QA confirmed the installed build (CDHash 6288d6c5…, commit 9be61eb) and permissionSnapshot 7 after relaunch. A macOS keychain dialog ("Kusunga wants to use your confidential information stored in 'com.wnasoni.kusunga'…") then appeared; per the PM rule QA stopped and left it untouched. No real-app flow ran; no screenshots (the window shows the PM's history). Notes in docs/qa/m1.md (de1fc6b on feat/saved-snippets).
- Gates: developer done · tester pass · reviewer approve with notes · QA blocked (0/3 criteria on the real app; ./tool/check.sh 1,189 passed) · PM merge waiting
- Open findings: as in the previous entry
- Decisions: none
- Blockers: PM — answer the keychain dialog on the Kusunga window, then tell the lead; GitHub billing or acceptance of local results for M1.4

## 2026-11-05 — M1.4 Saved snippets — Developer, tester and reviewer done; review approved with notes
- Changed (branch feat/saved-snippets, 9be61eb, pushed): snippets table (schema v3) in the encrypted store, main-window History/Snippets tabs, snippet editor, reorder, delete with Undo, Save as snippet, picker Snippets tab (⌃Tab), D1 history skip (Mac: own change count; Windows: unverified), `pasteSource` log code. Tester bugs TB-1, TB-2, TB-4, TB-5, R2, R3 fixed (6cf48f6..2a848f1). Reviewer L1, F1–F10, C1 fixed (7aca3ca..9be61eb); F5 fixed on Mac, skipped on Windows (Low; needs real Windows; "TO CONFIRM ON REAL WINDOWS" comment at clipboard_bridge.cpp:122).
- Checks: ./tool/check.sh 1,189 passed (reviewer, on 9be61eb); XCTest 231 passed (developer); ./tool/test_windows_policy.sh passed. CI not run (GitHub billing). Windows not compiled.
- Gates: developer done · tester pass · reviewer approve with notes · QA pending · PM merge waiting
- Open findings (Low, notes): N1 the "keychain" Snippets banner also shows for other memory-only causes; N2 after a failed migration History and Snippets give different advice; F5 Windows part skipped; R1 Clear history deletes .bak/.unreadable files that may now hold snippets (PM decision). Banner wording is a lead draft for PM confirmation.
- Decisions: none
- Blockers: PM — GitHub billing (CI) or acceptance of local results for M1.4; banner wording; R1

## 2026-11-04 — M1.4 Saved snippets — Overnight permissions — PM decision
- Changed: none. The lead runs the gates overnight (developer, tester, reviewer, QA); no merge, no risk acceptance and no skipped finding without the PM.
- Gates: developer in progress · tester · reviewer · QA · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Yes to both" — in answer to "Tonight, may QA quit and relaunch Kusunga, and may I push the M1.4 branch to GitHub?" Scope: tonight only; QA may quit and relaunch the PM's Kusunga (signed Debug build) for each QA build; the lead may push feat/saved-snippets (no merge, no PR merge). If a keychain or permission prompt appears, QA stops and leaves it for the PM.
- Blockers: PM — GitHub billing (CI)

## 2026-11-04 — M1.4 Saved snippets — Design approved
- Changed: design note docs/design/saved-snippets.md, UI spec docs/ui/saved-snippets.md, deck docs/slides/saved-snippets.html; merged to main. Size: large — new data store (snippets table, schema v3), personal data the user types in, new UI.
- Gates: design approved · developer not started · tester · reviewer · QA · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Approve as is" — in answer to "Do you approve the snippets design with all four recommendations?" Accepted: D1 pasting a snippet does not add it to history; D2 pinning copies (the item stays in history); D3 the picker always opens on History; D4 bank and card details allowed, with a note in the editor; design and UI spec approved.
- Blockers: PM — GitHub billing (CI) before the M1.4 merge

## 2026-11-04 — M1.3 History picker and paste — Merged
- Changed: PR Thamzy265/kusunga#3 merged into main as 6e5a183. M1.3 ticked in docs/PLAN.md.
- Gates: developer done · tester pass · reviewer approve with notes · QA pass · PM VoiceOver pass · CI not run (GitHub billing; PM accepted local results) · PM merge approved
- Open findings: Low notes as Later lines in docs/PLAN.md; macOS 12 minimum as an M1.9 AC.
- Decisions: PM said (2026-11-04): "Approve merge" — in answer to "Do you approve merging M1.3 into main?"
- Blockers: PM — GitHub billing, so CI can run again; open conditions: first CI run after billing is fixed green on both OSes, first macOS CI on main green.

## 2026-11-04 — M1.3 History picker and paste — CI not started (GitHub billing) — PM risk acceptance
- Changed: QA part 2 attempt 7 pass on adc39d1 (one click closes the picker after the target quits; copy-only plus toast; pastes pass). Reviewer approve with notes on adc39d1; notes are Later lines in docs/PLAN.md.
- Gates: developer done · tester pass · reviewer approve with notes · QA pass · PM VoiceOver pass · CI not run: GitHub refused to start jobs ("recent account payments have failed or your spending limit needs to be increased") · local results: ./tool/check.sh 893 passed, XCTest TEST SUCCEEDED, ./tool/test_windows_policy.sh all passed (lead, on a727633) · Windows build and runtime not tested · PM merge waiting
- Risk accepted by PM: merge M1.3 on local results; Windows build and tests unverified since the Windows picker dismissal change (F3). Condition: the first GitHub CI run that completes after billing is fixed must be green on both OSes; the M1.2 condition (first macOS CI on main green) still stands.
- Decisions: PM said (2026-11-04): "Accept local results" — in answer to how to handle GitHub's checks before the merge.
- Blockers: PM — GitHub billing (Actions)

## 2026-11-04 — M1.3 History picker and paste — Paste works; review approved with notes
- Changed (branch feat/history-picker, eb432b2): local signing through a git-ignored Local.xcconfig (CI stays ad-hoc); Mac deployment target 12.0 (forced by Xcode 27.2); permission codes mirrored to the macOS unified log (closed code list); picker kept open once when its target app quits; "Copied" toast on focus loss; VoiceOver/Narrator announce the count and selected row; tester bugs B1–B3 and reviewer findings F1–F6, R1, R2, C1–C6 fixed.
- Root cause of copy-only: the Accessibility entry belonged to an older ad-hoc build. With a stable signature and a fresh entry, permissionSnapshot = 7. H1 (wrong TCC service) not confirmed; ADR 0003 unchanged.
- Gates: developer done · tester pass (B1–B3 fixed) · reviewer approve with notes · QA part 2 attempt 5 pass (9/9 pastes, p95 170 ms, AC5, AC6, modifier release) · PM VoiceOver pass · CI pending on eb432b2 · PM relaunch recheck and merge waiting
- Open findings (Low, notes): shortcut press within 120 ms of clicking away is ignored; record the macOS 12 minimum in ADR 0003 or the README before M1.9; source guard that runPaste uses the real permissionMask; signing-id guard does not cross-check the local id outside macos/ios/tool/.github.
- Decisions: PM said (2026-11-04): "Rebuild with system log" — in answer to how to read the diagnostic codes. PM said (2026-11-04): "Both work" — VoiceOver check of the picker after the fix. PM said (2026-11-04): "Yes, rewrite them" — rewrite the unpushed commits so the team and certificate ids never reach GitHub (done before push; backup branch backup/pre-rewrite-history-picker kept locally).
- Blockers: none

## 2026-11-04 — Local signing for test builds — PM decision
- Changed: none yet. PM to sign in to Xcode and create an Apple Development certificate (Personal Team); the developer then signs local test builds with it via a git-ignored local xcconfig. CI stays ad-hoc. Does not replace the paid Developer ID account needed for M1.9.
- Gates: n/a — decision
- Open findings: none new
- Decisions: PM said (2026-11-04): "Yes, show me how" — in answer to "Will you set up free Apple ID signing in Xcode for test builds?"
- Blockers: PM — Xcode sign-in and certificate

## 2026-11-04 — M1.3 History picker and paste — Paste permission root cause (developer investigation)
- Changed: none in code. The macOS log (tccd) shows the PM's Settings toggle granted kTCCServiceAccessibility, while CGPreflightPostEventAccess reads kTCCServicePostEvent, which stays denied; on macOS 27 PostEvent "does not allow prompting", so "Allow pasting" only creates a denied row. Also 4 Kusunga copies with the same bundle id are registered (build Debug, build Release, Xcode DerivedData test host, one stale path). Ad-hoc signing ties every grant and the keychain "Always Allow" to one build's hash. The Mac's only signing identity (Apple Development (redacted)) is revoked.
- Gates: developer investigating · tester pass · reviewer approve · QA part 2 blocked · PM merge waiting
- Open findings: H1 (wrong TCC service — ADR 0003's "PostEvent only" assumption may not hold on macOS 27) strongest; H2 (stale copies) possible
- Decisions: waiting for PM — stable local signing (free Personal Team) before the diagnostic build
- Blockers: PM

## 2026-11-04 — M1.3 History picker and paste — Paste permission not effective
- Changed: QA (7bf5fb8, on the branch): after the PM removed and re-granted the permission and relaunched, paste still falls back to copy-only (`pastePermissionMissing`). Build is ad-hoc signed, sandboxed. Developer investigating root cause without a rebuild (TCC PostEvent vs Accessibility, stale copies with the same bundle id, unstable ad-hoc signing identity).
- Gates: developer investigating · tester pass · reviewer approve · QA part 2 blocked · PM merge waiting
- Open findings: real paste never shown on a real Mac yet
- Decisions: none
- Blockers: Developer — root cause of CGPreflightPostEventAccess staying false
- Sources: https://developer.apple.com/forums/thread/724603 ; https://developer.apple.com/forums/thread/744440 ; https://developer.apple.com/forums/thread/758554 ; https://developer.apple.com/forums/thread/727984

## 2026-11-04 — M1.3 History picker and paste — PM redid the paste permission
- Changed: PM removed the old Kusunga Accessibility entries and granted the permission again for the c175b71 build. QA running part 2.
- Gates: developer pass · tester pass · reviewer approve · QA part 2 running · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Done, redone" — in answer to "Tell me when you've redone the Accessibility entry for Kusunga."
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — QA part 2 blocked
- Changed: QA (2ef32d6, on the branch): with the permission turned on, paste still falls back to copy-only on the c175b71 build, before and after a relaunch (log `pastePermissionMissing`). Likely cause: the Accessibility entry belongs to an earlier unsigned build (each rebuild gets a new signature); PM asked to remove and re-add it.
- Gates: developer pass · tester pass · reviewer approve · QA part 2 blocked · PM merge waiting
- Open findings: real paste not yet shown; treated as a code/entitlement issue if it persists after the PM redoes the entry
- Decisions: none
- Blockers: PM — redo the Accessibility entry for this build

## 2026-11-04 — M1.3 History picker and paste — PM allowed pasting; QA part 2
- Changed: PM turned Kusunga on in System Settings > Privacy & Security > Accessibility (after help finding the entry). QA running part 2 (real paste).
- Gates: developer pass · tester pass · reviewer approve · QA part 2 running · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "its enabled" — after the lead's steps to allow pasting.
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — PM decision on taken shortcuts
- Changed: plan AC amended. The "^" copy finding was a misread: the code renders ⌃ (U+2303), which the font draws like a caret; no change.
- Gates: developer pass · tester pass · reviewer approve · QA part 1 pass · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Accept as Mac limit" — in answer to "How should we handle a shortcut that another Mac app already uses?" (accept as a Mac limitation and amend the AC to "reported where the OS reports it (Windows)", or add another check).
- Blockers: QA part 2 needs the PM to allow pasting

## 2026-11-04 — M1.3 History picker and paste — QA part 1 re-run: pass except AC7 "taken shortcut"
- Changed: QA (60f24df, on the branch) re-ran part 1 on c175b71. Pass: picker over TextEdit, Safari and Terminal with Kusunga frontmost; tray "Open picker"; full keyboard path with no click; copy-only fallback (exact toast, focus kept, card only after that paste, pastePermissionMissing logged); reserved ⌘V refused; Esc cancels recording; "Shortcut not changed." after 20 s idle; picker open p95 ≈ 100 ms; first keystroke p95 83 ms (341 items); no outbound sockets. First-run B1–B3 do not reproduce.
- Gates: developer pass (one copy fix: ⌃ not ^) · tester pass · reviewer approve · QA part 1 pass except AC7 taken-shortcut · PM merge waiting
- Open findings: G3 — on macOS 27 Carbon lets two apps register the same shortcut, so Kusunga can't report a shortcut taken by another app (both fire); system shortcuts like ⌘Space aren't reported either. Copy: "^" shown instead of "⌃" (developer fixing)
- Decisions: waiting for PM on G3 (accept as a Mac limitation and amend the AC, or add another check)
- Blockers: QA part 2 needs the PM to allow pasting

## 2026-11-04 — M1.3 History picker and paste — Reviewer: approve
- Changed: reviewer confirmed G2r, T1, R1 fixed (each new test fails on c0a297a). CI run 41802611042 green on macOS and Windows. No findings open.
- Gates: developer pass · tester pass · reviewer approve · QA running · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: QA part 2 needs the PM to allow pasting; Windows runtime still unrun (CI only)

## 2026-11-04 — M1.3 History picker and paste — QA re-run started
- Changed: QA built c175b71; PM opened it and answered the keychain prompt. QA re-runs part 1.
- Gates: developer pass · tester pass · reviewer confirming c175b71 · QA running · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Done, Always Allow" — in answer to "Tell me once you've opened the app and clicked Always Allow."
- Blockers: QA part 2 needs the PM to allow pasting

## 2026-11-04 — M1.3 History picker and paste — Last Low notes fixed
- Changed: ace9313 (G2r per-reason log codes, new `pasteCopyOnly`; T1 recording timer restarts on each key, "Shortcut not changed." announced on give-up) and c175b71 (R1 activation retries ≤ 0.5 s and stop when the user switches away). 806 pass / 2 skipped, XCTest 143; lead re-ran the check. Pushed. Reviewer confirming; QA building the one app for part 2.
- Gates: developer pass · tester pass · reviewer confirming · QA part 2 open · PM merge waiting
- Open findings: none
- Decisions: none new
- Blockers: QA needs the PM for the keychain prompt and to allow pasting

## 2026-11-04 — M1.3 History picker and paste — Reviewer: approve with notes
- Changed: reviewer re-checked c0a297a: forced activation is acceptable (only after the user's own shortcut or tray click; never during the paste focus check). CI run 41800681653 green on both OSes. G2 was a QA misread (QA read the old container's log; the real log already had the code).
- Gates: developer fixing three Low notes before the QA rebuild · tester pass · reviewer approve with notes · QA part 2 open · PM merge waiting
- Open findings: Low G2r (new log line mislabels other copy-only reasons), R1 (activation retries can run up to 1 s and could pull focus back if the user switches away), T1 (shortcut recording gives up silently; must be fixed, basic accessibility)
- Decisions: lead approves the copy "Shortcut not changed." for T1; the three Low notes are fixed before QA's single rebuild
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — PM keyboard check 2
- Changed: PM checked B2 (tray "Open picker" then typing) and B3 (Change shortcut, then Esc) with the physical keyboard on the 4147f9b build: both work. B1–B3 were QA tooling artefacts (synthetic keys go to the frontmost process); the developer's activation fixes stay, as they make Kusunga reliably frontmost (also for VoiceOver).
- Gates: developer pass · tester pass · reviewer re-check open · QA re-run open · PM merge waiting
- Open findings: none confirmed
- Decisions: PM said (2026-11-04): "Both work" — in answer to "With your real keyboard, do the menu-bar picker and Change shortcut work?"
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Developer fixes for QA part 1
- Changed: 2d20d3d (explicit focus for the search field and the shortcut recorder; recording cancels on deactivation and after 20 s; G2 logging; G1 test) and c0a297a (Kusunga is forced active and key while the picker shows, with short retries; borderless window can become key). 804 pass / 2 skipped; lead re-ran the check. Pushed; reviewer re-checking.
- Gates: developer pass · tester pass · reviewer re-check open · QA re-run open · PM merge waiting
- Open findings: B2 and B3 awaiting the PM's physical-keyboard check on the old build; G1 not reproduced in code (card may have come from an earlier copy-only paste in the same run)
- Decisions: none new
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — PM keyboard check
- Changed: PM checked B1 with the physical keyboard on the 4147f9b build: typing reaches the picker search field. B1 is likely a QA tooling artefact (System Events sends keys to the frontmost process); developer checks whether Kusunga is the active app while the picker shows.
- Gates: developer fixing · tester pass · reviewer approve with notes · QA fail (B1 under review) · PM merge waiting
- Open findings: B1 not reproduced with a real keyboard; B2, B3 to confirm with a real keyboard; G2; G1
- Decisions: PM said (2026-11-04): "Typing works" — in answer to "With your real keyboard, does typing appear in the picker's search box?"
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — QA part 1: fail
- Changed: QA (a27ffc9, on the branch) ran the real Mac app. Pass: picker opens over TextEdit, Safari and Terminal; search, list keys, ⌘1–9, mouse, click-outside, Esc returns focus to the target app; copy-only fallback with the exact toast text, toast doesn't take focus; picker on screen p95 ≈ 100 ms; no outbound sockets, codes-only log. 9 screenshots.
- Gates: developer fixing · tester pass · reviewer approve with notes (re-check after fixes) · QA fail · PM merge waiting
- Open findings: Blocker B1 — keys don't reach the picker until the search field is clicked; Major B2 — tray "Open picker" doesn't activate Kusunga (typing goes into the other app); Major B3 — shortcut recording gets no keys and can't be cancelled; Minor G2 — copy-only path doesn't log; spec gap G1
- Decisions: lead decision G1 — the "Let Kusunga paste for you" card stays hidden until a paste needed the permission (as the spec says)
- Blockers: QA part 2 waits for the fixes and one new build; PM asked for a 1-minute physical-keyboard check of B1

## 2026-11-04 — M1.3 History picker and paste — QA part 1 started
- Changed: QA built one debug app (4147f9b). PM opened it and answered the keychain prompt. QA runs everything that works before pasting is allowed.
- Gates: developer pass · tester pass · reviewer approve with notes · QA running · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-04): "Done, Always Allow" — in answer to "Tell me once you've opened the app and clicked Always Allow."
- Blockers: QA part 2 needs the PM to allow pasting (Kusunga's "Allow pasting" + System Settings)

## 2026-11-04 — M1.3 History picker and paste — Reviewer: approve with notes
- Changed: D1, W3, W4 fixed (0c37d35, 4147f9b). CI run 41726239937 green on macOS and Windows. All 12 findings across the rounds fixed (1 withdrawn). Note: a maximised history window comes back at normal size when the picker closes without activating Kusunga (accepted trade-off).
- Gates: developer pass · tester pass · reviewer approve with notes · QA open · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: QA needs the PM for the keychain prompt and to allow pasting (System Settings) on the real app; Windows runtime has no machine (CI only)

## 2026-11-04 — M1.3 History picker and paste — Reviewer re-check: block
- Changed: reviewer confirmed the earlier findings fixed (each repro fails on old code). CI run 41723751606 green on both OSes; the new Windows bridge compiles and links.
- Gates: developer fixing · tester pass · reviewer block · QA open · PM merge waiting
- Open findings: Medium D1 (on the "Dvorak – QWERTY ⌘" Mac layout the new key lookup posts ⌘. instead of ⌘V), W3 (Windows minimised/maximised history window restored in an inconsistent state); Low W4 (window moves by the taskbar size when the taskbar is at the top or left)
- Decisions: none new
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Developer fix round 2
- Changed: 7 commits to 5c4ded9 fix A1, W1, P1, K2, E1, M2, C1, W2, S6, L1, X1 and the Dvorak paste key; Later lines fixed. 797 pass / 2 skipped, XCTest 133 pass; lead re-ran the check. Pushed for CI.
- Gates: developer pass · tester pass · reviewer re-check open · QA open · PM merge waiting
- Open findings: none open on the developer side; native window behaviour not run live
- Decisions: none new
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Reviewer: block
- Changed: reviewer reviewed 0049a08. CI run 41718668191 green on macOS (macos-15) and Windows. Security review: no findings (focus check, own-marker rule, integrity check, sandbox guard all sound).
- Gates: developer fixing · tester pass · reviewer block · QA open · PM merge waiting
- Open findings: Medium A1 (screen readers can't read or edit the picker search field), W1 (Windows: hidden history window can flash or take focus after a paste/toast), P1 (search index rebuilt on every open; first keystroke ~0.5 s with 5,000 items), K2 (Windows AltGr+digit can paste an item); Low E1, M2 (M1.2: Cmd+Z after deleting the only row), C1, W2, S6, L1, X1; two developer Later lines rejected for format
- Decisions: lead decisions — fix the Dvorak/Colemak paste keystroke now (find the layout's "v" key) instead of deferring, because ⌘. would interrupt Terminal; accept the two new messages ("That shortcut is needed for copy and paste. Choose another." / "Couldn't save the shortcut. Try again.") and add them to the UI spec
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Developer fix round
- Changed: 268d7d3, 68c6844, 37e5cbf, b86ecc5, 0049a08 fix K1, U1, U2, V1, S3, S4/P1, S5 and apply the lead's Windows decisions; S1/S2 skipped with the Later line. 783 pass, 2 skipped; lead re-ran the check. Pushed for CI. Developer changed one tester repro's setup (one item → two items); sent to the reviewer to judge.
- Gates: developer pass · tester pass (repros green) · reviewer open · QA open · PM merge waiting
- Open findings: none open on the developer side
- Decisions: none new
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Tester hand-off
- Changed: tester added 176 Dart tests, 20 XCTests and a C++ edge test (69e222f..605c201). Dart 756 pass / 23 fail (repros). CI on ffdcd85: macOS PASSED on the new macos-15 runner (first Mac CI run since M1.2); Windows failed on the developer's 5,000-item search timing test (83 ms vs 50 ms).
- Gates: developer fixing · tester findings open · reviewer open · QA open · PM merge waiting
- Open findings: Medium K1 (shortcut could be set to ⌘V/⌘C/⌘X/⌘A/⌘Z and break paste itself), U1 (pending Undo lost after a picker trip), S5 (empty query on 5,000 items ~750 ms); Low-Medium V1 (ZWJ emoji shown as codes); Low U2, S3, S4/P1; S1/S2 deferred (see Decisions)
- Decisions: lead decisions — S1/S2 (ß and accent normalisation) deferred with a Later line and the repros skipped with that reason; Windows sends no paste keystroke if a modifier is still held after 300 ms (copy only); Windows picker clamps to small work areas
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — Developer hand-off
- Changed: branch `feat/history-picker` (19 commits), draft PR https://github.com/Thamzy265/kusunga/pull/3 for CI only. 603 Dart + 103 XCTest + C++ picker and clipboard policy tests pass; lead re-ran the check (603 pass). App not launched (keychain prompt). Windows picker bridge compiles only in CI. 2 Later lines added by the developer (non-QWERTY Mac layouts; Windows tray "Open picker" copies only).
- Gates: developer pass · tester open · reviewer open · QA open · PM merge waiting
- Open findings: none yet. Not verified: real Mac window behaviour (borderless picker, focus return, toast without stealing focus), real paste, timings, Windows bridge compile
- Decisions: lead decisions on spec gaps — `paste_mode` stays internal in M1.3 (no UI control; only "Allow pasting" sets it); new copy "Couldn't save the shortcut. Try again." accepted; toast 360×96 near the pointer for 4 s accepted; Mac shortcut label shows the key-position letter (covered by the non-QWERTY Later line)
- Blockers: none

## 2026-11-04 — M1.3 History picker and paste — PM deck approval
- Changed: design docs merged to main and marked approved; ADR 0003 accepted; plan updated with the new ACs, decisions and 3 Later lines.
- Gates: n/a — design approval
- Open findings: none
- Decisions: PM said (2026-11-04): "approve and proceed" — in answer to "Do you approve step 3 with my recommendations on slide 9?" (direct notarised Mac download with the sandbox on; default shortcut ⌘⇧V / Ctrl+Shift+V; pasted item stays on the clipboard; approve design and screen spec). Before that the PM asked what "Paste only into the app you were using" means; the lead explained the focus check.
- Blockers: none

## 2026-11-04 — Main branch CI after the M1.2 merge
- Changed: CI run 41700921138 on main (3a702f9): Windows pass; macOS cancelled by GitHub with no runner (fifth time). The PM risk acceptance's condition ("the next macOS CI run that completes on main must be green") is still open.
- Gates: n/a — CI
- Open findings: none
- Decisions: none; the M1.3 design moves the macOS job to the pinned `macos-15` runner label
- Blockers: Lead — GitHub `macos-latest` capacity

## 2026-11-04 — M1.3 History picker and paste — Design
- Changed: on branch `design/history-picker`: ADR 0003 (direct notarised Mac download, App Sandbox kept on, PostEvent only), design note `docs/design/history-picker.md`, UI spec `docs/ui/history-picker.md`, deck `docs/slides/history-picker.html`. Size: large — new OS permission, global shortcut, cross-app focus, new UI.
- Gates: n/a — design; PM deck approval waiting
- Open findings: none
- Decisions: waiting — Mac distribution, default shortcut, clipboard after paste, design approval
- Blockers: Lead waiting for PM deck approval
- Sources: Apple DTS on PostEvent/ListenEvent vs Accessibility in the sandbox, and a 2.4.5 rejection: https://developer.apple.com/forums/thread/820594 ; sandboxed clipboard managers needing manual paste: https://dev.to/eduardo_revillavaquero_0/i-shipped-a-clipboard-manager-inside-the-macos-app-store-sandbox-heres-what-works-and-what-5a30 ; Windows UIPI blocks SendInput to higher-integrity windows silently: https://docs.rs/win-text-inject/0.1.1/src/win_text_inject/target.rs.html

## 2026-11-03 — M1.2 Clipboard history — Merged
- Changed: PR https://github.com/Thamzy265/kusunga/pull/2 merged to main (3a702f9). Lead ran the check on main: 385 tests pass. M1.2 ticked in the plan.
- Gates: developer pass · tester pass · reviewer approve · QA pass · PM merge approved (macOS CI covered by the PM risk acceptance of 2026-11-03)
- Open findings: none. Follow-ups: the first macOS CI run that completes on main must be green (risk acceptance); clean up old test data on this Mac (old `uk.org.cgatechnologies.kusunga` container and keychain item, `kusunga.db.unreadable-*` test files) — PM to approve
- Decisions: PM said (2026-11-03): "Approve merge" — in answer to "Do you approve merging step 2 through the GitHub pull request?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead macOS CI capacity on GitHub
- Lessons: (1) unsigned builds re-prompt for the login keychain after each rebuild — plan real-app QA as one build per round with the PM present; (2) synthetic clicks can miss real bugs (Cmd+Z) — use System Events keystrokes; (3) GitHub `macos-latest` capacity failed 4 times — consider a different macOS runner label for M1.3

## 2026-11-03 — M1.2 Clipboard history — PM checks; waiting for merge approval
- Changed: PM checked light appearance and VoiceOver labels on the real app.
- Gates: developer pass · tester pass · reviewer approve · QA pass (PM checks done) · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-03): "Both look fine" — in answer to "Tell me how the light-mode and VoiceOver checks went."
- Blockers: none

## 2026-11-03 — M1.2 Clipboard history — Reviewer: approve
- Changed: reviewer confirmed the PM risk acceptance entry and its scope and approved 46a354e plus the QA docs commits (pushed to the PR branch). All findings across all rounds fixed, with regression tests.
- Gates: developer pass · tester pass · reviewer approve · QA pass (PM checks open: light appearance, VoiceOver) · PM merge waiting
- Open findings: none. Gaps noted: AC1 latency p95 and idle CPU not re-measured on the final poller (first-tick reads unchanged; retried reads add one 250 ms tick)
- Decisions: none new
- Blockers: PM checks: light appearance, VoiceOver

## 2026-11-03 — M1.2 Clipboard history — PM risk acceptance: macOS CI
- Changed: none in code. The gate "macOS CI green on the final head" is replaced by local macOS evidence for M1.2 only.
- Gates: developer pass · tester pass · reviewer approve (CI condition covered by the risk acceptance below) · QA pass (PM checks open: light appearance, VoiceOver) · PM merge waiting
- Open findings: none
- Decisions: Risk accepted by PM (2026-11-03): accepted: merging without a completed GitHub macOS CI job; a build or test problem that only shows on a clean macOS runner could be missed — scope: M1.2, branch `feat/clipboard-history`, heads f571105..46a354e (+ QA docs commits), gate "macOS CI on the final head"; evidence used instead: local `./tool/check.sh` (385 tests), local XCTest (55), QA real-app pass on 46a354e, Windows CI pass (run 41678344669) — expiry/review: the next macOS CI run that completes on main must be green; if it fails, the lead treats it as a bug in M1.2 — PM said: "Accept local results"
- Blockers: PM checks: light appearance, VoiceOver

## 2026-11-03 — M1.2 Clipboard history — macOS CI cancelled again
- Changed: the PM-approved re-run of the macOS job (run 41678344669) waited 15 minutes and was cancelled by GitHub with no runner (fourth time; 0 steps ran). Windows passed. The same checks pass locally on 46a354e (reviewer: check.sh 385, XCTest 55; QA real-app pass).
- Gates: developer pass · tester pass · reviewer approve pending macOS CI · QA pass (PM checks open) · PM merge waiting
- Open findings: none
- Decisions: waiting for PM — how to get macOS CI evidence
- Blockers: Lead — GitHub `macos-latest` runner capacity; needs a PM decision

## 2026-11-03 — M1.2 Clipboard history — QA pass on 46a354e
- Changed: QA (badfdf8, on the branch) re-ran on the PM-launched build. All 7 ACs pass: 304 of 304 fast copies saved (0.3–0.6 s spacing); Cmd+Z restores a deleted row in the list and undoes typing in the Keep field without restoring the row; Home/End and Cmd+Up/Down work; history survives tray Quit + relaunch with no keychain prompt; secret-marked copies still skipped; no paste alert seen. Gap: AC1 latency p95 (286 ms) was measured on c8d4ebf and not re-timed on the new poller.
- Gates: developer pass · tester pass · reviewer approve once macOS CI is green · QA pass (PM checks open: light appearance, VoiceOver) · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: CI — macOS job of run 41678344669 still queued on GitHub (Windows passed) · PM checks: light appearance and VoiceOver

## 2026-11-03 — M1.2 Clipboard history — PM go-aheads for CI and QA
- Changed: lead re-ran the cancelled macOS CI job of run 41678344669. PM opened the final QA build (46a354e) and answered the keychain prompt; QA running.
- Gates: developer pass · tester pass · reviewer approve once macOS CI is green · QA running · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-03): "Yes, re-run it" — in answer to "May I re-run the cancelled Mac check on GitHub?". PM said (2026-11-03): "Done, Always Allow" — in answer to "Tell me once you've opened the app and clicked Always Allow."
- Blockers: none

## 2026-11-03 — M1.2 Clipboard history — Reviewer: code approved; macOS CI blocked
- Changed: 46a354e fixes the reviewer's Low note (re-hold instead of drop). 385 Dart + 55 XCTest pass locally. CI run 41678344669: Windows pass (389 tests); macOS cancelled by GitHub (no runner), third time in a row. The reviewer's attempt to re-run the job was denied by the permission system; the lead did not run it either.
- Gates: developer pass · tester pass · reviewer approve once a macOS CI job is green · QA re-run open · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Reviewer/Lead — re-running the macOS CI job needs the PM's go-ahead (`gh run rerun 41678344669 --failed`) · QA needs the PM for the keychain prompt · others none

## 2026-11-03 — M1.2 Clipboard history — Reviewer: code approved, CI incomplete
- Changed: R1 and R2 fixed in ca5e4ef and confirmed (new undo tests fail on the old code). CI run 41675125996: Windows pass (389 tests); macOS job cancelled by GitHub again (no macOS runner available, second time).
- Gates: developer fixing one Low note · tester pass · reviewer approve pending a green macOS CI job · QA re-run open · PM merge waiting
- Open findings: none open; Low note (a copy whose types change on the confirming tick is dropped) sent to the developer
- Decisions: lead fixes the Low note before the final CI and QA run (AC1 is about not losing copies)
- Blockers: Reviewer/Lead — macOS CI on GitHub has had no runner twice; will retry on the next push · others none

## 2026-11-03 — M1.2 Clipboard history — Reviewer re-check: block
- Changed: reviewer checked f571105. Lost-copies retry is safe against late secret markers except one narrow writer-order case (R2). CI run 41671502357: Windows pass (383 tests, 4/4 Credential Manager); macOS job cancelled by GitHub (no runner) — re-runs on the next push.
- Gates: developer fixing · tester pass · reviewer block · QA re-run open · PM merge waiting
- Open findings: Medium R1 — Cmd/Ctrl+Z is swallowed in the Keep field, and with a pending delete it restores the deleted row instead; Low R2 — a writer that adds the secret marker after the text could be read on a retry
- Decisions: lead decision — when macOS paste access is Ask or Deny, the watcher does not retry (one read per change), so users never see repeated system alerts for one copy
- Blockers: Developer none · Tester none · Reviewer macOS CI must complete on the final head · QA none · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — Developer fixes for QA failures
- Changed: 6c668bd (poller retries for up to 8 ticks / 2 s when a copy's text isn't ready yet; verified 100/100 at 0.6 s and 0.3 s in a driver outside the app, old poller 99/100) and f571105 (Edit menu no longer takes Cmd+Z; End/Home reach rows not built yet; Cmd+Up/Down on Mac). 379 tests pass; lead re-ran the check. Pushed.
- Gates: developer pass · tester pass · reviewer re-check open · QA re-run open · PM merge waiting
- Open findings: none open on the developer side; real-app Cmd+Z and Home/End unconfirmed
- Decisions: none
- Blockers: QA — every rebuild of the unsigned app brings back the login-keychain prompt, so the PM must click Always Allow again for the QA re-run (QA will use one build for the whole re-run) · others none

## 2026-11-03 — M1.2 Clipboard history — QA: two failures
- Changed: QA (99fa529, on the branch) finished the real-app run with the real key. Pass: AC2, AC3, AC4 (DB unreadable without the key; history survives tray Quit and Cmd+Q), AC5 (Mac), AC7, 360 px layout, long rows, privacy (no sockets, container-only files, codes-only log). No macOS paste alert seen.
- Gates: developer fixing · tester pass · reviewer approve (re-check needed after fixes) · QA fail · PM merge waiting
- Open findings: FAIL AC1 completeness — about 1.7% of copies 0.6 s apart are silently lost; FAIL AC6 — Cmd+Z does not undo a delete (toast Undo works); probable — End/Home do not move focus to last/first row
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA re-runs after fixes; PM checks still to do: VoiceOver, light appearance, Home/End by hand · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — PM check for QA
- Changed: PM unlocked the Mac, launched the debug app and answered the login-keychain prompt. QA sent back to finish.
- Gates: developer pass · tester pass · reviewer approve · QA open · PM merge waiting
- Open findings: none
- Decisions: PM said (2026-11-03): "Done, Always Allow" — in answer to "Tell me when the Mac is unlocked and you've clicked Always Allow."
- Blockers: none

## 2026-11-03 — M1.2 Clipboard history — QA partial (needs PM)
- Changed: QA (d5f9e79, on the branch) ran the real Mac app with the screen locked and the keychain prompt unanswered. Pass: AC1 (p95 286 ms over 25 copies), AC2, AC3, AC5 (Mac markers), AC7 (memory-only banner, nothing written unencrypted); no network sockets; idle CPU 0.11%; accessBehavior "allowed". Not shown: AC4 encryption and persistence, AC6 UI paths, keyboard, narrow window, accessibility. Evidence: docs/qa/m1.md (M1.2), 4 screenshots.
- Gates: developer pass · tester pass · reviewer approve · QA open (partial) · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: QA needs the PM to unlock the Mac, keep it awake, and answer the keychain prompt with Always Allow once · others none

## 2026-11-03 — M1.2 Clipboard history — Reviewer: approve
- Changed: F1 fixed (c8d4ebf). CI run 41655738313 green on both OSes: macOS 376 tests + XCTest + C++ policy; Windows 380 tests incl. 4/4 real Credential Manager tests, Windows build OK. All findings from three review rounds fixed; mutation checks confirm the key tests. M1.9 gets two reviewer notes (licence notice; sqlite3mc from source decision).
- Gates: developer pass · tester pass · reviewer approve · QA open · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA may need the PM to answer the Mac keychain prompt once · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — Reviewer re-check: block (one Medium)
- Changed: all 8 earlier findings fixed and confirmed with mutation checks. CI run 41651232375 green on macOS and Windows (373 tests, Windows build).
- Gates: developer fixing · tester pass · reviewer block · QA open · PM merge waiting
- Open findings: Medium N1 (the real Windows Credential Manager code is never run by a test); Low N2 (tray Quit can leave an invisible process for up to 30 s), N3 (new "incompatible" banner missing from the UI spec)
- Decisions: lead sends N1–N3 to the developer now (fix rather than a dated plan task)
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — Developer fix round 2
- Changed: 4 commits to b375b14 fix C1, D1 (Windows Credential Manager), T1, W1, U1, U2, K1 (raw hex key), K2 (30 s, own log code). 373 tests pass; lead re-ran the check. Developer corrected the earlier stack reading: the keychain call blocks on the plugin's own queue, main thread idle. Real launches: after some rebuilds the login-keychain call blocks until the 30 s timeout (likely an access prompt), then memory-only with the banner.
- Gates: developer pass · tester pass · reviewer re-check open · QA open · PM merge waiting
- Open findings: none open on the developer side; Windows Credential Manager and the new C++ compile only in CI
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA likely needs the PM to answer a macOS keychain prompt once ("Always Allow") to test the encrypted path in the real app · Marketer none · Lead none

## 2026-11-03 — M1.2 Mac Keychain — PM decision
- Changed: plan M1.9 gets a must-do AC to move the key to the data-protection keychain with a key move before the first external beta.
- Gates: n/a — decision
- Open findings: none new
- Decisions: PM said (2026-11-03): "Login keychain for now" — in answer to "Which Mac Keychain approach should step 2 use?" (options: login keychain for now, or buy the Apple Developer account now).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — Reviewer: block
- Changed: reviewer blocked 55750fc. CI run 41648582715 passed on macOS and Windows (first Windows compile of the bridge). No high-confidence security vulnerabilities; supply chain OK (sqlite3mc binary SHA-256 pinned via the package).
- Gates: developer fixing · tester pass · reviewer block · QA open · PM merge waiting
- Open findings: Medium C1 (a newer or failed-migration history is moved aside and later deleted by Clear history — data loss on downgrade), D1 (Windows key is a DPAPI file next to the DB, not Credential Manager as approved), T1 (keychain timeout untested); Low W1 (Windows shutdown use-after-return), U1 (menu name), U2 (limit field hover), K1 (key used as passphrase, not raw key), K2 (timeout log code); developer's Later line rejected (no measurable trigger)
- Decisions: lead decisions — C1: leave the file untouched and run memory-only with a distinct banner; D1: implement Credential Manager (keep the approved AC); K1: switch to raw hex key now; K2: timeout 30 s with its own log code
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM: Mac Keychain approach (reviewer view: login keychain until M1.9, then a must-do switch with a key move before the first external beta)

## 2026-11-03 — M1.2 Clipboard history — Developer fix round
- Changed: 5 commits to 55750fc fix BUG-1..18, apply lead decisions (1 MiB UTF-8 cap, Windows fail closed, flush retry, CI temp-folder fix) and PM decisions (id `com.wnasoni.kusunga`, owner "William Nasoni"). 364 Dart + 43 XCTest + C++ policy checks pass; lead re-ran the check: 364 pass. Developer added a 15 s keychain timeout after a real launch blocked on a legacy-keychain prompt.
- Gates: developer pass · tester pass (repros green) · reviewer open · QA open · PM merge waiting
- Open findings: none open from the tester. Lead confirms BUG-14 copy "Couldn't save that number. Try again."
- Decisions: none new
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM: Mac Keychain approach (new evidence: the login keychain can show a macOS access prompt after a rebuild)

## 2026-11-03 — M1.2 Clipboard history — Tester hand-off
- Changed: tester added 179 Dart tests, 28 XCTests, ~100 C++ checks (061145c..42c8a08). Dart 340 pass / 24 fail (the 24 are bug repros). Mutation checks confirm key tests bite. CI: macOS pass; Windows compiled but tests failed on temp-folder cleanup.
- Gates: developer fixing · tester findings open · reviewer open · QA open · PM merge waiting
- Open findings: 18 bugs — Medium-High BUG-1 (NUL text blocks all later saves); Medium BUG-5 (unsaved copies not de-duplicated), BUG-7 (Clear history leaves backup files — privacy), BUG-15 (row overflows at 360 px / 200% text); Medium-Low BUG-8, 9, 12, 16, 17; Low BUG-2, 3, 4, 6, 10, 11, 13, 14, 18
- Decisions: lead decisions (technical): item size cap is 1 MiB of UTF-8 bytes (not characters) to keep the 50 MB worst case; Windows secret check fails closed when a marker is unreadable; flush retries waiting copies on quit; developer also applies the identifier and owner-name changes
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM: Mac Keychain approach

## 2026-11-03 — Owner name — PM decision
- Changed: none yet; developer applies it with the identifier change.
- Gates: n/a — decision
- Open findings: none
- Decisions: PM said (2026-11-03): "William Nasoni" — in answer to "What name should show as the app's owner in the copyright and Windows company fields?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM: Mac Keychain approach

## 2026-11-03 — App identifier — PM decision
- Changed: none yet. Developer changes the identifier on `feat/clipboard-history` after the tester hands off (to avoid two writers on one branch).
- Gates: n/a — decision
- Open findings: none
- Decisions: PM said (2026-11-03): "no dont use that organisation id, use com.wnasoni.kusunga," — replaces `uk.org.cgatechnologies.kusunga` everywhere (bundle id, test bundle id, channel names, keychain account, copyright and Windows company fields, docs).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM: name to show as copyright holder / Windows company; Mac Keychain approach (still open)

## 2026-11-03 — M1.2 Clipboard history — Developer hand-off
- Changed: branch `feat/clipboard-history` (HEAD 5b0e9f1, 9 commits), draft PR https://github.com/Thamzy265/kusunga/pull/2 for CI only. 185 Dart tests + 14 XCTest + C++ policy test pass. Real macOS run: copies appear, all 3 Mac secret markers skipped, 1.2 MB copy skipped, DB file not readable as plain SQLite, history survives quit. Lead re-ran the check: 185 pass.
- Gates: developer pass (with a blocker) · tester open · reviewer open · QA open · PM merge waiting
- Open findings: none yet. Not verified: Windows native code (first compile in CI), tray Quit by real click, VoiceOver, setup card on a real Mac, 5,000-item performance. Build hook downloads sqlite3mc binaries from GitHub at build time (for the reviewer).
- Decisions: lead decisions on spec gaps — encryption-unavailable banner gets its own text; ⋯ button name "More options"; tooltip capped at 2,000 characters. Waiting for PM: Mac Keychain (below).
- Blockers: Developer Mac data-protection Keychain refuses the unsigned build (errSecMissingEntitlement -34018); workaround on the branch uses the login keychain — PM decides · Tester none · Reviewer none · QA none · Marketer none · Lead same

## 2026-11-03 — M1.2 Clipboard history — PM deck approval
- Changed: PM approved the deck, design note, ADR 0002 and UI spec. Plan updated with the new ACs and Later lines. ADR 0002 accepted.
- Gates: n/a — design approval
- Open findings: none
- Decisions: PM said (2026-11-03): "Approve as is" — in answer to "Do you approve step 2 with my recommendations on slide 9?" (default 200 items, range 10–5,000; keychain failure → memory only with a warning; Apple Developer account only if needed; move secret-marker skip and delete/clear into M1.2; approve design and screen spec).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.2 Clipboard history — Design
- Changed: on branch `design/clipboard-history`: design note `docs/design/clipboard-history.md`, ADR 0002 (encrypted SQLite, key in keychain), UI spec `docs/ui/clipboard-history.md`, deck `docs/slides/clipboard-history.html`. Size: large — new data store, personal data, native code. Proposed scope change: secret-marker skip (from M1.6) and delete/clear (from M1.8) move into M1.2.
- Gates: n/a — design; PM deck approval waiting
- Open findings: none
- Decisions: waiting — default limit, keychain failure behaviour, Apple Developer account timing, scope change and approval
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead waiting for PM deck approval
- Sources: macOS pasteboard privacy status https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4/ ; sqlcipher_flutter_libs EOL https://pub.dev/packages/sqlcipher_flutter_libs

## 2026-11-03 — M1.1 Project setup — Merged
- Changed: PR https://github.com/Thamzy265/kusunga/pull/1 merged to main (7f26136) after CI run 41618587160 passed on macOS and Windows. M1.1 ticked in the plan.
- Gates: developer pass · tester pass · reviewer approve with notes · QA pass · PM merge approved
- Open findings: Minor — status item accessibility label is generic (polish later)
- Decisions: PM said (2026-11-03): "Approve merge" — in answer to "Do you approve merging step 1 through the GitHub pull request?"
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none
- Lessons: unit tests with fake plugins missed that the tray menu never opened; for native plugin code, add a mocked-channel test and a real-app click by QA

## 2026-11-03 — M1.1 Project setup — QA pass; waiting for PM merge approval
- Changed: developer fixed N1–N3 (3aaac53). QA (8dc3f2b) ran the real macOS app: window, menu-bar icon, menu "Open Kusunga"/"Quit", close hides, reopen, Quit — all pass. CI run 41617801471 passed on macOS and Windows (34 tests, debug builds). No network use in the release build; files only in the app container. Evidence: `docs/qa/m1.md`, 3 screenshots in `docs/qa/m1/screens/`. No video (could not crop to the app without capturing the desktop).
- Gates: developer pass · tester pass · reviewer approve with notes (N1–N3 fixed) · QA pass (light mode and Windows runtime not observed — optional PM checks) · PM merge waiting
- Open findings: Minor — status item accessibility label is the generic "status menu" (polish later)
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.1 Project setup — Reviewer re-check: approve with notes
- Changed: all 10 round-1 findings fixed. CI run 41616011334 passed on macOS and Windows (34 tests, debug builds). This meets the CI half of the AC; QA still checks the real window and tray.
- Gates: developer fixing N1–N3 · tester pass · reviewer approve with notes · QA open · PM merge waiting
- Open findings: Low N1 (Windows close could leave a headless process), N2 (Dock click doesn't reopen window), N3 (checkout v4 on deprecated Node 20) — lead sent all three to the developer before QA
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.1 Project setup — PM decision on CI; developer fix round 2
- Changed: developer fixed all reviewer findings (4a76a25, 1c4c70e): tray click opens the menu, close hides the window, "Open Kusunga" + "Quit" menu, Dependabot, SHA-pinned actions. 34 tests pass. Added `window_manager` ^0.5.2 (Dart 3.12 limit). Tray click confirmed only by a mocked-channel test, not by a real click.
- Gates: developer pass · tester pass · reviewer re-check open · QA open · PM merge waiting
- Open findings: none open on the developer side; reviewer re-check pending
- Decisions: PM said (2026-11-03): "Private GitHub repo" — in answer to "How should we check the Windows side of step 1?" (option: create a private GitHub repo for Kusunga and push the branch so CI runs on Mac and Windows).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — M1.1 Project setup — Reviewer: block
- Changed: reviewer blocked the branch. C1: clicking the menu-bar/tray icon does not open the Quit menu on either OS (tray_manager needs popUpContextMenu on click); unit tests used fakes so missed it. Check passes (23 tests); macOS debug build passes.
- Gates: developer fixing · tester pass · reviewer block · QA open · PM merge waiting
- Open findings: C1 blocking; D1 medium (no dependency check); Low: S1 (actions not SHA-pinned), D2 (closing window quits app), D3 (tray started before window), C2, C3, C4, T1; T2 cleanup
- Decisions: lead sends all findings to the developer now (D1 fixed with Dependabot, not deferred). Lead adds plan tasks: ADR on macOS distribution + App Sandbox before M1.3; Hardened Runtime in M1.9
- Blockers: Developer none · Tester none · Reviewer Windows half of the AC and CI unverified — needs a GitHub remote or a Windows machine (PM) · QA none · Marketer none · Lead same as reviewer

## 2026-11-03 — M1.1 Project setup — Developer fix round
- Changed: c872379 fixes B1, F1, F2, F3; F4 left as TODO(M1.2); CI permissions and triggers tidied. Lead re-ran the check: exit 0, 23 tests.
- Gates: developer pass · tester pass (findings fixed) · reviewer open · QA open · PM merge waiting
- Open findings: none open (F4 tracked as TODO for M1.2)
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead Windows not verified locally; CI has never run

## 2026-11-03 — M1.1 Project setup — Tester hand-off
- Changed: tester added 21 tests (24 total, 23 pass). B1 repro fails on purpose. Check script verified to fail on bad format, failing tests and analyzer errors.
- Gates: developer pass · tester findings open · reviewer open · QA open · PM merge waiting
- Open findings: B1 medium (start twice → double Quit), F1 medium (tray failure stops the app opening), F2 low (port never removes listener), F3 low (no dark theme), F4 low (exit(0) skips cleanup — note for M1.2)
- Decisions: lead decision (technical, not a PM decision): on tray failure the app still opens its window and logs the error; tray is removed if partly set up
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead Windows not verified locally; CI has never run

## 2026-11-03 — M1.1 Project setup — Developer hand-off
- Changed: branch `chore/project-setup` (bce7f8f, f884487). Flutter app for macOS + Windows, "Kusunga" window, menu-bar/tray icon with Quit (`tray_manager` pinned 0.5.3 for Dart 3.12), check command `./tool/check.sh` / `.\tool\check.ps1`, CI workflow, README, ADR 0001. Size: small. Lead re-ran the check: 4 tests pass.
- Gates: developer pass · tester open · reviewer open · QA open · PM merge waiting
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead Windows not verified locally; CI has never run (no remote)

## 2026-11-03 — MVP plan (M1 desktop) — PM approval
- Changed: PM approved the plan and deck. Decisions recorded in `docs/PLAN.md` ("Decided"). DPIA added to M1.9.
- Gates: n/a — planning
- Open findings: none
- Decisions: PM said (2026-11-03): "Approve as is" — in answer to "Do you approve the plan with my recommendations on slide 9?" (Flutter, vault in M2, no crash reports in M1, a short DPIA before the beta, approve the plan).
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none

## 2026-11-03 — MVP plan (M1 desktop) — Plan
- Changed: wrote `docs/PLAN.md` (M1 desktop MVP with 9 items, M2–M4 outline, Later list with triggers), `CLAUDE.md` Team setup, and the deck `docs/slides/mvp-plan.html`. Plan is based on `docs/marketing/competitor-research.md`.
- Gates: developer n/a — planning · tester n/a — planning · reviewer n/a — planning · QA n/a — planning · PM merge n/a — planning; PM deck approval waiting
- Open findings: none
- Decisions: PM said "Yes, draft the plan" (2026-11-03), choosing desktop first (Mac and Windows), then the mobile keyboard. Waiting on D1 stack, D2 vault timing, D3 crash reports, DPIA decision, plan approval.
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead check command unknown until the PM chooses the stack (D1)

## 2026-10-29 — Competitor research — Research
- Changed: marketer wrote `docs/marketing/competitor-research.md` (21 apps). No app combines clipboard history, typed snippets and encrypted sync on all four platforms. Mobile cannot record background clipboard history.
- Gates: n/a — research only
- Open findings: none
- Decisions: none
- Blockers: Developer none · Tester none · Reviewer none · QA none · Marketer none · Lead none
