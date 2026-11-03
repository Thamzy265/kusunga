# Status log

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
