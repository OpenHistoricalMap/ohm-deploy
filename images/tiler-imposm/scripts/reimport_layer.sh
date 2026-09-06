#!/bin/bash
set -e
source ./scripts/utils.sh

# ------------------------------------------------------------------------------
# Script: reimport_layer.sh
# Description:
#   Imports only the given layers (layers/<name>/mapping.json) from the PBF in
#   /mnt/data and deploys their tables to production. Tables of other layers are
#   not touched. Run ./scripts/create_mviews.sh <layer> afterwards to rebuild
#   the views of those layers.
#
# Usage:
#   ./scripts/reimport_layer.sh <layer> [layer ...]
# Example:
#   ./scripts/reimport_layer.sh others routes
# ------------------------------------------------------------------------------

WORKDIR=/mnt/data
PBFFILE="${WORKDIR}/osm.pbf"
TMP_MAPPING="./config/imposm3_reimport.json"
TMP_CONFIG="./config/config_reimport.json"
TMP_CACHE="./cachedir_reimport"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <layer> [layer ...]"
    echo "Available layers:"
    ls layers | sed 's/^/  - /'
    exit 1
fi

# Mapping with only the requested layers (fails on unknown layer names)
python3 scripts/layers.py imposm --layers "$(IFS=,; echo "$*")" -o "$TMP_MAPPING"

cat <<EOF >"$TMP_CONFIG"
{
    "cachedir": "$TMP_CACHE",
    "diffdir": "$WORKDIR/diff",
    "connection": "postgis://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB",
    "mapping": "/osm/$TMP_MAPPING",
    "replication_url": "$REPLICATION_URL"
}
EOF

mkdir -p "$TMP_CACHE"

log_message "Reimporting layers: $*"
imposm import -config "$TMP_CONFIG" -read "$PBFFILE" -write -cachedir "$TMP_CACHE" -overwritecache -optimize
imposm import -config "$TMP_CONFIG" -deployproduction

rm -f "$TMP_MAPPING" "$TMP_CONFIG"
rm -rf "$TMP_CACHE"

log_message "Done: $*"
