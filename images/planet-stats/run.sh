#!/usr/bin/env bash
# Pull prior state -> run pipeline -> publish output. State round-trips via S3
# because collate_stats.py globs all prior daily/ dirs.
set -o errexit
set -o pipefail
set -x

DATE="${RUN_DATE:-$(date +%Y-%m-%d)}"
DASHDIR="${DASHBOARD_DIR:-/mnt/planet-stats}"
STATE_S3="${PLANET_STATS_STATE_S3_URI:?set PLANET_STATS_STATE_S3_URI, e.g. s3://ohm-planet-stats}"

# Always nest under a fixed subfolder so nothing lands at the bucket root,
# even if the URI is just a bucket. Override the folder with PLANET_STATS_S3_PREFIX.
DEST="${STATE_S3%/}/${PLANET_STATS_S3_PREFIX:-planet-stats}"

# s3cmd reads AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY from env.
# Set AWS_S3_ENDPOINT for Cloudflare R2.
S3_ARGS=()
if [ -n "${AWS_S3_ENDPOINT:-}" ]; then
  S3_ARGS+=(--host="${AWS_S3_ENDPOINT}" --host-bucket="%(bucket)s.${AWS_S3_ENDPOINT}")
fi

mkdir -p "$DASHDIR"
s3cmd "${S3_ARGS[@]}" sync "${DEST}/" "$DASHDIR/" || echo "no prior state (first run)"
./stats-pipeline.sh "$DATE" "$DASHDIR"
s3cmd "${S3_ARGS[@]}" sync "$DASHDIR/" "${DEST}/"
