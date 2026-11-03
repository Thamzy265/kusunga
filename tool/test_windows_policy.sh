#!/usr/bin/env bash
# Builds and runs the pure C++ clipboard policy test. No Windows needed.
# If the Mac's Command Line Tools SDK does not match, use Xcode's compiler:
#   X=/Applications/Xcode.app/Contents/Developer
#   CXX="$X/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -isysroot $X/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" ./tool/test_windows_policy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/clipboard_policy_test"
# shellcheck disable=SC2086
${CXX:-clang++} -std=c++17 -Wall -Wextra -Werror windows/runner/clipboard_policy_test.cpp -o "$out"
"$out"
