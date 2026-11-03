#!/usr/bin/env bash
# Fill the land that OHM does not have yet with the OSM land polygons.
#
# Usage: merge_osm.sh OHM_DB OUT_GPKG
#   OHM_DB    osmcoastline output with the land_polygons layer
#   OUT_GPKG  GeoPackage with the merged land_polygons layer
#
# Open OHM coastlines do not make polygons, so OSM land stays there until the
# ring is closed in OHM. See merge_osm.py for the merge rules.
set -euo pipefail
source "$(dirname "$0")/common.sh"

ohm_db=$1
out=$2
work=$DATA_DIR/osm-land
rm -rf "$work" && mkdir -p "$work"

log "downloading $OSM_LAND_URL"
# osmdata.openstreetmap.de is sometimes down; fall back to our copy on planet.openhistoricalmap.org
if ! curl -fsSL --retry 2 -A "$USER_AGENT" -o "$work/osm.zip" "$OSM_LAND_URL"; then
  fallback="$PLANET_DOWNLOAD_URL/osmdata/$(basename "$OSM_LAND_URL")"
  log "download failed, trying $fallback"
  curl -fsSL --retry 2 -A "$USER_AGENT" -o "$work/osm.zip" "$fallback"
fi
unzip -q "$work/osm.zip" -d "$work"
rm -f "$work/osm.zip"
osm_shp=$(find "$work" -type f -name 'land_polygons.shp' | head -1)
[ -n "$osm_shp" ] || { log "land_polygons.shp not found in $OSM_LAND_URL"; exit 1; }

rm -f "$out"
log "merging OHM land with OSM land (buffer ${OSM_CUT_BUFFER}m)"
python3 -I "$APP_DIR/scripts/merge_osm.py" "$ohm_db" "$osm_shp" "$out" "$OSM_CUT_BUFFER"

rm -rf "$work"
