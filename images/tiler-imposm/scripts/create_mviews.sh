#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# Script: create_mviews.sh
# Description:
#   This script creates materialized views (MViews) for OpenHistoricalMap (OHM),
#   including optional views for utilities, Natural Earth (NE), and OSM land data.
#   Use the '--all' argument to trigger creation of supporting utility functions,
#   NE layers, and base OSM layers.
#
# Usage:
#   ./create_mviews.sh             # Runs only OHM views
#   ./create_mviews.sh --all==true     # Runs OHM views + utils + NE + OSM base views, this is used at importing data 
# ------------------------------------------------------------------------------

source ./scripts/utils.sh

ALL=false

# Parse arguments
for arg in "$@"; do
  if [[ "$arg" == "--all=true" ]]; then
    ALL=true
  fi
done

if [[ "$ALL" == true ]]; then
  ##################### Utils #####################
  log_message "Creating utility functions and generic materialized views"
  execute_sql_file queries/utils/utils.sql 
  execute_sql_file queries/utils/create_generic_mview.sql 
  # This will populate languages
  execute_sql_file queries/utils/fetch_db_languages.sql

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
log_message "Creating materialized views for OSM data"
execute_sql_file queries/ohm_mviews/admin_boundaries_centroids.sql
execute_sql_file queries/ohm_mviews/landuse.sql
execute_sql_file queries/ohm_mviews/admin_boundaries_maritime.sql
execute_sql_file queries/ohm_mviews/amenity.sql
execute_sql_file queries/ohm_mviews/buildings.sql
execute_sql_file queries/ohm_mviews/others.sql
execute_sql_file queries/ohm_mviews/places.sql
execute_sql_file queries/ohm_mviews/transport_areas.sql
execute_sql_file queries/ohm_mviews/transport_lines.sql
execute_sql_file queries/ohm_mviews/transport_points_centroids.sql
execute_sql_file queries/ohm_mviews/water.sql
