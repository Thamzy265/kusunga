# 0006. Sign and notarise releases on the PM's machine, not in CI

Date: 2026-11-19

## Status

Accepted (PM decision D6 A, 2026-11-19)

## Context

From M1.9, Kusunga ships signed builds to testers:
- **Mac:** Developer ID signing and notarisation by Apple (ADR 0003).
- **Windows:** the signing route chosen in decision D1.

The repo has been public since 2026-11-19. Signing keys are the most valuable secret the project has: anyone holding them can sign malware that Macs and Windows trust as Kusunga.

Options considered:
- **A: A release script on the PM's Mac.**
  - It builds from a clean tagged commit and signs with the Developer ID identity in the PM's keychain. The private key is never exported.
  - It notarises with a `notarytool` keychain profile and runs every release check.
- **B: A GitHub Actions release workflow,** with the certificate (`.p12`) and an App Store Connect API key in repository secrets.

## Decision

We will use option A for the beta.

`tool/release_mac.sh`, and its Windows counterpart for the D1 route, refuses to run if:
- the tree is dirty;
- HEAD is not an annotated tag `v<version>`;
- the tag's version does not match `pubspec.yaml`.

It fails the release on any failed check:
- `codesign --verify --strict`;
- `spctl -a -vv`;
- `stapler validate`;
- the `KusungaAcceptSyntheticKeys` strings check;
- the sqlite3mc `extensionfunctions.c` check.

No signing secret is stored in the repo or in GitHub.

## Consequences

- **Easier:** no secret on a public repo's CI. A leak needs the PM's machine.
- **Harder:**
  - only the PM can cut a release;
  - releases depend on the PM's Mac set-up;
  - the steps must stay documented (`docs/release.md`).
- **Revisit:** move to option B (Later line), with short-lived credentials and a protected environment that needs approval, if releases become frequent or a second person releases.
