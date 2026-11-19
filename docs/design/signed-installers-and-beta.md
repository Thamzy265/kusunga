# M1.9 Signed installers and first beta — design note

Date: 2026-11-19 — Author: lead — Size: large — release; new trust boundaries (signing keys, distribution channel); moves the history key — Phase: MVP — Status: approved by PM 2026-11-19 (D1–D7 as recommended)

UI spec: `docs/ui/about-and-licences.md` — Deck: `docs/slides/signed-installers-and-beta.html` — ADRs: 0006 (accepted), 0007 (accepted)

## Context

M1.1–M1.8 and the licence item are on main. M1.9 turns the app into something other people can install. It is the last M1 item.

What exists today (main at 02369fb, scout lookup 2026-11-19):

- **Mac**
  - Sandboxed. Release entitlements are `app-sandbox` and `files.user-selected.read-write` only.
  - Signing: Hardened Runtime is not set. Signing is Automatic, and the team comes from an optional, git-ignored `Local.xcconfig`. Without that file the build is ad-hoc signed.
  - Minimum macOS is 12.0. `ARCHS` is not set.
  - Release builds fail on macOS 27 with Flutter 3.44.6: the new `lipo` takes one architecture per `-verify_arch` (status log 2026-11-05).
- **Mac key**
  - `flutter_secure_storage`, using the **login keychain** (`usesDataProtectionKeychain: false`).
  - Account `com.wnasoni.kusunga`, entry `history_db_key`.
  - Read and created in `lib/history/history_opener.dart:93-98`, deleted in `lib/data/data_eraser.dart:126`.
- **Windows**
  - The key is a generic credential in Credential Manager, `com.wnasoni.kusunga/history_db_key`.
  - There is no installer, no MSIX config and no signing. `Runner.rc`: CompanyName "William Nasoni", ProductName "Kusunga".
- **Test-only switch:** `-KusungaAcceptSyntheticKeys` exists only inside `#if DEBUG` (`macos/Runner/TypedShortcutCore.swift:282-287`). Swift tests cover it. No release-binary guard exists yet.
- **Licences:**
  - There is no About or licences screen, and nothing calls `showLicensePage` or `LicenseRegistry`.
  - `docs/licences.md` lists every dependency.
  - SQLite3 Multiple Ciphers and SQLite are not in Flutter's NOTICES.
- **Release set-up:**
  - Version `1.0.0+1`. There are no release notes and no CHANGELOG.
  - The only workflow is `check.yml`, with jobs macos and windows.
  - There is no DPIA document yet (`docs/design/dpia.md` is planned).
- **Repo:**
  - Public since 2026-11-19, GPL-3.0-only.
  - Main is protected against force pushes and deletion.
  - CI is running on GitHub-hosted runners again; run 44550682517 was in progress when this was written.

## Requirements and non-goals

Acceptance criteria (docs/PLAN.md, M1.9), numbered here:
- **AC1 About / licences screen:**
  - the GPL notice (GPLv3 section 5(d)) and every third-party notice shipped in the binary, including SQLite3 Multiple Ciphers and SQLite, before any build is given to anyone;
  - each shipped platform's sqlite3mc binary is checked for `extensionfunctions.c` code.
- **AC2 Signed installers:** a notarised Mac build and a signed Windows installer that install and launch without OS security warnings.
- **AC3 Hardened Runtime** on the Mac build.
- **AC4 Mac key move:** the Mac history key moves from the login keychain to the data-protection keychain, with no user's history moved aside.
- **AC5 Release record:** release notes and a rollback plan; the PM approves the release.
- **AC6 DPIA:** a short DPIA in `docs/design/dpia.md`, signed off by the PM before the beta. It covers typed-shortcut keystroke watching.
- **AC7 SQLite3 Multiple Ciphers MIT notice** on the licence page (covered by AC1).
- **AC8 Release builds on macOS 27:** profile and release Mac builds succeed on the current macOS, and the built architectures are stated.
- **AC9 Minimum macOS:** 12.0 is stated in ADR 0003 or the README, and in the release notes.
- **AC10 Release-binary guard:**
  - the release pipeline fails if the shipped Mac binary contains `KusungaAcceptSyntheticKeys`;
  - a guard checks that `Local.xcconfig.example` sets no Swift compilation conditions.
