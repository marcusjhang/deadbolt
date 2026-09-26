#!/usr/bin/env bash
# Assemble a runnable Deadbolt.app from the SwiftPM Deadbolt executable.
# Re-runnable: it rebuilds the binary and recreates build/Deadbolt.app from
# scratch. Fails non-zero with a clear message when the build or assembly fails.
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
APP_DIR="$ROOT/build/Deadbolt.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
INFO_PLIST="$CONTENTS/Info.plist"

VERSION="0.1.0"
BUILD="1"

on_error() {
    echo "error: Deadbolt.app assembly failed" >&2
}
trap on_error ERR

echo "== building Deadbolt executable (release) =="
swift build --product Deadbolt -c release

BIN_DIR="$(swift build --show-bin-path -c release)"
BINARY="$BIN_DIR/Deadbolt"

if [[ ! -f "$BINARY" ]]; then
    echo "error: built binary not found at $BINARY" >&2
    exit 1
fi

echo "== assembling $APP_DIR =="
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/Deadbolt"
chmod +x "$MACOS_DIR/Deadbolt"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.deadbolt.app</string>
    <key>CFBundleName</key>
    <string>Deadbolt</string>
    <key>CFBundleExecutable</key>
    <string>Deadbolt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST"

echo "== ad-hoc codesign =="
codesign --force --sign - "$APP_DIR"

echo "built $APP_DIR"
