#!/usr/bin/env bash
# Runs the launch-at-login XCTests (M1.7: the controller behind the
# loginItemStatus and setLoginItem calls, against a fake SMAppService, and the
# login-launch check) as a standalone bundle with `xcrun xctest`. The
# Foundation-only core is compiled with its tests as a module named Kusunga,
# so nothing launches the app and no real login item is ever registered. CI
# also runs the same tests inside RunnerTests.
set -euo pipefail
cd "$(dirname "$0")/.."
dir="$(mktemp -d)"
bundle="$dir/LoginItemTests.xctest"
mkdir -p "$bundle/Contents/MacOS"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LoginItemTests</string>
<key>CFBundleIdentifier</key><string>com.wnasoni.kusunga.loginitemtests</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
# Type-check guard: the Xcode 16.4 compiler on the macos-15 CI runner gave up
# on a closure-in-ternary here ("unable to type-check this expression in
# reasonable time") that newer local compilers still accept. Local Swift
# takes about 1 ms for every other expression in this file and took about
# 930 ms for that one, so any expression over 100 ms fails this script
# before CI does.
slow="$(xcrun swiftc -typecheck \
  -Xfrontend -warn-long-expression-type-checking=100 \
  macos/Runner/LoginItemCore.swift 2>&1 | grep 'type-check' || true)"
if [ -n "$slow" ]; then
  echo "$slow"
  echo "FAIL: an expression in LoginItemCore.swift is slow to type-check; split it up" >&2
  exit 1
fi
platform="$(xcrun --show-sdk-platform-path)"
xcrun swiftc -module-name Kusunga -enable-testing -parse-as-library \
  -suppress-warnings \
  -F "$platform/Developer/Library/Frameworks" \
  -I "$platform/Developer/usr/lib" -L "$platform/Developer/usr/lib" \
  -Xlinker -bundle -Xlinker -rpath -Xlinker "$platform/Developer/Library/Frameworks" \
  -Xlinker -rpath -Xlinker "$platform/Developer/usr/lib" \
  -framework XCTest \
  macos/Runner/LoginItemCore.swift macos/RunnerTests/LoginItemCoreTests.swift \
  -o "$bundle/Contents/MacOS/LoginItemTests"
xcrun xctest "$bundle"
