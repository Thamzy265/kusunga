#!/usr/bin/env bash
# The one check command: format, analyze, test. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
