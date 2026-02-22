#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/apps/mac-client"
DIST_DIR="$NATIVE_DIR/dist"
APP_NAME="VerbatimFlow"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
VOL_NAME="VerbatimFlow Installer"

OUTPUT_DMG="${1:-$DIST_DIR/VerbatimFlow-installer.dmg}"
# Stage in /tmp to avoid iCloud FileProvider injecting virtual extended
# attributes (FinderInfo invisible flag) into the DMG contents.
STAGE_DIR="/tmp/verbatimflow-dmg-stage"

"$ROOT_DIR/scripts/build-native-app.sh"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "[error] app bundle not found: $APP_BUNDLE" >&2
  exit 1
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Use ditto instead of cp -R to avoid copying virtual FileProvider/iCloud
# extended attributes (e.g. FinderInfo with invisible flag) into the DMG.
ditto "$APP_BUNDLE" "$STAGE_DIR/${APP_NAME}.app"
xattr -cr "$STAGE_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGE_DIR/Applications"

cat > "$STAGE_DIR/Install VerbatimFlow.txt" <<'TXT'
Install steps:
1. Drag VerbatimFlow.app to Applications.
2. Launch from Applications.
3. On first run, grant Microphone, Accessibility, and Input Monitoring when prompted.
TXT

rm -f "$OUTPUT_DMG"
mkdir -p "$(dirname "$OUTPUT_DMG")"

hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

rm -rf "$STAGE_DIR"

echo "[ok] installer dmg: $OUTPUT_DMG"
echo "[hint] open '$OUTPUT_DMG'"
