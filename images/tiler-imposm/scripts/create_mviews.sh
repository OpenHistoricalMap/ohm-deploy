#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# Script: create_mviews.sh
# Description:
#   This script creates materialized views (MViews) for OpenHistoricalMap (OHM),
#   including optional views for utilities, Natural Earth (NE), and OSM land data.
#   Use the '--force' argument to trigger creation of supporting utility functions,
#   NE layers, and base OSM layers.
#
# Usage:
#   ./create_mviews.sh             # Runs only OHM views
#   ./create_mviews.sh --force     # Runs OHM views + utils + NE + OSM base views, this is used at importing data 
# ------------------------------------------------------------------------------

source ./scripts/utils.sh

FORCE=false

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--force=true" ]]; then
    FORCE=true
  fi
done


if [[ "$FORCE" == true ]]; then
  ##################### Utils #####################
  log_message "Creating utility functions and generic materialized views"
  execute_sql_file queries/utils/utils.sql 
  execute_sql_file queries/utils/create_generic_mview.sql 
  execute_sql_file queries/utils/fetch_db_languages.sql 
  # execute_sql_file queries/utils/postgis_helpers.sql 
  # execute_sql_file queries/utils/postgis_post_import.sql

  ##################### NE #####################
  log_message "Creating materialized views for NE data"
  execute_sql_file queries/ne_mviews/lakes.sql

  ##################### OSM #####################
  log_message "Creating materialized views for OSM data - land"
  execute_sql_file queries/osm_mviews/land.sql

  ## Since admin boundary lines do not use languages, this will run only once.
  execute_sql_file queries/ohm_mviews/admin_boundaries_lines.sql
fi

##################### OHM #####################
# log_message "Creating materialized views for OSM data"
# execute_sql_file queries/ohm_mviews/admin_boundaries_centroids.sql
# execute_sql_file queries/ohm_mviews/admin_boundaries_maritime.sql
execute_sql_file queries/ohm_mviews/amenity.sql
# execute_sql_file queries/ohm_mviews/buildings.sql
# execute_sql_file queries/ohm_mviews/landuse.sql
# execute_sql_file queries/ohm_mviews/others.sql
# execute_sql_file queries/ohm_mviews/places.sql
# execute_sql_file queries/ohm_mviews/transport.sql
# execute_sql_file queries/ohm_mviews/water.sql
