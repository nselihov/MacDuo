#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

mkdir -p "$PROJECT_DIR/.cache/clang" "$PROJECT_DIR/.cache/swiftpm"

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.cache/swiftpm"

cd "$PROJECT_DIR"
swift run MacDuoDisplayCheck