- **Before start:** decide whether to build sqlite3mc from source (decision D2 below).

Added by the lead (needed to meet the GPL and to make AC2 real):
- **R1 Source offer (GPLv3 section 6):**
  - every binary we hand out is built from a tagged commit on the public repo;
  - the About screen and the release page link to that source.
- **R2 Version in the app:** the About screen shows the exact version and build, so a tester's report names the build.
- **R3 Release-build checks run on the exact files we ship:**
  - the extensionfunctions check, the strings guard and the signature checks;
  - a check fails the release; it is never skipped.

Non-goals:
- auto-update (testers download each new beta);
- Mac App Store;
- Linux;
- crash reports;
- a website;
- iOS and Android;
- paid sync.

## Top 3 qualities

| Quality | Target | How we check it |
|---|---|---|
| Users trust what they install | Mac: Gatekeeper accepts the download with no warning (`spctl -a -vv` says "Notarized Developer ID"); Windows: no SmartScreen or "unknown publisher" block on the chosen route | Release checklist runs `spctl`, `codesign --verify --strict`, `stapler validate`; Windows `Get-AuthenticodeSignature` = Valid; QA installs on a clean user account |
| No history lost in the key move | 0 history items lost or moved aside across the move; the move is safe to run again after a crash at any step | Unit tests for every step and every crash point; QA moves a qa-profile DB with 500 items and counts them before and after |
| Every shipped binary is accounted for | Each release maps to one git tag; licence notices match `docs/licences.md`; the test-only switch is absent | Release script refuses an untagged or dirty tree; guard tests; `strings` check is 0 |

## Estimate

Trivially small: a beta of 5–20 invited testers (D4), 2 platforms, about 5 MB to 40 MB per download, a handful of releases. No server, no data leaves the device.

## Data

- **No new data store.** One change only: where the Mac history key lives.
- **Mac key move (AC4), each launch, before the DB opens:**
  1. Read `history_db_key` from the data-protection keychain. If it is there, use it. Done.
  2. If not, read the same entry from the login keychain (the old place).
  3. If found there:
     - write it to the data-protection keychain;
     - read it back and compare byte for byte;
     - open the DB with it to prove it is the right key;
     - only then delete the old login-keychain item.
  4. If neither has it, this is a first run: make a new key straight in the data-protection keychain. The existing rule from ADR 0002 stays: if a DB exists and no key opens it, it is moved aside and the user is told.
- **Crash at any point:** the old item is deleted last, so the worst case is two copies of the same key. The next launch takes step 1 and deletes the leftover old item.
- **Not reversible:** going back to the login keychain is not offered, because the new place is stricter. A rollback build reads the data-protection keychain first (see Rollback).
- **Delete everything:** deletes the key from both places.
- **Entitlement:** the data-protection keychain needs a `keychain-access-groups` entitlement with the team prefix (`$(AppIdentifierPrefix)com.wnasoni.kusunga`). That needs the signed build, so it needs the Apple Developer account (D5 Mac). The team ID stays out of tracked files: it comes from `Local.xcconfig`, as today.
- **Windows:** no key change. Credential Manager stays.

## Options

Two choices are expensive to undo: how releases are signed and built (ADR 0006), and the Windows route (D1).

### A: Release script on the PM's Mac, signing keys stay on the PM's machines (recommended)
- **How it works:**
  - a `tool/release_mac.sh` script builds from a clean tagged commit;
  - signs with the Developer ID certificate in the PM's own keychain;
  - submits to Apple with `notarytool`, using a keychain profile the PM creates once;
  - staples the ticket, runs every release check (R3) and writes the DMG and its SHA-256;
  - Windows builds follow the same pattern on the route the PM picks in D1.
