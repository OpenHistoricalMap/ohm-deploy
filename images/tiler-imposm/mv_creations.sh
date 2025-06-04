#!/bin/bash
set -e

source ./scripts/utils.sh

# log_message "Creating utility functions and generic materialized views"
# psql $PG_CONNECTION -f queries/utils/create_generic_mview.sql 
# psql $PG_CONNECTION -f queries/utils/date_utils.sql 
# psql $PG_CONNECTION -f queries/utils/fetch_db_languages.sql 
# psql $PG_CONNECTION -f queries/utils/get_language_columns.sql 
# psql $PG_CONNECTION -f queries/utils/postgis_helpers.sql 
# psql $PG_CONNECTION -f queries/utils/postgis_post_import.sql

log_message "Creating materialized views for OSM data"
psql $PG_CONNECTION -f queries/ohm_mviews/admin_boundaries_centroids.sql 
### psql $PG_CONNECTION -f queries/ohm_mviews/admin_boundaries_lines.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/admin_boundaries_maritime.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/amenity.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/buildings.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/landuse.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/others.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/places.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/transport.sql 
psql $PG_CONNECTION -f queries/ohm_mviews/water.sql

log_message "Creating materialized views for NE data"
psql $PG_CONNECTION -f queries/ne_mviews/lakes.sql

log_message "Creating materialized views for OSM data - land"
psql $PG_CONNECTION -f queries/osm_views/land.sql
