#!/usr/bin/env bash
# Runs the typed-shortcut XCTests as the SHIPPING (Release) build compiles
# them: without -D DEBUG, so QA's debug-only synthetic-keys switch does not
# exist and software-sent keys are always skipped (PM decision 2026-11-09).
# tool/test_mac_shortcuts.sh compiles with -D DEBUG and covers the switch;
# this one proves the shipping behaviour. Nothing launches the app.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
bundle="$dir/TypedShortcutTestsRelease.xctest"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TypedShortcutTestsRelease</string>
<key>CFBundleIdentifier</key><string>com.wnasoni.kusunga.typedshortcuttestsrelease</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
platform="$(xcrun --show-sdk-platform-path)"
# No -D DEBUG here, on purpose.
xcrun swiftc -module-name Kusunga -enable-testing -parse-as-library \
  -suppress-warnings \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" -L "$platform/Developer/usr/lib" \
  -Xlinker -bundle -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  -framework XCTest \
  macos/Runner/TypedShortcutCore.swift macos/RunnerTests/TypedShortcutCoreTests.swift \
  -o "$bundle/Contents/MacOS/TypedShortcutTestsRelease"
xcrun xctest "$bundle"
