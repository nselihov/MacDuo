#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
PROBE_APP="$PROJECT_DIR/.build/MacDuoLockScreenProbe.app"
MODE="${1:---arm}"
case "$MODE" in
    --build|--check|--preview|--arm) ;;
    *) echo "Usage: $0 [--build|--check|--preview|--arm]" >&2; exit 2 ;;
esac
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
mkdir -p "$PROJECT_DIR/.cache/clang" "$PROJECT_DIR/.cache/swiftpm"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.cache/swiftpm"
cd "$PROJECT_DIR"
swift build --product MacDuoLockScreenProbe
PROBE_BIN_DIR="$(swift build --show-bin-path)"
if [[ "$MODE" == "--check" ]]; then
    exec "$PROBE_BIN_DIR/MacDuoLockScreenProbe" --check --log "$PROJECT_DIR/.build/lock-screen-probe.log"
fi
mkdir -p "$PROBE_APP/Contents/MacOS" "$PROBE_APP/Contents/Resources"
cp "$PROBE_BIN_DIR/MacDuoLockScreenProbe" "$PROBE_APP/Contents/MacOS/MacDuoLockScreenProbe"
cp "$PROJECT_DIR/Resources/LockScreenProbe-Info.plist" "$PROBE_APP/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/Licenses/SkyLightWindow.txt" "$PROBE_APP/Contents/Resources/"
codesign --force --sign - --timestamp=none "$PROBE_APP"
if [[ "$MODE" == "--build" ]]; then
    echo "$PROBE_APP"
else
    open -g "$PROBE_APP" --args "$MODE" --log "$PROJECT_DIR/.build/lock-screen-probe.log"
    echo "Probe log: $PROJECT_DIR/.build/lock-screen-probe.log"
fi
