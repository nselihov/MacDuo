#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/.build/MacDuo.app"
DIST_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DIST_DIR/MacDuo-preview.dmg"
STAGING_DIR="$(mktemp -d /private/tmp/macduo-package.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT

"$PROJECT_DIR/scripts/make-app-icon.sh"
"$PROJECT_DIR/scripts/build-app.sh"

codesign --verify --strict "$APP_PATH"

mkdir -p "$DIST_DIR"
ditto "$APP_PATH" "$STAGING_DIR/MacDuo.app"
ln -s /Applications "$STAGING_DIR/Программы"

hdiutil create \
    -volname "MacDuo" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"
echo "$DMG_PATH"
