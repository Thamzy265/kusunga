# Status log

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
