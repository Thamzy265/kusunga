#!/usr/bin/env bash
# Guards the Mac release script (M1.9e) calls before it hands a build out.
# Nothing here builds, signs or launches anything.
#
#   tool/mac_release_guards.sh binary <Kusunga.app | file>
#       Fails (exit 1) if any file in the bundle contains the QA-only switch
#       KusungaAcceptSyntheticKeys (it is compiled out of release builds).
#   tool/mac_release_guards.sh xcconfig <file>
#       Fails (exit 1) if the file sets Swift compilation conditions
#       (SWIFT_ACTIVE_COMPILATION_CONDITIONS, or -D in OTHER_SWIFT_FLAGS):
#       a signing example file must never switch DEBUG code on.
#
# Exit 2 means the guard could not run (missing path, nothing to scan), which
# is also a failure: a typo must never pass.
set -euo pipefail

needle="KusungaAcceptSyntheticKeys"

usage() {
  echo "usage: $0 binary <app-or-file> | xcconfig <file>" >&2
  exit 2
}

guard_binary() {
  local target="$1" files file hits rc total=0
  [ -e "$target" ] || { echo "guard: $target does not exist" >&2; exit 2; }
  files="$(find "$target" -type f -print)"
  [ -n "$files" ] || { echo "guard: no files under $target" >&2; exit 2; }
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
  local file="$1"
  [ -f "$file" ] || { echo "guard: $file does not exist" >&2; exit 2; }
  # Drop comment lines, then look for the two ways to set a condition.
  if grep -v '^[[:space:]]*//' "$file" |
    grep -Eq '^[[:space:]]*(SWIFT_ACTIVE_COMPILATION_CONDITIONS|OTHER_SWIFT_FLAGS[^=]*=.*(^|[[:space:]])-D)'; then
    echo "guard FAILED: $file sets Swift compilation conditions" >&2
    exit 1
  fi
  echo "ok: $file sets no Swift compilation conditions"
}

[ "$#" -eq 2 ] || usage
case "$1" in
  binary) guard_binary "$2" ;;
  xcconfig) guard_xcconfig "$2" ;;
  *) usage ;;
esac
