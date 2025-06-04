#!/bin/bash
set -e

source ./scripts/utils.sh

function execute_sql_file() {
    local file="$1"
    log_message "Executing: $file"
    if psql "$PG_CONNECTION" -f "$file"; then
        log_message "✅ Successfully executed: $file"
    else
        log_message "❌ ERROR executing: $file"
    fi
}

##################### Utils #####################
log_message "Creating utility functions and generic materialized views"
execute_sql_file queries/utils/create_generic_mview.sql 
execute_sql_file queries/utils/date_utils.sql 
execute_sql_file queries/utils/fetch_db_languages.sql 
execute_sql_file queries/utils/get_language_columns.sql 
execute_sql_file queries/utils/postgis_helpers.sql 
execute_sql_file queries/utils/postgis_post_import.sql

##################### NE #####################
log_message "Creating materialized views for NE data"
execute_sql_file queries/ne_mviews/lakes.sql

##################### OSM #####################
log_message "Creating materialized views for OSM data - land"
execute_sql_file queries/osm_views/land.sql

##################### OHM #####################
log_message "Creating materialized views for OSM data"
execute_sql_file queries/ohm_mviews/admin_boundaries_centroids.sql 
### execute_sql_file queries/ohm_mviews/admin_boundaries_lines.sql 
execute_sql_file queries/ohm_mviews/admin_boundaries_maritime.sql 
execute_sql_file queries/ohm_mviews/amenity.sql 
execute_sql_file queries/ohm_mviews/buildings.sql 
execute_sql_file queries/ohm_mviews/landuse.sql 
execute_sql_file queries/ohm_mviews/others.sql 
execute_sql_file queries/ohm_mviews/places.sql 
execute_sql_file queries/ohm_mviews/transport.sql 
execute_sql_file queries/ohm_mviews/water.sql
