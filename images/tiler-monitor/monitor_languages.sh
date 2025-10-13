#!/bin/bash
set -e

GREEN="\033[0;32m"
NC="\033[0m"

log_message() {
    local message="$1"
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') - ${GREEN}${message}${NC}"
}

PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

NIM_NUMBER_LANGUAGES="${NIM_NUMBER_LANGUAGES:-5}" # Default to 5 languages
FORCE_LANGUAGES_GENERATION="${FORCE_LANGUAGES_GENERATION:-false}"
EVALUATION_INTERVAL="${EVALUATION_INTERVAL:-3600}" # Default to 1 hour

log_message "Configuration Summary:"
log_message "  Environment:             $DOCKER_CONFIG_ENVIRONMENT"
log_message "  Postgres Host:           $POSTGRES_HOST"
log_message "  Postgres Port:           $POSTGRES_PORT"
log_message "  Database:                $POSTGRES_DB"
log_message "  User:                    $POSTGRES_USER"
log_message "  NIM_NUMBER_LANGUAGES:    $NIM_NUMBER_LANGUAGES"
log_message "  FORCE_LANGUAGES_GENERATION: $FORCE_LANGUAGES_GENERATION"
log_message "  EVALUATION_INTERVAL:     $EVALUATION_INTERVAL seconds"

function restart_production_containers() {
  log_message "Running create_mviews.sh for production..."
  docker compose -f hetzner/tiler/tiler.production.yml run --no-TTY imposm_mv_production /osm/scripts/create_mviews.sh

  log_message "Restarting tiler_server_production..."
  docker compose -f hetzner/tiler/tiler.production.yml up tiler_server_production -d --force-recreate

  log_message "Cleaning tiles with tiler_s3_cleaner_production..."
  docker compose -f hetzner/tiler/tiler.production.yml run --no-TTY tiler_s3_cleaner_production tiler-cache-cleaner clean_by_prefix 

  log_message "Restarting global_seeding_production..."
  docker compose -f hetzner/tiler/tiler.production.yml up global_seeding_production -d --force-recreate

  log_message "Restarting tile_coverage_seeding_production..."
  docker compose -f hetzner/tiler/tiler.production.yml up tile_coverage_seeding_production -d --force-recreate
}

function restart_staging_containers() {
  log_message "Running create_mviews.sh for staging..."
  docker compose -f hetzner/tiler/tiler.staging.yml run --no-TTY imposm_mv_staging /osm/scripts/create_mviews.sh

  log_message "Restarting tiler_staging..."
  docker compose -f hetzner/tiler/tiler.staging.yml up tiler_staging -d --force-recreate

  log_message "Cleaning tiles with tiler_s3_cleaner_staging..."
  docker compose -f hetzner/tiler/tiler.staging.yml run --no-TTY tiler_s3_cleaner_staging tiler-cache-cleaner clean_by_prefix
}

log_message "Waiting for PostgreSQL to be ready..."
until pg_isready -h "${POSTGRES_HOST}" -U "${POSTGRES_USER}" -p "${POSTGRES_PORT}" > /dev/null 2>&1; do
  sleep 1
done
log_message "PostgreSQL is ready."

# Loop de monitoreo
while true; do
  log_message "Checking for language changes..."
  psql "$PG_CONNECTION" -c "SELECT populate_languages(${NIM_NUMBER_LANGUAGES}, '${FORCE_LANGUAGES_GENERATION}'::BOOLEAN);"
  HAS_CHANGED=$(psql "$PG_CONNECTION" -t -A -c "SELECT EXISTS (SELECT 1 FROM languages WHERE is_new = TRUE);")

  log_message "has_changed = $HAS_CHANGED"

  if [[ "$HAS_CHANGED" == "t" ]]; then
    log_message "Restarting Docker containers..."
    if [[ "$DOCKER_CONFIG_ENVIRONMENT" == "production" ]]; then
      restart_production_containers
    else
      restart_staging_containers
    fi
  else
    log_message "No changes detected. Sleeping for $EVALUATION_INTERVAL seconds..."
  fi
  log_message "Sleep for $EVALUATION_INTERVAL seconds before next check."
  sleep "$EVALUATION_INTERVAL"
done
