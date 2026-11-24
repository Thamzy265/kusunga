# Flutter 3.50.1 (M1.10a) — design note

Date: 2026-11-24 — Size: large — the SDK change touches the whole app, the build on both platforms and CI — Phase: MVP — Status: approved by PM 2026-11-24 ("Approve, all A"; deck `docs/slides/flutter-3-50.html`)

## Context

M1.10 (dependency updates) cannot start on Flutter 3.44.6 / Dart 3.12.2 (ADR 0001): sqlite3 >= 3.6.0, window_manager >= 0.6.0 and tray_manager >= 0.7.0 all need Flutter 3.50 / Dart 3.14 (lookup 2026-11-23, `docs/status.md`). The PM chose "Flutter first, then pkgs" (2026-11-24). This item moves the app to Flutter 3.50.1 and changes nothing else that 3.50.1 does not force. M1.10b then updates the three packages.

Facts (lookup 2026-11-24; sources in the status log entry for this note):
- Flutter 3.50.1 is the current stable (released 2026-11-20) and ships Dart 3.14.0. 3.50.0..3.50.1 is 13 small tool/engine fixes.
- `package:flutter/material.dart` still works but is deprecated in 3.50: Material and Cupertino moved to the `material_ui` and `cupertino_ui` packages (1.0 since 3.47). `flutter analyze` fails on infos here (`analysis_options.yaml`), so the 118 files that import it (lib 22, test 96) would fail the check. `dart fix --apply --code=migrate_design_widgets` rewrites the imports; `material_ui` is added to `pubspec.yaml` by hand.
- Old and new Material types do not mix. A compatibility bridge exists for packages that still use the old library.
- The macOS 27 `lipo` failure (M1.9 AC, workaround `ARCHS = arm64`) is fixed in Flutter 3.47.0 and later (Flutter PR 188625).
- Minimum macOS 12 (the repo already uses 12.0), Xcode 15, Visual Studio 2019: unchanged for us. The Windows runner template changed only cosmetically.
- Every current direct dependency resolves on 3.50.1; no package bump is forced. The SDK-pinned packages move (`meta` 1.19.0, `test_api`, `matcher`).
- No other 3.47 / 3.50 breaking change hits the repo (`describeEnum`, `withOpacity`, `pushNamed`, `WidgetSpan`, `ignoreSemantics` and the rest: 0 uses).

## Requirements and non-goals

- Functional: the app, all tests and the release build guards work as today on Flutter 3.50.1.
- Non-functional: `./tool/check.sh` and `.\tool\check.ps1` pass with no new analyzer ignores; both CI jobs pass; the PM's other projects keep their Flutter 3.44.6.
- Non-goals: the three package updates (M1.10b); raising the Dart language version in `pubspec.yaml` (`sdk: ^3.12.2` stays, so `dart format` keeps the 3.12 style; M1.10b raises it in its own formatting commit); a universal (Intel) Mac build (decision F3).

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| No behaviour change | Same tests pass, same count apart from those the migration rewrites | `./tool/check.sh` before and after; QA main flows in the qa profile |
| Data integrity | History and snippets made on 3.44.6 open unchanged | QA opens the qa profile's existing data after the upgrade |
| Reproducible toolchain | One Flutter version everywhere | CI `flutter-version`, CLAUDE.md, ADR 0008 and `docs/licences.md` all say 3.50.1; a `test/ci` check compares them |

## Estimate

n/a — no load change.

## Data

No schema, store or format change. The SQLite library (sqlite3 3.5.2, SQLite3 Multiple Ciphers 2.5.0) does not change in this item.

## Options

### A: side-by-side SDK, migrate to `material_ui` now
- Install Flutter 3.50.1 in its own folder next to 3.44.6. The team uses it by path; the PM's 3.44.6 and its projects stay as they are.
- Run `dart fix` for the Material imports, add `material_ui`, keep the analyzer gate strict.
- Cost: a large but mechanical diff (about 118 files, imports only). Effort: about one developer round.

### B: upgrade the existing SDK in place, silence the deprecation
- `flutter upgrade` in `/Users/williamnasoni/Developer/flutter`; add an analyzer ignore for the Material deprecation and migrate later.
- Smaller diff now, but it changes the SDK the PM's other projects use, and an ignore can hide real deprecations. Effort: smaller.

## Decision

Option A. PM approved F1 A, F2 A and F3 A on 2026-11-24 ("Approve, all A"). ADR 0008 (proposed) records the version change and supersedes the version line in ADR 0001.

## Failure plan

No outbound calls at run time. Build-time downloads (Flutter SDK, pub packages, sqlite3mc binaries) keep their pins: the Flutter git tag, `pubspec.lock` hashes, and the sqlite3 package's binary hashes.

## Observability

n/a — no run-time change. The CI logs are the evidence.

## Trust boundaries and abuse cases

- Boundaries: the Flutter SDK download (git tag from github.com/flutter/flutter) and the new `material_ui` package from pub.dev.
- Abuse case: "As an attacker I publish a look-alike package so that the build pulls my code" — mitigation: `material_ui` is published by flutter.dev (verified publisher); the lockfile pins its hash; the reviewer checks the publisher.
- Abuse case: "As an attacker I change a Flutter tag" — mitigation: install by tag 3.50.1 and record its commit hash in the status log; CI's `flutter-action` pins the same version.

## Privacy

n/a — no personal data, store or processing changes.

## Rollout and rollback

- One branch, `chore/flutter-3-50`, pushed with a pull request (CI is the Windows evidence).
- Order: install the SDK (PM-approved command) → developer runs the check on 3.44.6 for a baseline → switches to 3.50.1, migrates the imports, updates every version pin together → tester → reviewer → QA → PM merge.
- Rollback: revert the merge commit; the 3.44.6 SDK stays installed, so the team switches back by path. No data step.

## Later lines

- Update the trigger of "Universal (Intel + Apple silicon) Mac build": its "pinned Flutter is upgraded past 3.44.6" part fires with this item. If F3 is "keep Apple silicon only", the new trigger is "≥ 1 tester or user asks for an Intel build" — noted 2026-11-24 by lead.

## Decisions for the PM

- **F1. Where Flutter 3.50.1 goes:** A: a new folder `/Users/williamnasoni/Developer/flutter-3.50.1` (recommended — your 3.44.6 and its projects are untouched; delete the folder to undo) · B: upgrade `/Users/williamnasoni/Developer/flutter` in place. Either way you approve the exact install command first.
- **F2. Material deprecation:** A: migrate to `material_ui` in this item (recommended — the check stays strict; mostly an automatic rewrite) · B: ignore the deprecation now and migrate later (a weaker gate, which is a risk you accept, with a Later trigger).
- **F3. Mac architectures:** A: keep Apple silicon only (recommended — your D3 decision stands, no Intel Mac to test on) · B: build universal now that the lipo bug is fixed.
