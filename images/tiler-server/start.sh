#!/usr/bin/env bash
set -euo pipefail

echo "Starting tile server setup..."

# Configurable paths
WORK_DIR="/app"
SCRIPTS_DIR="${WORK_DIR}/scripts"
PROVIDERS_DIR="${WORK_DIR}/config/providers"
TEGOLA_CONFIG_FILE="${WORK_DIR}/config/config.toml"
CONFIG_TEMPLATE_FILE="${WORK_DIR}/config/config.template.toml"

# Languages to geojson
echo "Extracting languages to geojson..."
python "${SCRIPTS_DIR}/lang2geojson.py"

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
