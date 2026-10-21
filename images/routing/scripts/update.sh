#!/usr/bin/env bash
# Bring the planet up to date and build a new graph if anything changed.
# Run it from a CronJob. When a new graph is ready and RESTART_DEPLOYMENT is set,
# it does a rolling restart of that Deployment so the servers load the new graph.
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$GRAPHS_DIR"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another update is running, skipping"
  exit 0
fi

if [ ! -f "$PLANET_FILE" ] || planet_is_old; then
  download_planet
fi

before=$(planet_sequence)
update_planet
after=$(planet_sequence)
log "planet sequence $before -> $after"

if [ "$before" = "$after" ] && current_is_valid; then
  log "no new data, keeping $(current_graph)"
  exit 0
fi

build_graph
exec 9>&-

if [ -n "${RESTART_DEPLOYMENT:-}" ]; then
  "$(dirname "$0")/restart-server.sh" "$RESTART_DEPLOYMENT"
fi
