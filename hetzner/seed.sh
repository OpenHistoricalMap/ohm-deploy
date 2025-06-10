#!/bin/bash

# Configurable paths
WORK_DIR="/app"
SCRIPTS_DIR="${WORK_DIR}/scripts"
PROVIDERS_DIR="${WORK_DIR}/config/providers"
TEGOLA_CONFIG_FILE="${WORK_DIR}/config/config.toml"
CONFIG_TEMPLATE_FILE="${WORK_DIR}/config/config.template.toml"

# Build Tegola config
echo "Building Tegola config..."
python "${SCRIPTS_DIR}/build_config.py" \
  --template="${CONFIG_TEMPLATE_FILE}" \
  --output="${TEGOLA_CONFIG_FILE}" \
  --providers="${PROVIDERS_DIR}" \
  --provider_names "
admin_boundaries_lines,
admin_boundaries_centroids,
admin_boundaries_maritime,
place_areas,
place_points_centroids,
water_areas,
water_areas_centroids,
water_lines,
transport_areas,
transport_lines,
transport_points_centroids,
amenity_areas,
amenity_points_centroids,
buildings_areas,
buildings_points_centroids,
landuse_areas,
landuse_points_centroids,
landuse_lines,
other_areas,
other_points_centroids,
other_lines"


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
    echo "Global seeding completed. Sleeping for 1 hour..."
    sleep 1800
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
    echo "Global seeding completed. Sleeping for 5 minutes.."
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
