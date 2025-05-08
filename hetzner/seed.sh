#!/bin/bash

UTILS_DIR="/opt/utils"
CONFIG_DIR="/opt/config"
TEGOLA_CONFIG_DIR="/opt/tegola_config"

TAGINFO_URL="https://taginfo.openhistoricalmap.org/api/4/keys/all"
LANGUAGE_SQL_FILE="${CONFIG_DIR}/languages.sql"
TEGOLA_CONFIG_FILE="${TEGOLA_CONFIG_DIR}/config.toml"

mkdir -p ${CONFIG_DIR} ${TEGOLA_CONFIG_DIR}

# Extract language tags
echo "Extracting languages from Taginfo..."
python "${UTILS_DIR}/extract_taginfo_languages.py" \
  --url "${TAGINFO_URL}" \
  --output "${LANGUAGE_SQL_FILE}"

# Build Tegola config
echo "Building Tegola config..."
python "${UTILS_DIR}/build_config.py" \
  --output="${TEGOLA_CONFIG_FILE}" \
  --provider_names "admin_boundaries_lines,
admin_boundaries.centroids,
admin_boundaries_maritime,
place_areas,
place_points,
water_areas,
water_areas.centroids,
water_lines,
transport_areas,
transport_associated_streets,
transport_lines,
transport_points,
route_lines,
amenity_areas,
amenity_areas.centroids,
amenity_points,
buildings,
buildings_points_centroids,
buildings.centroids,
buildings_points,
landuse_areas,
landuse_areas.centroids,
landuse_lines,
landuse_points,
other_areas,
other_areas.centroids,
other_lines,
other_points"

seed_global() {
  while true; do
    echo "Starting global seeding..."
    pkill -f "tegola" && sleep 5

    # Seed all areas (min 0 to max 5)
    tegola cache seed tile-name "0/0/0"  \
      --config=/opt/tegola_config/config.toml \
      --map=osm \
      --min-zoom=0 \
      --max-zoom=5 \
      --concurrency=4 \
      --overwrite=true

    # Seed land areas separately (zoom 6-7)
    for zoom in $(seq 6 7); do
      echo "Downloading tile list for zoom level $zoom..."
      wget -O /opt/tile-list.tiles "https://s3.amazonaws.com/planet.openhistoricalmap.org/tile_coverage/tiles_boundary_$zoom.list"

      tegola cache seed tile-list /opt/tile-list.tiles \
        --config=/opt/tegola_config/config.toml \
        --map=osm \
        --min-zoom="$zoom" \
        --max-zoom="$zoom" \
        --concurrency=4 \
        --overwrite=true
    done
    echo "Global seeding completed. Sleeping for 3 hour..."
    sleep 600
  done
}

seed_coverage() {
  while true; do
    echo "Starting coverage seeding..."
    wget -O /opt/tile-list.tiles "https://s3.amazonaws.com/planet.openhistoricalmap.org/tile_coverage/tiles_14.list"
    pkill -f "tegola" && sleep 5

    for zoom in $(seq 8 14); do
      echo "Downloading tile list for zoom level $zoom..."
      wget -O /opt/tile-list.tiles "https://s3.amazonaws.com/planet.openhistoricalmap.org/tile_coverage/tiles_boundary_$zoom.list"

      tegola cache seed tile-list /opt/tile-list.tiles \
        --config=/opt/tegola_config/config.toml \
        --map=osm \
        --min-zoom=$zoom \
        --max-zoom=$zoom \
        --concurrency=4 \
        --overwrite=false
    done
    sleep 300
  done
}

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <global|coverage>"
  exit 1
fi

case "$1" in
  global)
    seed_global
    ;;
  coverage)
    seed_coverage
    ;;
  *)
    echo "Invalid option. Use 'global' or 'coverage'."
    exit 1
    ;;
esac
