#!/usr/bin/env bash
# Build land-polygons-split-3857.zip from the OHM coastlines and publish it.
# Same format as https://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip,
# so the tiler loads it the same way. Also publishes the osmcoastline errors as GeoJSON.
#
# Steps: planet -> natural=coastline ways -> ways on COASTLINE_DATE -> osmcoastline
#        -> checks -> zip -> S3
set -euo pipefail
source "$(dirname "$0")/common.sh"

mkdir -p "$DATA_DIR" "$OUT_DIR"
work=$DATA_DIR/work
rm -rf "$work" && mkdir -p "$work"

if [ -n "${PLANET_URL:-}" ]; then
  log "downloading $PLANET_URL"
  curl -fsSL -A "$USER_AGENT" -o "$PLANET_FILE" "$PLANET_URL"
  PLANET_KEY=$PLANET_URL
elif [ "${SKIP_PLANET_DOWNLOAD:-false}" != "true" ] || [ ! -f "$PLANET_FILE" ]; then
  download_planet
fi

log "filtering natural=coastline"
osmium tags-filter "$PLANET_FILE" w/natural=coastline -o "$work/coastline-all.osm.pbf" --overwrite

log "keeping coastlines that exist on $COASTLINE_DATE"
python3 -I "$APP_DIR/scripts/filter_by_date.py" "$work/coastline-all.osm.pbf" "$work/coastline.osm.pbf" "$COASTLINE_DATE"

# Exit codes: 0 ok, 1 warnings, 2 errors (output still usable), 3 fatal
log "running osmcoastline"
rc=0
osmcoastline "$work/coastline.osm.pbf" \
  --output-database="$work/coastline.db" \
  --output-polygons=land \
  --srs=3857 \
  --max-points="$MAX_POINTS" \
  --overwrite \
  --verbose || rc=$?
[ "$rc" -le 2 ] || { log "osmcoastline failed with rc=$rc"; exit 1; }
log "osmcoastline rc=$rc"

count=$(layer_count "$work/coastline.db" land_polygons)
error_points=$(layer_count "$work/coastline.db" error_points)
error_lines=$(layer_count "$work/coastline.db" error_lines)
log "land_polygons=$count error_points=$error_points error_lines=$error_lines"

if [ "${count:-0}" -lt "$MIN_LAND_POLYGONS" ]; then
  log "only ${count:-0} land polygons, minimum is $MIN_LAND_POLYGONS"
  exit 1
fi

# A broken coastline makes the sea flood the land, so do not publish a big drop
prev=$(curl -fsS -A "$USER_AGENT" "$PUBLIC_URL/$META_NAME" 2>/dev/null | jq -r '.land_polygons // empty' || true)
if [ -n "$prev" ] && [ "${FORCE:-false}" != "true" ]; then
  min=$(( prev * (100 - MAX_DROP_PCT) / 100 ))
  if [ "$count" -lt "$min" ]; then
    log "land polygons dropped from $prev to $count (more than $MAX_DROP_PCT%), not publishing. Set FORCE=true to publish anyway."
    exit 1
  fi
fi

log "writing $ZIP_NAME"
shp_dir=$work/land-polygons-split-3857
mkdir -p "$shp_dir"
# The .shp name becomes the table name in the tiler DB
ogr2ogr -f "ESRI Shapefile" "$shp_dir/land_polygons.shp" "$work/coastline.db" land_polygons
(cd "$work" && zip -qr "$OUT_DIR/$ZIP_NAME.tmp" land-polygons-split-3857)
mv "$OUT_DIR/$ZIP_NAME.tmp" "$OUT_DIR/$ZIP_NAME"

log "writing $ERRORS_NAME"
errors_dir=$work/coastline-errors
mkdir -p "$errors_dir"
for layer in error_points error_lines; do
  ogr2ogr -f GeoJSON -t_srs EPSG:4326 "$errors_dir/$layer.geojson" "$work/coastline.db" "$layer"
done
(cd "$work" && zip -qr "$OUT_DIR/$ERRORS_NAME.tmp" coastline-errors)
mv "$OUT_DIR/$ERRORS_NAME.tmp" "$OUT_DIR/$ERRORS_NAME"

jq -n \
  --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg planet "${PLANET_KEY:-$PLANET_FILE}" \
  --arg date "$COASTLINE_DATE" \
  --argjson rc "$rc" \
  --argjson land "$count" \
  --argjson points "${error_points:-0}" \
  --argjson lines "${error_lines:-0}" \
  '{created: $created, planet: $planet, coastline_date: $date, osmcoastline_rc: $rc,
    land_polygons: $land, error_points: $points, error_lines: $lines}' > "$OUT_DIR/$META_NAME"
cat "$OUT_DIR/$META_NAME"

if [ -n "$AWS_S3_BUCKET" ]; then
  for f in "$ZIP_NAME" "$ERRORS_NAME" "$META_NAME"; do
    log "uploading $f to $AWS_S3_BUCKET/$S3_PREFIX/"
    aws s3 cp "$OUT_DIR/$f" "$AWS_S3_BUCKET/$S3_PREFIX/$f" --acl public-read
  done
else
  log "AWS_S3_BUCKET is empty, files stay in $OUT_DIR"
fi

rm -rf "$work"
