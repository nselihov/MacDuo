#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Resources/duo-source.png"
ICONSET="$PROJECT_DIR/Resources/AppIcon.iconset"
ROUNDED_SOURCE="$PROJECT_DIR/.build/AppIcon-rounded-1024.png"

mkdir -p "$ICONSET" "$PROJECT_DIR/.build"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
swift "$PROJECT_DIR/scripts/round-app-icon.swift" "$SOURCE" "$ROUNDED_SOURCE"

render_icon() {
    local size="$1"
    local name="$2"
    sips -s format png -z "$size" "$size" "$ROUNDED_SOURCE" --out "$ICONSET/$name" >/dev/null
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

cp "$ROUNDED_SOURCE" "$PROJECT_DIR/Resources/AppIcon-1024.png"
iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/Resources/AppIcon.icns"
