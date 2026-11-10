#!/usr/bin/env bash
# Runs the capture-skip XCTests (M1.6: secret markers, then the pause, then
# the source app against the ignore list, all before any text is read) as a
# standalone bundle with `xcrun xctest`. The watcher and the Foundation-only
# gate are compiled with their tests as a module named Kusunga, so nothing
# launches the app (the RunnerTests host is Kusunga.app, which would open the
# real data and the keychain). CI also runs the same tests inside RunnerTests.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
bundle="$dir/CaptureGateTests.xctest"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CaptureGateTests</string>
<key>CFBundleIdentifier</key><string>com.wnasoni.kusunga.capturegatetests</string>
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
  macos/Runner/CaptureSkipCore.swift macos/Runner/ClipboardWatcher.swift \
  macos/RunnerTests/CaptureGateTests.swift \
  -o "$bundle/Contents/MacOS/CaptureGateTests"
xcrun xctest "$bundle"
