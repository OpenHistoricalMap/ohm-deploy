#!/usr/bin/env bash
# Shared settings and helpers for start.sh and update.sh
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

DATA_DIR=${DATA_DIR:-/data}
PLANET_FILE=${PLANET_FILE:-$DATA_DIR/planet.osm.pbf}
GRAPHS_DIR=${GRAPHS_DIR:-$DATA_DIR/graphs}
CURRENT_LINK=$GRAPHS_DIR/current
LOCK_FILE=$DATA_DIR/.update.lock
PLANET_BUCKET_URL=${PLANET_BUCKET_URL:-https://s3.amazonaws.com/planet.openhistoricalmap.org}
PLANET_DOWNLOAD_URL=${PLANET_DOWNLOAD_URL:-https://planet.openhistoricalmap.org}
REPLICATION_URL=${REPLICATION_URL:-https://planet.openhistoricalmap.org/replication/minute}
# Download a fresh planet after this many days, instead of only applying diffs
FULL_REFRESH_DAYS=${FULL_REFRESH_DAYS:-7}
KEEP_GRAPHS=${KEEP_GRAPHS:-2}
USER_AGENT=${USER_AGENT:-ohm-routing}
APP_DIR=${APP_DIR:-/app}
GH_JAR=$APP_DIR/graphhopper.jar
GH_CONFIG=$APP_DIR/config/config.yml
# Hash of config/ and src/, written at build time. A graph is only valid for the
# same profiles and encoded values, so each graph dir starts with this version.
GRAPH_VERSION=$(cat "$APP_DIR/graph-version")

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$(basename "$0")] $*"; }

# Name of the graph dir that "current" points to, or empty
current_graph() { [ -L "$CURRENT_LINK" ] && readlink "$CURRENT_LINK" || true; }

current_is_valid() {
  local cur
  cur=$(current_graph)
  [[ -n "$cur" && "$cur" == "$GRAPH_VERSION"-* && -d "$GRAPHS_DIR/$cur" ]]
}

# Replication sequence number stored in the PBF header
planet_sequence() {
  python3 -I -c "import osmium,sys; h=osmium.io.Reader(sys.argv[1], osmium.osm.osm_entity_bits.NOTHING).header(); print(h.get('osmosis_replication_sequence_number', ''))" "$PLANET_FILE"
}

# There is no planet-latest file, so list this month and last month in the bucket
latest_planet_key() {
  local prefix
  for prefix in "planet/planet-$(date -u +%y%m)" "planet/planet-$(date -u -d 'last month' +%y%m)"; do
    curl -fsS "$PLANET_BUCKET_URL?prefix=$prefix" \
      | grep -o '<Key>[^<]*\.osm\.pbf</Key>' | sed 's/<[^>]*>//g' | sort | tail -1
  done | sort | tail -1
}

download_planet() {
  local key
  key=$(latest_planet_key)
  [ -n "$key" ] || { log "no planet file found in $PLANET_BUCKET_URL"; return 1; }
  log "downloading $key"
  curl -fsSL -A "$USER_AGENT" -o "$PLANET_FILE.tmp" "$PLANET_DOWNLOAD_URL/$key"
  mv "$PLANET_FILE.tmp" "$PLANET_FILE"
  date -u +%s > "$PLANET_FILE.downloaded"
}

planet_is_old() {
  [ -f "$PLANET_FILE.downloaded" ] || return 0
  [ $(( $(date -u +%s) - $(cat "$PLANET_FILE.downloaded") )) -gt $(( FULL_REFRESH_DAYS * 86400 )) ]
}

# Apply replication diffs until the PBF is up to date. rc 1 means more data is waiting.
update_planet() {
  local rc
  for _ in $(seq 1 50); do
    rc=0
    pyosmium-up-to-date --server "$REPLICATION_URL" -s 1000 "$PLANET_FILE" || rc=$?
    [ "$rc" -eq 1 ] || break
  done
  [ "$rc" -eq 0 ] || { log "pyosmium-up-to-date failed with rc=$rc"; return 1; }
}

# Build a new graph and point "current" to it. Nothing changes if the import fails.
build_graph() {
  local name tmp start
  name="$GRAPH_VERSION-$(date -u +%Y%m%d%H%M%S)"
  tmp="$GRAPHS_DIR/.$name.tmp"
  mkdir -p "$GRAPHS_DIR"
  # leftovers from an import that was killed; safe because callers hold the lock
  find "$GRAPHS_DIR" -mindepth 1 -maxdepth 1 -name '.*.tmp' -type d -exec rm -rf {} +
  start=$(date +%s)
  log "importing $PLANET_FILE into $name"
  # shellcheck disable=SC2086
  java $JAVA_OPTS \
    -Ddw.graphhopper.datareader.file="$PLANET_FILE" \
    -Ddw.graphhopper.graph.location="$tmp" \
    -jar "$GH_JAR" import "$GH_CONFIG" || { rm -rf "$tmp"; log "import failed"; return 1; }
  mv "$tmp" "$GRAPHS_DIR/$name"
  ln -sfn "$name" "$GRAPHS_DIR/.current.tmp"
  mv -Tf "$GRAPHS_DIR/.current.tmp" "$CURRENT_LINK"
  log "graph $name ready in $(( $(date +%s) - start ))s"
  prune_graphs
}

# Keep the newest KEEP_GRAPHS graph dirs
prune_graphs() {
  local cur dir
  cur=$(current_graph)
  find "$GRAPHS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort -t- -k2 -r \
    | tail -n +"$(( KEEP_GRAPHS + 1 ))" | while read -r dir; do
      [ "$dir" = "$cur" ] && continue
      log "removing old graph $dir"
      rm -rf "${GRAPHS_DIR:?}/$dir"
    done
}
