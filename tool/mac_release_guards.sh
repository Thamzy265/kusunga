#!/usr/bin/env bash
# Guards the Mac release script (M1.9e) calls before it hands a build out.
# Nothing here builds, signs or launches anything.
#
#   tool/mac_release_guards.sh binary <Kusunga.app | file>
#       Fails (exit 1) if any file in the bundle contains the QA-only switch
#       KusungaAcceptSyntheticKeys (it is compiled out of release builds).
#   tool/mac_release_guards.sh xcconfig <file>
#       For the signing example file. Fails (exit 1) if, outside whole-line //
#       comments, the file has a -D token anywhere, or sets any key other than
#       DEVELOPMENT_TEAM, CODE_SIGN_STYLE, CODE_SIGN_IDENTITY or
#       PROVISIONING_PROFILE_SPECIFIER (with or without [sdk=..]/[config=..]).
#       So it can never switch DEBUG code on. CR, LF and CRLF all end a line.
#   tool/mac_release_guards.sh frameworks <Kusunga.app>
#       For the signed release build (M1.10c, ADR 0009). Fails (exit 1) unless
#       the app and everything nested in it pass
#       `codesign --verify --deep --strict` (so a loose .dylib that is not
#       signed fails too), the native-asset frameworks sqlite3mc.framework and
#       cnativeapi.framework are in Contents/Frameworks, and every framework
#       there passes `codesign --verify --strict` and is signed by the same
#       team as the app (an ad-hoc or unsigned app or framework fails). The
#       Team ID is never printed, so the output can go into QA evidence.
#
# Exit 2 means the guard could not run (missing path, nothing to scan), which
# is also a failure: a typo must never pass.
set -euo pipefail
# Globbing on, whatever the caller exported: with SHELLOPTS=noglob in the
# environment bash starts with it off, and the framework loop would check
# nothing and still print ok (reviewer F4).
set +f
# Tracing off, whatever the caller exported (SHELLOPTS=xtrace, or bash -x): a
# trace would print the Team ID that codesign reports and that the signing
# example sets. Before anything below reads either.
set +x
# Byte-wise text tools whatever the caller's locale: under UTF-8, grep skips
# lines with invalid UTF-8, so a marker next to a stray byte would be missed.
export LC_ALL=C

needle="KusungaAcceptSyntheticKeys"
# The only keys the signing example may set (Local.xcconfig.example sets the
# first three; the profile specifier is for manual signing).
allowed_xcconfig_line='^[[:space:]]*(DEVELOPMENT_TEAM|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER)(\[[^]]*\])*[[:space:]]*='

# Native assets that must ship, each signed like the app (M1.10c).
required_frameworks="sqlite3mc cnativeapi"

usage() {
  echo "usage: $0 binary <app-or-file> | xcconfig <file> | frameworks <app>" >&2
  exit 2
}

guard_binary() {
  local target="$1" files file hits rc total=0
  # A path starting with "-" would be read as an option by find and grep:
  # refuse it (exit 2) and ask for ./-name instead.
  case "$target" in
    -*) echo "guard: $target starts with a dash, write it as ./$target" >&2; exit 2 ;;
  esac
  [ -e "$target" ] || { echo "guard: $target does not exist" >&2; exit 2; }
  # Empty files cannot hold the marker; a bundle with only empty files (or
  # none) scanned nothing, which must not pass. Any find error is exit 2.
  rc=0
  files="$(find "$target" -type f -size +0c -print)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "guard: could not list $target" >&2
    exit 2
  fi
  [ -n "$files" ] || { echo "guard: nothing to scan under $target" >&2; exit 2; }
  while IFS= read -r file; do
    # Raw bytes, not `strings`: strings parses Mach-O files and errors out on
    # a malformed one, which must not read as "clean". grep -a is a superset
    # of strings (it also matches text split across a section boundary).
    # grep exits 1 for "no match" (count 0) and 2 for an error, which fails.
    rc=0
    hits="$(grep -a -c -F -- "$needle" "$file")" || rc=$?
    if [ "$rc" -gt 1 ]; then
      echo "guard: could not read $file" >&2
      exit 2
    fi
    if [ "$hits" -ne 0 ]; then
      echo "guard: $file contains $needle ($hits strings)" >&2
      total=$((total + hits))
    fi
  done <<< "$files"
  if [ "$total" -ne 0 ]; then
    echo "guard FAILED: the shipped binary contains $needle" >&2
    exit 1
  fi
  echo "ok: no $needle in $target"
}

