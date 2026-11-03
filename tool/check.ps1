# The one check command for Windows: format, analyze, test.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

dart format --output=none --set-exit-if-changed .
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
