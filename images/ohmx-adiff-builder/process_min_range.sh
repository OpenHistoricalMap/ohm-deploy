#!/bin/bash
# Backfill an explicit replication seqno range, then merge the results.
# Usage: ./process_min_range.sh SEQNO_START SEQNO_END
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh
command -v mise >/dev/null 2>&1 && eval "$(mise activate bash --shims)"

mkdir -p "$SPLIT_ADIFFS_DIR" "$BAD_CHANGESETS_DIR" "$CHANGESET_DIR" "$BUCKET_DIR"

for seqno in $(seq "$1" "$2"); do
  echo ">>> seqno $seqno"
  p=$(printf "%09d" "$seqno")
  url="$REPLICATION_URL/${p:0:3}/${p:3:3}/${p:6:3}.osc.gz"
  curl -fsSL --max-time 120 "$url" | gzip -d > "$seqno.osc" || { echo "skip (download)"; continue; }

  tmpdir=$(mktemp -d)
  if ! "$OSMX_RS_BIN" augmented-diff --split "$OSMX_DB_PATH" "$seqno.osc" "$tmpdir"; then
    rm -rf "$tmpdir"; mv "$seqno.osc" "$BAD_CHANGESETS_DIR/"; continue
  fi
  for f in "$tmpdir"/*.adiff; do
    [ -e "$f" ] || continue
    cs=$(basename -s .adiff "$f")
    mkdir -p "$SPLIT_ADIFFS_DIR/$cs"
    mv "$f" "$SPLIT_ADIFFS_DIR/$cs/$seqno.adiff"
  done
  rm -rf "$tmpdir"

  "$OSMX_BIN" update "$OSMX_DB_PATH" "$seqno.osc" "$seqno" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --commit \
    || echo "warn: osmx update failed for $seqno"
  rm -f "$seqno.osc"
done

# Merge whatever fragments now exist (merge.mk skips unchanged changesets).
make -f merge.mk SPLIT_ADIFFS_DIR="$SPLIT_ADIFFS_DIR" CHANGESET_DIR="$CHANGESET_DIR" \
                 BUCKET_DIR="$BUCKET_DIR" API_URL="$API_URL"
