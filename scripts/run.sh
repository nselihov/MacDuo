#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/.build/MacDuo.app"

"$PROJECT_DIR/scripts/build-app.sh"
open "$APP_PATH"
