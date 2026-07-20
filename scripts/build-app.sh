#!/usr/bin/env bash
#
# Builds Flare Scan, assembles a proper macOS .app bundle, and signs it with the
# App Sandbox entitlements. Output: dist/Flare Scan.app
#
set -euo pipefail

APP_NAME="Flare Scan"
EXECUTABLE_NAME="FlareScan"
BUNDLE_ID="com.umudhasanli.flarescan"
VERSION="1.1.0"
BUILD="2"
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
cp "$ROOT/assets/flare-scan.svg" "$APP/Contents/Resources/FlareScan.svg"

# Turn the supplied SVG logo into a native macOS application icon.
ICONSET="$DIST/FlareScan.iconset"
mkdir -p "$ICONSET"
for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" \
            "32:icon_32x32.png" "64:icon_32x32@2x.png" \
            "128:icon_128x128.png" "256:icon_128x128@2x.png" \
            "256:icon_256x256.png" "512:icon_256x256@2x.png" \
            "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
  size="${spec%%:*}"
  file="${spec#*:}"
  sips -s format png -z "$size" "$size" "$ROOT/assets/flare-scan.svg" \
    --out "$ICONSET/$file" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/FlareScan.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key><string>FlareScan</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>${MIN_MACOS}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableDescription</key><string>Private visual disk space analyzer with Sunburst, Treemap, and confirmed cleanup.</string>
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
codesign --display --entitlements - "$APP" 2>/dev/null | grep -q "user-selected.read-write" \
  && echo "  ✓ user-selected read/write entitlement present"

echo "✔ Built: $APP"
echo "  Run it with:  open \"$APP\""
