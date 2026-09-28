#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/.build/MacDuo.app"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

mkdir -p "$PROJECT_DIR/.cache/clang" "$PROJECT_DIR/.cache/swiftpm"

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.cache/swiftpm"

cd "$PROJECT_DIR"
swift build --product MacDuo
BINARY_DIR="$(swift build --show-bin-path)"
BINARY_PATH="$BINARY_DIR/MacDuo"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_PATH" "$APP_PATH/Contents/MacOS/MacDuo"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
mkdir -p "$APP_PATH/Contents/Resources/Licenses"
cp "$PROJECT_DIR/Resources/Licenses/SkyLightWindow.txt" "$APP_PATH/Contents/Resources/Licenses/"
cp "$PROJECT_DIR/Resources/DuoFold.metal" "$APP_PATH/Contents/Resources/"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/"
cp "$PROJECT_DIR/Resources/Licenses/iPhoneDuoAnimation.txt" "$APP_PATH/Contents/Resources/Licenses/"

# Remove the obsolete shader bundle from older local builds.
rm -rf "$APP_PATH/Contents/Resources/MacDuo_MacDuo.bundle"

# A stable designated requirement lets macOS recognize rebuilt local versions
# as the same app for Screen Recording permission during development.
codesign \
    --force \
    --sign - \
    --timestamp=none \
    --requirements '=designated => identifier "com.nikolay.macduo"' \
    "$APP_PATH"

echo "$APP_PATH"
