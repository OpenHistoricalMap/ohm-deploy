#!/bin/bash
set -e
source ./scripts/utils.sh

# Usage: ./scripts/reimport_layer.sh <layer1> [layer2] ...
# Example: ./scripts/reimport_layer.sh communication_lines communication_multilines

WORKDIR=/mnt/data
PBFFILE="${WORKDIR}/osm.pbf"
LAYERS_DIR="./config/layers"
TMP_MAPPING="./config/imposm3_reimport.json"
TMP_CONFIG="./config/config_reimport.json"
TMP_CACHE="./cachedir_reimport"

# Validate arguments
if [ $# -eq 0 ]; then
    echo "Usage: $0 <layer1> [layer2] ..."
    echo "Available layers:"
    ls "$LAYERS_DIR"/*.json | xargs -I{} basename {} .json | sort | sed 's/^/  - /'
    exit 1
fi

# Validate layers exist
for layer in "$@"; do
    [ -f "$LAYERS_DIR/${layer}.json" ] || { echo "Layer not found: $layer"; exit 1; }
done

# Build mapping config with only the specified layers
python3 -c "
import json, os
t = json.load(open('./config/imposm3.template.json'))
for l in '$*'.split():
    c = json.load(open(f'$LAYERS_DIR/{l}.json'))
    t.get('generalized_tables',{}).update(c.get('generalized_tables',{}))
    t.get('tables',{}).update(c.get('tables',{}))
json.dump(t, open('$TMP_MAPPING','w'), indent=2)
print('Tables:', list(t['tables'].keys()))
"

# Create imposm config
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

# Import and deploy
log_message "Reimporting layers: $*"
imposm import -config "$TMP_CONFIG" -read "$PBFFILE" -write -cachedir "$TMP_CACHE" -overwritecache -optimize
imposm import -config "$TMP_CONFIG" -deployproduction

# Cleanup
rm -f "$TMP_MAPPING" "$TMP_CONFIG"
rm -rf "$TMP_CACHE"

log_message "$Done: $*"
