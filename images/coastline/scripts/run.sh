#!/usr/bin/env bash
# CronJob entry point: build and publish the zip, then load it into the tiler DB
# when LOAD_TILER_DB=true.
set -euo pipefail
source "$(dirname "$0")/common.sh"

"$APP_DIR/scripts/build.sh"

if [ "${LOAD_TILER_DB:-false}" = "true" ]; then
  "$APP_DIR/scripts/load.sh" "$OUT_DIR/$ZIP_NAME"
fi
