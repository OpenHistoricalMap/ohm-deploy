#!/bin/bash

# Update materialized views every 10 seconds. Actually, it will be in the queue until the previous one is done.
SLEEP_INTERVAL=10
PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function refresh_admin_boundaries_mviews() {
    local materialized_views=(
        "mview_admin_boundaries_centroid_z0_2"
        "mview_admin_boundaries_centroid_z3_5"
        "mview_admin_boundaries_centroid_z6_7"
        "mview_admin_boundaries_centroid_z8_9"
        "mview_admin_boundaries_centroid_z10_12"
        "mview_admin_boundaries_centroid_z13_15"
        "mview_admin_boundaries_centroid_z16_20"
        "mview_land_ohm_lines_z0_2"
        "mview_land_ohm_lines_z3_5"
        "mview_land_ohm_lines_z6_7"
        "mview_land_ohm_lines_z8_9"
        "mview_land_ohm_lines_z8_9"
        "mview_land_ohm_lines_z10_12"
        "mview_land_ohm_lines_z16_20"
    )

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "Refreshing $mview..."
            
            if psql "$PG_CONNECTION" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" > /dev/null 2>&1; then
                log_message "Successfully refreshed $mview."
            else
                log_message "ERROR refreshing $mview!"
            fi
        done
        sleep $SLEEP_INTERVAL
    done
}

function refresh_transport_lines_mviews() {
    local materialized_views=(
        "mview_transport_lines_z5_7"
        "mview_transport_lines_z8_9"
        "mview_transport_lines_z10_11"
        "mview_transport_lines_z12_13"
        "mview_transport_lines_z14_20"
    )

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "Refreshing $mview..."
            
            if psql "$PG_CONNECTION" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" > /dev/null 2>&1; then
                log_message "Successfully refreshed $mview."
            else
                log_message "ERROR refreshing $mview!"
            fi
        done
        sleep $SLEEP_INTERVAL
    done
}

function refresh_water_areas_mviews() {
    local materialized_views=(
        "mview_water_areas_centroid_z0_2"
        "mview_water_areas_centroid_z3_5"
        "mview_water_areas_centroid_z6_7"
        "mview_water_areas_centroid_z8_9"
        "mview_water_areas_centroid_z10_12"
        "mview_water_areas_centroid_z13_15"
    )

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "Refreshing $mview..."
            
            if psql "$PG_CONNECTION" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" > /dev/null 2>&1; then
                log_message "Successfully refreshed $mview."
            else
                log_message "ERROR refreshing $mview!"
            fi
        done
        sleep $SLEEP_INTERVAL
    done
}

# Execute the function in the background
refresh_transport_lines_mviews & 
refresh_admin_boundaries_mviews &
refresh_water_areas_mviews &
