#!/usr/bin/env bash
# Load a land-polygons-split-3857.zip into the land_polygons table of the tiler DB
# and refresh the materialized views that read it (mview_land_*).
#
# Usage: load.sh [ZIP_PATH_OR_URL]   default: $LAND_POLYGONS_URL, then $PUBLIC_URL/$ZIP_NAME
#
# The zip goes first into land_polygons_new. Copying it into land_polygons and the
# refresh run in one transaction, so the tiles never see an empty table.
# land_polygons is created empty if it does not exist.
set -euo pipefail
source "$(dirname "$0")/common.sh"

src=${1:-${LAND_POLYGONS_URL:-$PUBLIC_URL/$ZIP_NAME}}
work=$DATA_DIR/load
rm -rf "$work" && mkdir -p "$work"

if [ -f "$src" ]; then
  cp "$src" "$work/land.zip"
else
  log "downloading $src"
  curl -fsSL -A "$USER_AGENT" -o "$work/land.zip" "$src"
fi
unzip -q "$work/land.zip" -d "$work"
shp=$(find "$work" -type f -name 'land_polygons.shp' | head -1)
[ -n "$shp" ] || { log "land_polygons.shp not found in $src"; exit 1; }

db=$(pg_url)
psql "$db" -v ON_ERROR_STOP=1 -qc "DROP TABLE IF EXISTS land_polygons_new"

log "loading $shp into land_polygons_new"
OGR_ENABLE_PARTIAL_REPROJECTION=true ogr2ogr -f PostgreSQL "$(pg_ogr)" "$shp" \
  -nln land_polygons_new -t_srs EPSG:3857 -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=wkb_geometry -lco FID=ogc_fid -lco SPATIAL_INDEX=NONE

new_count=$(psql "$db" -tAc "SELECT COUNT(*) FROM land_polygons_new")
[ "$new_count" -gt 0 ] || { log "land_polygons_new is empty"; exit 1; }

psql "$db" -v ON_ERROR_STOP=1 -q <<'SQL'
CREATE TABLE IF NOT EXISTS land_polygons (
  ogc_fid serial PRIMARY KEY,
  wkb_geometry geometry(MultiPolygon, 3857)
);
CREATE INDEX IF NOT EXISTS land_polygons_wkb_geometry_geom_idx ON land_polygons USING GIST (wkb_geometry);
SQL

# Materialized views that read land_polygons. Found from pg_depend so this keeps
# working if the views in queries/osm_mviews/land.sql change.
mviews=$(psql "$db" -tAc "
  SELECT DISTINCT c.relname
  FROM pg_depend d
  JOIN pg_rewrite r ON r.oid = d.objid
  JOIN pg_class c ON c.oid = r.ev_class
  WHERE d.refobjid = 'public.land_polygons'::regclass
    AND c.relkind = 'm'
  ORDER BY 1")
log "views to refresh: $(echo "$mviews" | xargs)"

old_count=$(psql "$db" -tAc "SELECT COUNT(*) FROM land_polygons")
log "swapping land_polygons: $old_count -> $new_count rows"
start=$(date +%s)
{
  echo "BEGIN;"
  echo "TRUNCATE land_polygons;"
  echo "INSERT INTO land_polygons (wkb_geometry) SELECT wkb_geometry FROM land_polygons_new;"
  for v in $mviews; do echo "REFRESH MATERIALIZED VIEW $v;"; done
  echo "COMMIT;"
} | psql "$db" -v ON_ERROR_STOP=1 -q
log "swap done in $(( $(date +%s) - start ))s"

psql "$db" -v ON_ERROR_STOP=1 -qc "DROP TABLE land_polygons_new" -c "ANALYZE land_polygons"
rm -rf "$work"
