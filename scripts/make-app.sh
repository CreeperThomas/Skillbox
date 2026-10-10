#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Skillbox.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/Skillbox" "$APP/Contents/MacOS/Skillbox"
for bundle in "$ROOT"/.build/release/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
/usr/libexec/PlistBuddy -c 'Clear dict' "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Skillbox' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.thomas.skillbox' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string Skillbox' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0.0' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 26.0' "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"
printf 'Built %s\n' "$APP"
