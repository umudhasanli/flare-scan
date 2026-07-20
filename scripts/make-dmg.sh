#!/usr/bin/env bash
#
# Packages dist/Flare Scan.app into a distributable dist/Flare Scan.dmg with a
# drag-to-Applications layout. Run scripts/build-app.sh first.
#
set -euo pipefail

APP_NAME="Flare Scan"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

if [[ ! -d "$APP" ]]; then
  echo "✖ $APP not found. Build it first:  scripts/build-app.sh"
  exit 1
fi

STAGING="$DIST/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="$DIST/$APP_NAME.dmg"
rm -f "$DMG"

echo "▶ Creating DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGING"
echo "✔ DMG ready: $DMG"
echo "  Size: $(du -h "$DMG" | cut -f1)"
