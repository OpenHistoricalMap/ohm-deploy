#!/usr/bin/env bash
set -euo pipefail

echo "Starting tile server setup..."

# Configurable paths
UTILS_DIR="/app/utils"
CONFIG_DIR="/app/config"
TEGOLA_CONFIG_DIR="/app/tegola_config"
TEGOLA_CONFIG_FILE="${TEGOLA_CONFIG_DIR}/config.toml"

mkdir -p ${CONFIG_DIR} ${TEGOLA_CONFIG_DIR}


# Build Tegola config
echo "Building Tegola config..."
python "${UTILS_DIR}/build_config.py" \
  --output="${TEGOLA_CONFIG_FILE}" \
  --provider_names "
admin_boundaries_lines,
admin_boundaries_centroids,
--admin_boundaries_maritime,
place_areas,
--place_points,
place_points_centroids,
water_areas,
water_areas_centroids,
--water_lines,
--transport_areas,
--transport_associated_streets,
transport_lines,
--transport_points,
transport_points_centroids,
--route_lines,
--amenity_areas,
--amenity_areas.centroids,
--amenity_points,
amenity_points_centroids,
--buildings,
buildings_points_centroids,
--buildings.centroids,
--buildings_points,
--landuse_areas,
--landuse_areas.centroids,
landuse_points_centroids,
--landuse_points,
--landuse_lines,
--other_areas,
--other_areas.centroids,
other_points_centroids,
--other_lines,
--other_points"


# Wait for PostgreSQL
echo "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" > /dev/null 2>&1; do
  sleep 1
done
echo "PostgreSQL is ready."

# Run VACUUM and ANALYZE
if [[ "${EXECUTE_VACUUM_ANALYZE:-false}" == "true" ]]; then
  echo "Running VACUUM and ANALYZE for public tables..."
  tables=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -Atc \
    "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")

  for table in $tables; do
    echo "Processing table: $table"

    echo "  VACUUM..."
    time psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "VACUUM $table;" > /dev/null

    echo "  ANALYZE..."
    time psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "ANALYZE $table;" > /dev/null
  done
  echo "VACUUM and ANALYZE completed."
fi

# Run REINDEX
if [[ "${EXECUTE_REINDEX:-false}" == "true" ]]; then
  echo "Running REINDEX on primary key indexes..."
  psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "
  DO \$\$
  DECLARE
      tbl RECORD;
      idx_name TEXT;
  BEGIN
      FOR tbl IN
          SELECT tablename FROM pg_tables WHERE schemaname = 'public'
      LOOP
          SELECT indexname INTO idx_name
          FROM pg_indexes
          WHERE schemaname = 'public'
            AND tablename = tbl.tablename
            AND indexname = tbl.tablename || '_pkey';

          IF idx_name IS NOT NULL THEN
              RAISE NOTICE 'Reindexing index: %', idx_name;
              EXECUTE format('REINDEX INDEX %I;', idx_name);
          END IF;
      END LOOP;
  END
  \$\$;" > /dev/null
  echo "REINDEX completed."
fi

# Start Tegola
echo "Starting Tegola server..."
# TEGOLA_SQL_DEBUG=LAYER_SQL:EXECUTE_SQL tegola serve --config="${TEGOLA_CONFIG_FILE}" --log-level=TRACE
tegola serve --config="${TEGOLA_CONFIG_FILE}"
