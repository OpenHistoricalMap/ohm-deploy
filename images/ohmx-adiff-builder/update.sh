#!/bin/bash
set -euo pipefail

# This script is base  on https://github.com/OSMCha/osmx-adiff-builder/blob/main/update.sh

export PATH="$PATH:$PWD"

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <osmx_db_path> <replication_adiffs_dir> <bad_changesets_dir> [initial_seqnum]"
    exit 1
fi

OSMX_DB_PATH=$1
REPLICATION_ADIFFS_DIR=$2
BAD_CHANGESETS_DIR=$3
INITIAL_SEQNUM=${4:-}

eval "$(mise activate bash --shims)"

if [ -n "${INITIAL_SEQNUM:-}" ]; then
  seqno_start="$INITIAL_SEQNUM"
else
  seqno_start="$(osmx query "$OSMX_DB_PATH" seqnum)"
fi

echo ">>> Starting from seqno=$seqno_start"

osm replication minute --seqno "$seqno_start" \
| while read -r seqno timestamp url; do
    # Exit if seqno is empty
    if [ -z "${seqno:-}" ]; then
      echo ">>> seqno is empty, end of stream"; break
    fi

    echo ">>> [$seqno] fetching $url"
    # Robust curl with retries and timeout
    if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 120 "$url" | gzip -d > "${seqno}.osc"; then
      echo "!!! [$seqno] failed to download or decompress. skipping..."
      continue
    fi

    echo ">>> [$seqno] building adiff"
    tmpfile="$(mktemp)"
    if augmented_diff.py "$OSMX_DB_PATH" "${seqno}.osc" \
       | xmlstarlet format > "$tmpfile"; then
        mv "$tmpfile" "$REPLICATION_ADIFFS_DIR/${seqno}.adiff"
        echo ">>> [$seqno] adiff OK -> ${REPLICATION_ADIFFS_DIR}/${seqno}.adiff"
    else
        rm -f "$tmpfile"
        mv "${seqno}.osc" "$BAD_CHANGESETS_DIR/${seqno}.osc"
        echo "!!! [$seqno] error generating adiff (possible invalid XML). OSC moved to $BAD_CHANGESETS_DIR. Continuing..."
        continue
    fi

    echo ">>> [$seqno] osmx update"
    osmx update "$OSMX_DB_PATH" "${seqno}.osc" "$seqno" "$timestamp" --commit || {
      echo "!!! [$seqno] osmx update failed"; exit 1;
    }
    rm -f "${seqno}.osc"
    echo ">>> [$seqno] done"
done
