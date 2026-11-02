#!/usr/bin/env bash
# Shared settings and helpers for build.sh and load.sh
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

DATA_DIR=${DATA_DIR:-/data}
PLANET_FILE=${PLANET_FILE:-$DATA_DIR/planet.osm.pbf}
OUT_DIR=${OUT_DIR:-$DATA_DIR/out}
PLANET_DOWNLOAD_URL=${PLANET_DOWNLOAD_URL:-https://planet.openhistoricalmap.org}
PLANET_MAX_AGE_DAYS=${PLANET_MAX_AGE_DAYS:-30}
USER_AGENT=${USER_AGENT:-ohm-coastline}
APP_DIR=${APP_DIR:-/app}

# Only coastlines that exist on this date are used. Default: today.
COASTLINE_DATE=${COASTLINE_DATE:-$(date -u +%Y-%m-%d)}
# osmcoastline splits polygons bigger than this, same as the osmdata split files
MAX_POINTS=${MAX_POINTS:-1000}
# Fail when there are fewer land polygons than this
MIN_LAND_POLYGONS=${MIN_LAND_POLYGONS:-1}
# Fail when the land polygon count drops more than this % from the last published run
MAX_DROP_PCT=${MAX_DROP_PCT:-20}

# Publish to $AWS_S3_BUCKET/$S3_PREFIX/. Read back from $PUBLIC_URL.
AWS_S3_BUCKET=${AWS_S3_BUCKET:-}
S3_PREFIX=${S3_PREFIX:-coastline}
PUBLIC_URL=${PUBLIC_URL:-$PLANET_DOWNLOAD_URL/$S3_PREFIX}

ZIP_NAME=land-polygons-split-3857.zip
META_NAME=land-polygons-split-3857.json
ERRORS_NAME=coastline-errors.zip

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [$(basename "$0")] $*"; }

# There is no planet-latest file. Planets are named planet-YYMMDD_0000.osm.pbf,
# but not every day has one, so try each day back from today.
latest_planet_key() {
  local i key
  for i in $(seq 0 "$PLANET_MAX_AGE_DAYS"); do
    key="planet/planet-$(date -u -d "$i days ago" +%y%m%d)_0000.osm.pbf"
    if curl -fsI -A "$USER_AGENT" -o /dev/null "$PLANET_DOWNLOAD_URL/$key"; then
      echo "$key"
      return 0
    fi
  done
}

download_planet() {
  local key
  key=$(latest_planet_key)
  [ -n "$key" ] || { log "no planet file in the last $PLANET_MAX_AGE_DAYS days on $PLANET_DOWNLOAD_URL"; return 1; }
  log "downloading $key"
  curl -fsSL -A "$USER_AGENT" -o "$PLANET_FILE.tmp" "$PLANET_DOWNLOAD_URL/$key"
  mv "$PLANET_FILE.tmp" "$PLANET_FILE"
  PLANET_KEY=$key
}

# Number of features in a layer of an OGR source
layer_count() {
  ogrinfo -ro -q "$1" -sql "SELECT COUNT(*) AS n FROM $2" | awk -F'= ' '/n \(Integer.*\) =/ {print $2; exit}'
}

pg_url() {
  echo "postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:${POSTGRES_PORT:-5432}/$POSTGRES_DB"
}

pg_ogr() {
  echo "PG:dbname='$POSTGRES_DB' host='$POSTGRES_HOST' port='${POSTGRES_PORT:-5432}' user='$POSTGRES_USER' password='$POSTGRES_PASSWORD'"
}
