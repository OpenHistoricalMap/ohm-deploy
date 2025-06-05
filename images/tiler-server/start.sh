#!/usr/bin/env bash
set -euo pipefail

echo "Starting tile server setup..."

# Configurable paths
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
place_points_centroids,
water_areas,
water_areas.centroids,
water_lines,
transport_areas,
transport_associated_streets,
transport_lines,
transport_points,
transport_points_centroids,
route_lines,
amenity_areas,
amenity_areas.centroids,
amenity_points,
amenity_points_centroids,
buildings,
buildings_points_centroids,
buildings.centroids,
buildings_points,
landuse_areas,
landuse_areas.centroids,
landuse_points_centroids,
landuse_points,
landuse_lines,
other_areas,
other_areas.centroids,
other_points_centroids,
other_lines,
other_points"

# Wait for PostgreSQL
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" > /dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is ready."

# Start Tegola
echo "Starting Tegola server..."
# TEGOLA_SQL_DEBUG=LAYER_SQL:EXECUTE_SQL tegola serve --config="${TEGOLA_CONFIG_FILE}" --log-level=TRACE
tegola serve --config="${TEGOLA_CONFIG_FILE}"
