#!/bin/bash
# Builds a Release .app and packages it into a drag-to-Applications .dmg.
# Ad-hoc signed (no paid Apple Developer account) — first launch requires
# right-click -> Open to get past Gatekeeper. See README.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Clip"
CONFIG="Release"
BUILD_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"

xcodegen generate
rm -rf "$BUILD_DIR"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration "$CONFIG" \
  -derivedDataPath "$BUILD_DIR" -destination "generic/platform=macOS" \
  build CODE_SIGNING_ALLOWED=NO

APP_PATH="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/stage"
cp -R "$APP_PATH" "$DIST_DIR/stage/"
ln -s /Applications "$DIST_DIR/stage/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR/stage" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg"

echo "Built $DIST_DIR/$APP_NAME.dmg"
