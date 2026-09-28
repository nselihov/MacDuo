#!/bin/zsh
set -euo pipefail

EXPERIMENT_DIR="${0:A:h}"
PROJECT_DIR="${EXPERIMENT_DIR:h:h}"
OUTPUT_DIR="$PROJECT_DIR/.build/reference-port/metal-prototype"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
mkdir -p "$OUTPUT_DIR"
swiftc "$EXPERIMENT_DIR/main.swift" -o "$OUTPUT_DIR/duo-fold-prototype" \
  -framework AppKit -framework Metal
"$OUTPUT_DIR/duo-fold-prototype" "$EXPERIMENT_DIR/DuoFold.metal" "$OUTPUT_DIR"
