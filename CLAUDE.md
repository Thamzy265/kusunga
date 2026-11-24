# Kusunga

A clipboard history and saved-snippets app for Mac, Windows, iOS and Android. It keeps what you copy (up to a limit you set) and lets you save things you paste often, such as your phone number, email, links or bank details, and paste them with a shortcut.

## Team setup

- Plan: `docs/PLAN.md` (with a "Later" section)
- Status log: `docs/status.md`
- QA evidence: `docs/qa/<milestone>.md`, screenshots in `docs/qa/<milestone>/screens/`, videos and traces in `qa-artifacts/` (git-ignored)
- Design notes `docs/design/`, ADRs `docs/adr/`, UI specs `docs/ui/`, slides `docs/slides/`, marketing `docs/marketing/`
- Project phase: `MVP`
- Privacy regions: UK + EU
- Check command: `./tool/check.sh` (Windows: `.\tool\check.ps1`) — runs `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`. Stack: Flutter 3.50.1 / Dart 3.14.0 (ADR 0001, 0008)
- End-to-end tools: TBD (desktop UI automation, chosen when the first UI flow needs it; Maestro for mobile later)
- Approved tools: Flutter 3.50.1 SDK side by side — `git clone --depth 1 --branch 3.50.1 https://github.com/flutter/flutter.git /Users/williamnasoni/Developer/flutter-3.50.1` — approved 2026-11-24
