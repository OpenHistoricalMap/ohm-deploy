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

export POSTGRES_PORT=$([[ "$DOCKER_CONFIG_ENVIRONMENT" == "production" ]] && echo 5432 || echo 54321)

PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

NIM_NUMBER_LANGUAGES="${NIM_NUMBER_LANGUAGES:-5}" # Default to 5 languages
FORCE_MVIEWS_GENERATION="${FORCE_MVIEWS_GENERATION:-false}"
EVALUATION_INTERVAL="${EVALUATION_INTERVAL:-3600}" # Default to 1 hour (3600 seconds)

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


function get_new_languages_bbox() {
  ## This function retrieves the bounding boxes of new languages from the database.
  psql "$PG_CONNECTION" -t -A -F '|' -c \
  "SELECT alias,
          ST_XMin(b) || ',' || ST_YMin(b) || ',' || ST_XMax(b) || ',' || ST_YMax(b) AS bbox_str
   FROM (
     SELECT alias, ST_Transform(ST_SetSRID(bbox, 3857), 4326) AS b
     FROM languages
     WHERE is_new = TRUE
   ) sub;"
}

function restart_production_containers() {
  ## ================================================================= 
  ## Update materialized views with the new language columns. This takes around 10 minutes.
  ## NOTE: This will not affect the currently running tiler server.
  ## =================================================================
  docker compose -f  tiler.production.yml run imposm /osm/scripts/create_mviews.sh # --all=true

  ## ================================================================= 
  ## Restart imposm, which going to refresh the mviews
  ## =================================================================
  ## docker compose -f tiler.production.yml up imposm_production -d --force-recreate

  ## =================================================================
  ## Restart tiler container, which is going to take the new languages in the configuration 
  ## =================================================================
  docker compose -f tiler.production.yml up tiler_production -d --force-recreate

  ## =================================================================
  ## Restart global cache generator and coverage 
  ## =================================================================
  docker compose -f tiler.production.yml up global_seeding_production -d --force-recreate
  docker compose -f tiler.production.yml up tile_coverage_seeding_production -d --force-recreate

  ## =================================================================
  ## Remove tiles that the new languages are covering. 
  ## =================================================================
  get_new_languages_bbox | while IFS='|' read -r alias bbox; do
    echo "Language: $alias"
    docker compose -f tiler.staging.yml run s3_tiles python delete_s3_tiles.py --bbox="$bbox"
  done
}


function restart_staging_containers() {
  ## Restart staging continaers - testing environment
  docker compose -f  tiler.staging.yml run imposm_staging /osm/scripts/create_mviews.sh 
  docker compose -f tiler.staging.yml up imposm_staging -d --force-recreate
  docker compose -f tiler.staging.yml up tiler_staging -d --force-recreate
  docker compose -f tiler.staging.yml up tiler_sqs_cleaner_staging -d --force-recreate
  get_new_languages_bbox | while IFS='|' read -r alias bbox; do
    echo "Language: $alias"
    docker compose -f tiler.staging.yml run tiler_s3_cleaner_staging python delete_s3_tiles.py --bbox="$bbox"
  done
}

while true; do
  echo "Checking for language changes..."

  psql "$PG_CONNECTION" -c "SELECT populate_languages(${NIM_NUMBER_LANGUAGES}, '${FORCE_MVIEWS_GENERATION}'::BOOLEAN);"
  HAS_CHANGED=$(psql "$PG_CONNECTION" -t -A -c "SELECT EXISTS (SELECT 1 FROM languages WHERE is_new = TRUE);")
  echo "has_changed = $HAS_CHANGED"
  if [[ "$HAS_CHANGED" == "t" ]]; then
    echo "Restarting Docker containers..."
    restart_staging_containers
    # if [[ "$DOCKER_CONFIG_ENVIRONMENT" == "production" ]]; then
    #   restart_production_containers
    # else
    #   restart_staging_containers
    # fi
  else
    echo "No changes detected. Waiting $EVALUATION_INTERVAL seconds..."
  fi
  echo "----------------------------------------"
  sleep "$EVALUATION_INTERVAL"
done