- **Benefits:** no signing secret ever goes to GitHub, which matters now the repo is public. Simple. Works today.
- **Costs and risks:**
  - only the PM can cut a release, and the PM types the commands;
  - releases depend on the PM's Mac being set up.
- **Effort:** small–medium.

### B: GitHub Actions release workflow with signing secrets
- **How it works:** a workflow on a tag imports the Developer ID certificate (`.p12`) and an App Store Connect API key from repository secrets, builds, signs, notarises and uploads.
- **Benefits:** repeatable, and no local set-up per release.
- **Costs and risks:**
  - signing keys live in GitHub;
  - a leaked secret lets anyone sign malware as the PM;
  - on a public repo every workflow change needs extra care: forks can't read secrets, but a merged workflow can;
  - more set-up.
- **Effort:** medium.

## Decision

- **PM decisions, 2026-11-19 (PM said: "approve decisions, am going to sleep you can continue"):** D1 A (Microsoft Store, SignPath as the fall-back), D2 A (pinned prebuilt), D3 A (Apple silicon only), D4 A (5–20 testers, GitHub Releases pre-release), D5 A (0.9.0), D6 A (release script on the PM's Mac), D7 A (email).
- **Still open (PM, before the beta, in M1.9f):** the lawful basis and the retention for tester contact details and feedback.
- **ADRs:** 0006 (release process) and 0007 (data-protection keychain move) are accepted.

## Work split (each part is its own branch and passes every gate)

| Part | What | Needs from PM first |
|---|---|---|
| M1.9a | About section in Settings, licence page with every notice (AC1, AC7, R1, R2), extensionfunctions check script for each platform's sqlite3mc binary | deck approval only |
| M1.9b | Mac release build: fix the macOS 27 `lipo` failure (AC8), Hardened Runtime (AC3), release-binary guard and `Local.xcconfig.example` guard (AC10), minimum macOS stated (AC9) | D3 (architectures) |
| M1.9c | Data-protection keychain and key move (AC4), code and tests | Apple Developer account active for the signed QA run |
| M1.9d | Windows packaging and signing on the chosen route (AC2 Windows) | D1 |
| M1.9e | Release script(s), release checklist, release notes, rollback plan (AC2 Mac, AC5, R3) | D6, Apple Developer account |
| M1.9f | DPIA (AC6) — the lead drafts, the PM signs | PM sign-off |
| Release | Tag, build, checks, PM approves, hand to testers | D4, D5, PM release approval |

M1.9a, M1.9b and M1.9f can start as soon as the deck is approved.

## Failure plan

- **Outbound calls:**
  - `notarytool submit --wait` with a 30-minute timeout. On a timeout, the script prints the submission id and stops.
  - Re-running the script checks the same submission with `notarytool info`; it never submits twice blindly.
  - The app itself makes no new outbound calls.
- **Key move failures:**
  - **Data-protection keychain unavailable** (for example, an ad-hoc dev build without the entitlement): keep using the login keychain, change nothing, log `keychainMoveSkipped`. Debug and profile builds take this path.
  - **Write or read-back fails:** keep the old item, open with the old key, and try again on the next launch.
  - **The old item exists but the DB will not open with it:** existing ADR 0002 behaviour (move aside, tell the user). The move does not run.
- **User sees:** nothing on success. If the move is skipped, still nothing; the log has the reason, with no key material.

## Observability

- Log events, with no key material and no personal data:
  - `keychainMoved`
  - `keychainMoveSkipped(reason)`
  - `keychainMoveRetry`
  - `keychainLeftoverDeleted`
- The release script prints a summary: version, tag, commit, SHA-256 of each file, and each check's pass/fail.
- Two numbers to watch in the beta: tester reports of a missing history after updating (target 0), and install-warning reports (target 0).

## Trust boundaries and abuse cases

- **Boundaries:**
  - the release build machine and its signing keys;
  - the download channel (D4) between us and testers;
  - the prebuilt sqlite3mc binary (pinned by SHA-256 in the `sqlite3` package hook);
  - the keychain move (reads an item another build may have written).
- **Abuse cases:**
  - **As an attacker I swap the download for a trojaned build so that testers run my code.**
    - Mitigation: Developer ID signing and notarisation on Mac; Authenticode or Store signing on Windows.
    - The release page lists the SHA-256 of each file.
    - QA installs from the published download, not from the build folder.
  - **As an attacker I steal the signing key so that I can sign malware as Kusunga.**
    - Mitigation: option A keeps keys only in the PM's keychain (the Developer ID private key is never exported). No secrets in the repo; the existing secret scan in review covers it.
  - **As an attacker who controls the test-only switch path, I enable synthetic keys in a shipped build so that I can fire typed shortcuts from injected events.**
    - Mitigation: the switch is compiled out of release; the strings guard (AC10) fails the release if it is present.
  - **As an attacker I plant a login-keychain item named `history_db_key` so that Kusunga adopts my key.**
    - Mitigation: the move only adopts the old item if it opens the existing DB. With no DB, a planted key would only encrypt new history with a key the attacker knows.
    - That needs code running as the user, which already beats any local protection.
    - Recorded as an accepted limit of the threat model (same as ADR 0002), not a new risk.
  - **As a supply-chain attacker I change the sqlite3mc prebuilt binary so that the cipher is weakened.** Mitigation: SHA-256 pin in the package hook; the extensionfunctions check (AC1) also reads each shipped binary; D2 covers building from source.
  - **As a tester I post a bug report with clipboard content in it so that personal data ends up public.** Mitigation: the beta guide tells testers never to paste history content in a report. The feedback channel is D7.

## Privacy

Not legal advice. Items marked "PM decides" need the PM's decision before the developer starts.

| Field | Purpose | Lawful basis (PM decides) | Retention | Shared with | Notes |
|---|---|---|---|---|---|
| History DB key (Mac) | Encrypts history on the device | n/a — stays on the user's device; Kusunga's maker receives nothing | Until Delete everything | none | Moves to the stricter data-protection keychain |
| Tester feedback (whatever testers send) | Fix bugs in the beta | PM decides — likely legitimate interests or consent | PM decides (suggest: delete 90 days after M1 ships) | Depends on D7 (GitHub issues are public; email is private) | Testers are told never to include clipboard content |
| Tester contact details (name, email) for the invite | Send the beta and updates | PM decides — likely consent | PM decides (suggest: until the beta ends, then delete) | none | Collected by the PM, outside the app |

- Fields removed: none. The app adds no fields.
- **DPIA screening:**
  - Triggers: "new technology" and "invisible processing" (keystroke watching for typed shortcuts, M1.5); the keystrokes never leave the device.
  - The PM already decided a DPIA is written before the beta (2026-11-08). The lead drafts it in M1.9f; the PM signs it.
- Children likely: no. It is an invited adult beta.
- Automated decisions or profiling: none.
- Special category data: possible in history content (users copy anything), but it never leaves the device. Covered in the DPIA.
- **New vendors / SDKs / transfers:**
  - None in the app.
  - Distribution: Apple notarisation receives the app binary only, no user data. The Windows route (D1) may add Microsoft Partner Center (binary only).
  - The download host (D4) receives testers' IP addresses when they download; with GitHub Releases, that is GitHub's own processing.
- Private defaults: unchanged. Nothing new is on by default.
- Export, delete, rectify: unchanged; Delete everything also removes the key from the new keychain place.
- Marketing consent: n/a. Beta invites are one-to-one messages from the PM, not marketing. A newsletter would need consent.
- Record of processing and privacy notice: the beta guide includes a short privacy note (everything stays on your device; what we receive is only what you send us). The PM approves it with the release (AC5).
- **Escalated to PM:**
  - D7 feedback channel;
  - the lawful basis and retention for tester contact details and feedback;
  - DPIA sign-off (AC6).

## Rollout and rollback

- **Order:** M1.9a, M1.9b and M1.9f first; then M1.9c, M1.9d and M1.9e when the PM's accounts are ready; then the release.
- **First the PM:** the PM installs the beta build on their own Mac over the existing dev install first. This tests the key move on real data; the M1.9c QA run uses the qa profile, never the PM's real DB.
- **Small batches:** 2–3 testers first, the rest after 3 days with no blocker.
- **Rollback:**
  - Testers go back to the previous beta's download (kept on the release page) or uninstall.
  - Rule for every later build: it reads the data-protection keychain first, so going back to a build that has the move keeps working.
  - A build from before the move (any dev build before M1.9c) would not find the key and would move history aside. So we never hand a pre-move build to anyone, and the release page keeps only post-move builds.
  - Confirm the rollback worked by opening Kusunga: history is present, and the log shows no `keyMissing` / move-aside event.

## Later lines

- Release workflow in GitHub Actions with signing secrets (option B) — option A is enough for a small beta — trigger: > 2 releases a month for 2 months, or a second person needs to cut releases — noted 2026-11-19 by lead
- Auto-update (Sparkle on Mac, the Store or an updater on Windows) — testers can download by hand — trigger: > 50 beta users, or ≥ 5 reports of testers on an old build — noted 2026-11-19 by lead
- Intel Mac build, if D3 chooses Apple silicon only — trigger: ≥ 5 beta requests from Intel Mac users — noted 2026-11-19 by lead
- Build sqlite3mc from source, if D2 keeps the pinned prebuilt — trigger: the sqlite3 package changes its prebuilt source or hash scheme, a cipher-related CVE in a pinned build, or we need a compile option the prebuilt lacks — noted 2026-11-19 by lead

## Decisions needed (PM)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Windows signing route (closes plan D5 for Windows) | A: Microsoft Store, MSIX, Microsoft signs for free; beta via a hidden Store listing · B: SignPath Foundation (free for open-source projects; OV-level; SmartScreen warnings at first, eligibility to be confirmed) · C: buy an OV certificate (about $150–300/year, hardware token) · D: unsigned Windows beta (testers see "Windows protected your PC"; needs your risk acceptance, AC2 not met) | A, with B as the fall-back if Store review rejects the keyboard hook or takes too long. The Store route changes how launch at login and the data folder work on Windows (MSIX), which M1.9d must re-test. Hidden-listing details are not yet confirmed. |
| D2 | sqlite3mc: pinned prebuilt or build from source | A: keep the SHA-256-pinned prebuilt from the sqlite3 package · B: build from source in our build | A for the beta: it is hash-pinned, and the extensionfunctions check reads the shipped binary. B is a Later line with a trigger. |
| D3 | Mac architectures for the beta | A: Apple silicon only (`ARCHS = arm64`, works around the `lipo` failure now) · B: Universal (Apple silicon + Intel); needs a Flutter update that fixes `lipo` on macOS 27, which changes the pinned Flutter (ADR 0001) | A. macOS 27 runs only on Apple silicon; Intel users are on macOS 26 or older. Intel becomes a Later line. |
| D4 | Beta size and download place | A: 5–20 invited testers, files on GitHub Releases on the public repo (marked pre-release) · B: same testers, files shared privately (link from you) | A: it matches the GPL source offer (same place as the source) and gives a public SHA-256 list. |
| D5 | Version number | A: 0.9.0 (beta) · B: 1.0.0-beta.1 | A: 1.0.0 is for the first public release. |
| D6 | Release process | A: release script on your Mac, keys stay with you · B: GitHub Actions with signing secrets | A |
| D7 | Feedback channel and tester data | A: email to an address you choose (private) · B: GitHub issues (public) · C: both, with a "never paste clipboard content" rule | A for the beta, because reports may contain personal data. Also needed: the lawful basis and retention for tester contact details and feedback. |
