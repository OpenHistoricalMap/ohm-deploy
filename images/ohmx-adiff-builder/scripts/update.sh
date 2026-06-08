#!/bin/bash
# For each new replication file: build per-changeset adiffs with osmx-rs --split,
# then apply the change to the osmx db. Runs once and exits; start.sh loops it.
#
# Usage: update.sh <osmx_db> <split_adiffs_dir> <bad_changesets_dir> [start_seqno]
set -euo pipefail
cd "$(dirname "$0")"
source ./config.sh
export PATH="$PATH:$PWD"

# Args are optional overrides; defaults come from config.sh (the /data layout).
OSMX_DB_PATH=${1:-$OSMX_DB_PATH}
SPLIT_ADIFFS_DIR=${2:-$SPLIT_ADIFFS_DIR}
BAD_CHANGESETS_DIR=${3:-$BAD_CHANGESETS_DIR}

command -v mise >/dev/null 2>&1 && eval "$(mise activate bash --shims)"

# Preflight: a missing tool is a setup error, not a bad changeset. Fail fast and
# loud instead of silently dumping every .osc into bad_changesets.
for bin in "$OSMX_BIN" "$OSMX_RS_BIN" osm; do
  command -v "$bin" >/dev/null 2>&1 || { echo "FATAL: required binary '$bin' not found in PATH" >&2; exit 127; }
done

mkdir -p "$SPLIT_ADIFFS_DIR" "$BAD_CHANGESETS_DIR"
# The db is the single source of truth for position: create_database seeds the
# seqnum from the planet header, every osmx update --commit advances it.
seqno_start=$("$OSMX_BIN" query "$OSMX_DB_PATH" seqnum)
echo ">>> starting from seqno=$seqno_start"

osm replication minute --seqno "$seqno_start" | while read -r seqno timestamp url; do
  [ -z "${seqno:-}" ] && { echo ">>> end of stream"; break; }

  echo ">>> [$seqno] fetching $url"
  if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 120 "$url" | gzip -d > "$seqno.osc"; then
    echo "!!! [$seqno] download failed, skipping"; rm -f "$seqno.osc"; continue
  fi

  # Generate one adiff per changeset into a tmp dir, then file each fragment under
  # split-adiffs/<changeset>/<seqno>.adiff so they accumulate across replication files.
  tmpdir=$(mktemp -d)
  if ! "$OSMX_RS_BIN" augmented-diff --split "$OSMX_DB_PATH" "$seqno.osc" "$tmpdir"; then
    rm -rf "$tmpdir"; mv "$seqno.osc" "$BAD_CHANGESETS_DIR/"
    echo "!!! [$seqno] osmx-rs failed, osc moved to $BAD_CHANGESETS_DIR"; continue
  fi
  for f in "$tmpdir"/*.adiff; do
    [ -e "$f" ] || continue
    cs=$(basename -s .adiff "$f")
    mkdir -p "$SPLIT_ADIFFS_DIR/$cs"
    mv "$f" "$SPLIT_ADIFFS_DIR/$cs/$seqno.adiff"
  done
  rm -rf "$tmpdir"

  echo ">>> [$seqno] osmx update"
  "$OSMX_BIN" update "$OSMX_DB_PATH" "$seqno.osc" "$seqno" "$timestamp" --commit
  rm -f "$seqno.osc"
done
