#!/usr/bin/env bash
#
# Builds Flare Scan, assembles a proper macOS .app bundle, and signs it with the
# App Sandbox entitlements. Output: dist/Flare Scan.app
#
set -euo pipefail

APP_NAME="Flare Scan"
EXECUTABLE_NAME="FlareScan"
BUNDLE_ID="com.umudhasanli.flarescan"
VERSION="1.0.0"
BUILD="1"
MIN_MACOS="14.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "▶ Building release binary…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"
EXECUTABLE="$BIN_PATH/$EXECUTABLE_NAME"
if [[ ! -f "$EXECUTABLE" ]]; then
  echo "✖ Executable not found at: $EXECUTABLE"
  exit 1
fi

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Umud Hasanli. MIT License.</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▶ Signing (ad-hoc) with sandbox entitlements…"
codesign --force \
  --entitlements "$ROOT/packaging/DiskLens.entitlements" \
  --sign - "$APP"

echo "▶ Verifying signature & entitlements…"
codesign --verify --verbose=2 "$APP"
codesign --display --entitlements - "$APP" 2>/dev/null | grep -q "app-sandbox" \
  && echo "  ✓ sandbox entitlement present"

echo "✔ Built: $APP"
echo "  Run it with:  open \"$APP\""
