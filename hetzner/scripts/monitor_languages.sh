#!/bin/bash
# -----------------------------------------------------------------------------
# Script: monitor_languages.sh
# Description:
#   This script monitors the PostgreSQL database for new language tags.
#   If changes are detected, it will regenerate materialized views and
#   restart relevant Docker containers depending on the environment (staging or production).
#
#   - It supports configurable environment variables via .env.<environment> files.
#   - The script checks for updates every N seconds (default: 600). 86400 (24 hours) 
#   - It uses a confirmation prompt before running the evaluation loop.
#
# Environment Variables:
#   DOCKER_CONFIG_ENVIRONMENT  - Target environment (default: "staging")
#   NIM_NUMBER_LANGUAGES       - Max number of languages to track (default: 10)
#   FORCE_MVIEWS_GENERATION    - Force refresh of all mviews (default: false)
#   EVALUATION_INTERVAL        - Interval in seconds between checks (default: 600)
#
# Usage:
#   bash monitor_languages.sh
# -----------------------------------------------------------------------------
set -e

export DOCKER_CONFIG_ENVIRONMENT="staging"
source ".env.${DOCKER_CONFIG_ENVIRONMENT}"

export POSTGRES_HOST="localhost"
export POSTGRES_PORT=$([[ "$DOCKER_CONFIG_ENVIRONMENT" == "production" ]] && echo 5432 || echo 5433)

PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

NIM_NUMBER_LANGUAGES="${NIM_NUMBER_LANGUAGES:-10}"
FORCE_MVIEWS_GENERATION="${FORCE_MVIEWS_GENERATION:-false}"
EVALUATION_INTERVAL="${EVALUATION_INTERVAL:-600}"

echo "Configuration Summary:"
echo "  Environment:             $DOCKER_CONFIG_ENVIRONMENT"
echo "  Postgres Host:           $POSTGRES_HOST"
echo "  Postgres Port:           $POSTGRES_PORT"
echo "  Database:                $POSTGRES_DB"
echo "  User:                    $POSTGRES_USER"
echo "  NIM_NUMBER_LANGUAGES:    $NIM_NUMBER_LANGUAGES"
echo "  FORCE_MVIEWS_GENERATION: $FORCE_MVIEWS_GENERATION"
echo "  EVALUATION_INTERVAL:     $EVALUATION_INTERVAL seconds"
echo

read -p "Do you want to run the script? This script will restart containers if a new language is added to the database. (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborting script."
  exit 0
fi

while true; do
  echo "Checking for language changes..."

  psql "$PG_CONNECTION" -c "SELECT update_languages_from_tables(${NIM_NUMBER_LANGUAGES}::INT, ${FORCE_MVIEWS_GENERATION}::BOOLEAN);"
  HAS_CHANGED=$(psql "$PG_CONNECTION" -t -A -c "SELECT has_changed FROM languages_hash ORDER BY id DESC LIMIT 1;")
  echo "has_changed = $HAS_CHANGED"

  if [[ "$HAS_CHANGED" == "t" ]]; then
    set -x
    echo "Restarting Docker containers..."
    if [[ "$DOCKER_CONFIG_ENVIRONMENT" == "production" ]]; then
      echo "producion"
      docker compose -f  tiler.production.yml run imposm /osm/scripts/create_mviews.sh 
      docker compose -f tiler.production.yml up imposm_production -d --force-recreate
      docker compose -f tiler.production.yml up tiler_production -d --force-recreate
      docker compose -f hetzner/tiler.production.yml up global_seeding_production -d --force-recreate
      docker compose -f hetzner/tiler.production.yml up tile_coverage_seeding_production -d --force-recreate
      docker compose -f hetzner/tiler.production.yml up remove_cache_tiles_production -d --force-recreate
    else
      docker compose -f tiler.staging.yml run imposm /osm/scripts/create_mviews.sh 
      docker compose -f tiler.staging.yml up imposm -d --force-recreate
      docker compose -f tiler.staging.yml up tiler -d --force-recreate
    fi
    set +x
  else
    echo "No changes detected. Waiting $EVALUATION_INTERVAL seconds..."
  fi
  echo "----------------------------------------"
  sleep "$EVALUATION_INTERVAL"
done
