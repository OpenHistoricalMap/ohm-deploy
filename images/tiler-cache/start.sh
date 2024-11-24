#!/bin/bash
set -x

# Default command if none provided
COMMAND=${1:-"tiler-purge"}

echo "Starting Tiler Cache Service with command: $COMMAND"

case "$COMMAND" in
  tiler-purge)
    echo "Executing tiler-purge..."
    python /app/tiler-purge/main.py
    ;;
  tiler-seed)
    echo "Executing tiler-seed..."
    cd /app/tiler-seed
    python main.py --geojson-url "$GEOJSON_URL" \
                                   --feature-type "$FEATURE_TYPE" \
                                   --zoom-levels "$ZOOM_LEVELS" \
                                   --concurrency "$CONCURRENCY" \
                                   --s3-bucket "$S3_BUCKET" \
                                   --log-file "$OUTPUT_FILE"
    ;;
  *)
    echo "Invalid command: $COMMAND"
    exit 1
    ;;
esac