guard_xcconfig() {
  local file="$1" text live lines bad rc
  [ -f "$file" ] || { echo "guard: $file does not exist" >&2; exit 2; }
  # Read the file first, so an unreadable file is an error (exit 2) and not a
  # pass. Xcode ends a line at CR as well as LF, so turn CR into LF; a NUL
  # also starts a new line (conservative). No pipes below: under pipefail a
  # grep that stops early (SIGPIPE) on a large file would hide a match.
  rc=0
  text="$(tr '\r\000' '\n\n' < "$file")" || rc=$?
  [ "$rc" -eq 0 ] || { echo "guard: could not read $file" >&2; exit 2; }
  # Drop whole-line // comments. grep -v exits 1 when nothing is left: fine.
  rc=0
  live="$(grep -v '^[[:space:]]*//' <<< "$text")" || rc=$?
  [ "$rc" -le 1 ] || { echo "guard: could not scan $file" >&2; exit 2; }
  # 1. A -D token anywhere (any quoting, any key, glued to $(inherited)).
  #    "-D" must not follow a letter, digit or underscore, so a value such as
  #    My-Dev is not a flag.
  rc=0
  grep -Eq '(^|[^[:alnum:]_])-D' <<< "$live" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "guard FAILED: $file has a -D token" >&2
    exit 1
  fi
  [ "$rc" -eq 1 ] || { echo "guard: could not scan $file" >&2; exit 2; }
  # 2. Only the signing keys, each optionally with [sdk=..]/[config=..]
  #    conditions, may be set. Anything else (another key, #include, a stray
  #    continuation line) fails: Xcode honours spellings a deny-list misses.
  rc=0
  lines="$(grep -Ev '^[[:space:]]*$' <<< "$live")" || rc=$?
  [ "$rc" -le 1 ] || { echo "guard: could not scan $file" >&2; exit 2; }
  rc=1
  # (A here-string of nothing is one empty line, so skip the match then.)
  if [ -n "$lines" ]; then
    rc=0
    bad="$(grep -Ev "$allowed_xcconfig_line" <<< "$lines")" || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    echo "guard FAILED: $file sets something other than the signing keys:" >&2
    echo "$bad" >&2
    exit 1
  fi
  [ "$rc" -eq 1 ] || { echo "guard: could not scan $file" >&2; exit 2; }
  echo "ok: $file sets only signing keys and no -D flags"
}

# The Team ID of the signed code at $1 on stdout ("" when codesign cannot read
# a signature, "not set" for ad-hoc). codesign prints the details on stderr.
team_of() {
  local out rc=0
  out="$(codesign -dv --verbose=2 "$1" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] || return 0
  sed -n 's/^TeamIdentifier=//p' <<< "$out"
}

# Returns 1, saying why on stderr, unless the framework at $1 passes
# `codesign --verify --strict` and is signed by the app's team ($2).
check_framework() {
  local fw="$1" app_team="$2" team
  if ! codesign --verify --strict "$fw" 2>/dev/null; then
    echo "guard: $(basename "$fw") does not pass codesign --verify --strict" >&2
    return 1
  fi
  team="$(team_of "$fw")"
  if [ "$team" != "$app_team" ]; then
    echo "guard: $(basename "$fw") is not signed by the app's team" >&2
    return 1
  fi
}

# True when the folder name $1 (such as cnativeapi.framework) is a required
# framework.
is_required() {
  local name
  for name in $required_frameworks; do
    [ "$1" = "$name.framework" ] && return 0
  done
  return 1
}

guard_frameworks() {
  local app="$1" dir app_team fw name failed=0 checked=0
  case "$app" in
    -*) echo "guard: $app starts with a dash, write it as ./$app" >&2; exit 2 ;;
  esac
  [ -d "$app" ] || { echo "guard: $app does not exist" >&2; exit 2; }
  dir="$app/Contents/Frameworks"
  [ -d "$dir" ] || { echo "guard: $app has no Contents/Frameworks" >&2; exit 2; }
  app_team="$(team_of "$app")"
  if [ -z "$app_team" ] || [ "$app_team" = "not set" ]; then
    echo "guard FAILED: $app is not signed with a team (ad-hoc or unsigned)" >&2
    exit 1
  fi
  # The app's own signature and everything nested in it, including a loose
  # .dylib in Contents/Frameworks, which the framework checks below miss.
  if ! codesign --verify --deep --strict "$app" 2>/dev/null; then
    echo "guard: $app does not pass codesign --verify --deep --strict" >&2
    failed=1
  fi
  # The required frameworks by their own path, not through the listing
  # below, and both of them: should that ever stop being true, the guard
  # fails rather than passing on fewer.
  for name in $required_frameworks; do
    fw="$dir/$name.framework"
    if [ ! -d "$fw" ]; then
      echo "guard: $name.framework is missing from $dir" >&2
      failed=1
      continue
    fi
    checked=$((checked + 1))
    check_framework "$fw" "$app_team" || failed=1
  done
  if [ "$checked" -lt 2 ]; then
    echo "guard: only $checked of the 2 required frameworks could be checked" >&2
    failed=1
  fi
  # Every other framework there.
  for fw in "$dir"/*.framework; do
    [ -d "$fw" ] || continue
    is_required "$(basename "$fw")" && continue
    check_framework "$fw" "$app_team" || failed=1
  done
  if [ "$failed" -ne 0 ]; then
    echo "guard FAILED: $app does not verify, or a framework in it is missing or not signed like the app" >&2
    exit 1
  fi
  echo "ok: $app verifies, and $required_frameworks and every framework in it are signed by the app's team"
}

[ "$#" -eq 2 ] || usage
case "$1" in
  binary) guard_binary "$2" ;;
  xcconfig) guard_xcconfig "$2" ;;
  frameworks) guard_frameworks "$2" ;;
  *) usage ;;
esac
