#!/bin/bash
set -e

MIN_ZOOM=${MIN_ZOOM:-9}
MAX_ZOOM=${MAX_ZOOM:-16}

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
    --min-zoom=$MIN_ZOOM \
    --max-zoom=$MAX_ZOOM \
    --map=osm \
    --overwrite=false \
    --concurrency=16

# Run Tegola cache seed
tegola cache seed tile-list "$file_name" \
    --config=/opt/tegola_config/config.toml \
    --map=osm \
    --min-zoom=$MIN_ZOOM \
    --max-zoom=$MAX_ZOOM \
    --overwrite=false \
    --concurrency=16
set +x

echo "Script completed successfully."