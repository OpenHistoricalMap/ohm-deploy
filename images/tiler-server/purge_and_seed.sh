#!/bin/bash
set -e

PURGE_MIN_ZOOM=${PURGE_MIN_ZOOM:-8}
PURGE_MAX_ZOOM=${PURGE_MAX_ZOOM:-20}
SEED_MIN_ZOOM=${SEED_MIN_ZOOM:-8}
SEED_MAX_ZOOM=${SEED_MAX_ZOOM:-14}

file_name=$(basename "$IMPOSM_EXPIRED_FILE")
aws s3 cp "$IMPOSM_EXPIRED_FILE" "$file_name"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download the file from S3."
    exit 1
fi

set -x
# Run Tegola cache purge
tegola cache purge tile-list "$file_name" \
    --config=/opt/tegola_config/config.toml \
    --format="/zxy" \
    --min-zoom=$PURGE_MIN_ZOOM \
    --max-zoom=$PURGE_MAX_ZOOM \
    --map=osm \
    --overwrite=false \
    --concurrency=16

# Run Tegola cache seed
tegola cache seed tile-list "$file_name" \
    --config=/opt/tegola_config/config.toml \
    --map=osm \
    --min-zoom=$SEED_MIN_ZOOM \
    --max-zoom=$SEED_MAX_ZOOM \
    --overwrite=true \
    --concurrency=16
set +x

echo "Script completed successfully."
