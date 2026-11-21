#!/usr/bin/env bash
# Fails if a sqlite3mc (SQLite3 Multiple Ciphers) binary contains
# extensionfunctions.c code. That file has no licence upstream, so it must not
# ship (docs/licences.md, flag 1; M1.9 AC1). Run it on every binary that is
# handed to anyone.
#
#   tool/check_sqlite3mc.sh [binary ...]
#
# With no argument it checks every sqlite3mc binary this machine has built:
# the downloaded libraries under .dart_tool/hooks_runner/shared/sqlite3/build/
# (libsqlite3mc.dylib, libsqlite3mc.so, or sqlite3mc.dll on Windows),
# and the ones copied into build/ (the Mac sqlite3mc.framework, the Windows
# sqlite3mc.dll). It fails if it finds none, so "nothing to check" never passes.
#
# macOS (works now; the arm64 binary had no extensionfunctions code on
# 2026-11-19):
#   tool/check_sqlite3mc.sh build/macos/Build/Products/Release/Kusunga.app/Contents/Frameworks/sqlite3mc.framework/sqlite3mc
#
# Windows: run it in Git Bash (it only needs bash, tr and grep, which Git for
# Windows ships; no `strings`, no network) on the built DLL:
#   bash tool/check_sqlite3mc.sh build/windows/x64/runner/Release/sqlite3mc.dll
# For a release, give it the DLL inside the installer's input folder, the exact
# file that is signed and shipped.
#
# How it works: it splits the binary at NUL bytes (C string tables) and looks
# for names that extensionfunctions.c registers and SQLite3 Multiple Ciphers
# does not: padl, padr, padc, strfilter, charindex, leftstr, rightstr, stdev,
# variance, replicate, atn2, cot, coth, proper, lower_quartile, upper_quartile and its
# RegisterExtensionFunctions entry point. Short names must be a whole string
# (so "padlock" is fine); the long, distinctive ones may sit inside a string. It
# also fails on a file that is empty or is not a SQLite library, so a wrong
# path can't pass. It is a check for those function names, not proof; the
# build flag SQLITE_ENABLE_EXTFUNC must stay off as well.
set -uo pipefail
root="${KUSUNGA_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# Whole-string matches (short names) and in-string matches (distinctive names).
exact=(padl padr padc stdev variance replicate atn2 cot coth proper)
inside=(strfilter charindex leftstr rightstr lower_quartile upper_quartile RegisterExtensionFunctions)

# LC_ALL=C: bytes, not characters. In a UTF-8 locale tr stops at the first
# byte that is not valid UTF-8, which every real binary has.
strings_of() { LC_ALL=C tr '\0' '\n' <"$1"; }

failed=0
check() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "FAIL $file: no such file" >&2
    return 1
  fi
  if [ ! -s "$file" ]; then
    echo "FAIL $file: the file is empty" >&2
    return 1
  fi
  if ! strings_of "$file" | LC_ALL=C grep -a -c -F 'sqlite_master' | grep -qv '^0$'; then
    echo "FAIL $file: not a SQLite library (no SQLite string found)" >&2
    return 1
  fi
  local hits="" args=() n
  for n in "${exact[@]}"; do args+=(-e "$n"); done
  hits+="$(strings_of "$file" | LC_ALL=C grep -a -x -F "${args[@]}" || true)"$'\n'
  args=()
  for n in "${inside[@]}"; do args+=(-e "$n"); done
  hits+="$(strings_of "$file" | LC_ALL=C grep -a -o -F "${args[@]}" || true)"
  hits="$(printf '%s\n' "$hits" | LC_ALL=C sed '/^$/d' | LC_ALL=C sort -u)"
  if [ -n "$hits" ]; then
    echo "FAIL $file: contains extensionfunctions.c code (no licence): $(echo "$hits" | tr '\n' ' ')" >&2
    return 1
  fi
  echo "ok   $file: no extensionfunctions.c code"
}

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(
    {
      [ -d "$root/.dart_tool/hooks_runner/shared/sqlite3/build" ] &&
        find "$root/.dart_tool/hooks_runner/shared/sqlite3/build" -type f \( -name 'libsqlite3mc.*' -o -name sqlite3mc.dll \)
      [ -d "$root/build" ] &&
        find "$root/build" -type f \( -name sqlite3mc.dll -o -path '*sqlite3mc.framework/*sqlite3mc' \)
    } 2>/dev/null | LC_ALL=C sort -u
  )
  if [ "${#files[@]}" -eq 0 ]; then
    echo "FAIL: no sqlite3mc binary found under $root (build the app first, or pass the file)" >&2
    exit 2
  fi
fi

for f in "${files[@]}"; do
  check "$f" || failed=1
done
exit "$failed"
