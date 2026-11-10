#!/usr/bin/env bash
# Builds and runs the pure C++ policy tests (clipboard, own changes, capture
# skips, picker, typed shortcuts and the shared app id rule). No Windows needed.
# If the Mac's Command Line Tools SDK does not match, use Xcode's compiler:
#   X=/Applications/Xcode.app/Contents/Developer
#   CXX="$X/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++ -isysroot $X/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" ./tool/test_windows_policy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
for name in clipboard_policy_test clipboard_own_change_edge_test capture_gate_test capture_gate_edge_test picker_policy_test picker_policy_edge_test typed_shortcut_policy_test app_id_test; do
  # shellcheck disable=SC2086
  ${CXX:-clang++} -std=c++17 -Wall -Wextra -Werror "windows/runner/$name.cpp" -o "$dir/$name"
  "$dir/$name"
done
