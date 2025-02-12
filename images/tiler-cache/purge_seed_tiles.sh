set -x

# Default zoom levels
PURGE_MIN_ZOOM=${PURGE_MIN_ZOOM:-8}
PURGE_MAX_ZOOM=${PURGE_MAX_ZOOM:-20}
PURGE_CONCURRENCY=${PURGE_CONCURRENCY:-16}

SEED_MIN_ZOOM=${SEED_MIN_ZOOM:-8}
SEED_MAX_ZOOM=${SEED_MAX_ZOOM:-14}
SEED_CONCURRENCY=${SEED_CONCURRENCY:-16}

EXECUTE_PURGE=${EXECUTE_PURGE:-true}
EXECUTE_SEED=${EXECUTE_SEED:-true}

# Download file from S3
file_name=$(basename "$IMPOSM_EXPIRED_FILE")
aws s3 cp "$IMPOSM_EXPIRED_FILE" "$file_name"
if [ $? -ne 0 ]; then
    echo "Error: Failed to download the file from S3."
    exit 1
fi

# Run Tegola cache purge if enabled
if [ "$EXECUTE_PURGE" = "true" ]; then
    echo "Starting Tegola cache purge..."
    set -x
    tegola cache purge tile-list "$file_name" \
        --config=/opt/tegola_config/config.toml \
        --format="/zxy" \
        --min-zoom=$PURGE_MIN_ZOOM \
        --max-zoom=$PURGE_MAX_ZOOM \
        --map=osm \
        --overwrite=false \
        --concurrency=$PURGE_CONCURRENCY
    set +x
else
    echo "Skipping Tegola cache purge (EXECUTE_PURGE=false)."
fi

# Run Tegola cache seed if enabled
if [ "$EXECUTE_SEED" = "true" ]; then
    echo "Starting Tegola cache seed..."
    set -x
    tegola cache seed tile-list "$file_name" \
        --config=/opt/tegola_config/config.toml \
        --map=osm \
        --min-zoom=$SEED_MIN_ZOOM \
        --max-zoom=$SEED_MAX_ZOOM \
        --overwrite=true \
        --concurrency=$SEED_CONCURRENCY
    set +x
else
    echo "Skipping Tegola cache seed (EXECUTE_SEED=false)."
fi

echo "Script completed successfully."
