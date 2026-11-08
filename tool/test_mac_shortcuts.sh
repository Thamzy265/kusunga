#!/usr/bin/env bash
# Runs the typed-shortcut XCTests (buffer, matcher, skip rules, key classes)
# as a standalone bundle with `xcrun xctest`. The Foundation-only Swift core is
# compiled with its tests as a module named Kusunga, so nothing launches the
# app (the RunnerTests host is Kusunga.app, which would open the real data and
# the keychain). CI also runs the same tests inside RunnerTests.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
bundle="$dir/TypedShortcutTests.xctest"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TypedShortcutTests</string>
<key>CFBundleIdentifier</key><string>com.wnasoni.kusunga.typedshortcuttests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
platform="$(xcrun --show-sdk-platform-path)"
xcrun swiftc -module-name Kusunga -enable-testing -parse-as-library \
  -suppress-warnings \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" -L "$platform/Developer/usr/lib" \
  -Xlinker -bundle -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  -framework XCTest \
  macos/Runner/TypedShortcutCore.swift macos/RunnerTests/TypedShortcutCoreTests.swift \
  -o "$bundle/Contents/MacOS/TypedShortcutTests"
xcrun xctest "$bundle"
