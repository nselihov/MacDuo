#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="$PROJECT_DIR/Resources/duo-source.png"
ICONSET="$PROJECT_DIR/Resources/AppIcon.iconset"

mkdir -p "$ICONSET"

render_icon() {
    local size="$1"
    local name="$2"
    sips -s format png -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
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

sips -s format png -z 1024 1024 "$SOURCE" \
    --out "$PROJECT_DIR/Resources/AppIcon-1024.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/Resources/AppIcon.icns"
