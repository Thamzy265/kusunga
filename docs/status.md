# Status log

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
