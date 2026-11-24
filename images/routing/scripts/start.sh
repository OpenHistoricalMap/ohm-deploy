#!/usr/bin/env bash
# Start the GraphHopper server from the current graph. If there is no graph for
# this image version yet (first deploy, or config changed), build one first.
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Local copy of the graph, so update.sh can replace or prune graphs on the
# shared volume while this server is running
LOCAL_GRAPH=${LOCAL_GRAPH:-/tmp/graph}

if ! current_is_valid; then
  log "no graph for version $GRAPH_VERSION, building one"
  mkdir -p "$GRAPHS_DIR"
  exec 9>"$LOCK_FILE"
  flock 9
  # another pod or the CronJob may have built it while we waited for the lock
  if ! current_is_valid; then
    [ -f "$PLANET_FILE" ] || download_planet
    update_planet || log "could not apply diffs, building from the planet as it is"
    build_graph
  fi
  exec 9>&-
fi

graph=$(current_graph)
log "loading graph $graph"
mkdir -p "$LOCAL_GRAPH"
find "$LOCAL_GRAPH" -mindepth 1 -delete
cp -r "$GRAPHS_DIR/$graph/." "$LOCAL_GRAPH/"

# shellcheck disable=SC2086
exec java $JAVA_OPTS \
  -Ddw.graphhopper.datareader.file="$PLANET_FILE" \
  -Ddw.graphhopper.graph.location="$LOCAL_GRAPH" \
  -jar "$GH_JAR" server "$GH_CONFIG"
