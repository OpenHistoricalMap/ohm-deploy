#!/bin/bash
# Update materialized views every 10 seconds. Actually, it will be in the queue until the previous one is done.
SLEEP_INTERVAL=10
PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function refresh_mviews_group() {
    local group_name="$1"
    shift
    local materialized_views=("$@")

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "[$group_name] Refreshing $mview..."
            if psql "$PG_CONNECTION" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" > /dev/null 2>&1; then
                log_message "[$group_name] Successfully refreshed $mview."
            else
                log_message "[$group_name] ERROR refreshing $mview!"
            fi
        done
        sleep "$SLEEP_INTERVAL"
    done
}

# Define materialized views by group
admin_views=(
    "mview_admin_boundaries_centroid_z0_2"
    "mview_admin_boundaries_centroid_z3_5"
    "mview_admin_boundaries_centroid_z6_7"
    "mview_admin_boundaries_centroid_z8_9"
    "mview_admin_boundaries_centroid_z10_12"
    "mview_admin_boundaries_centroid_z13_15"
    "mview_admin_boundaries_centroid_z16_20"
    "mview_relation_members_boundaries"
    "mview_admin_boundaries_relations_ways"
    "mview_land_ohm_lines_z0_2"
    "mview_land_ohm_lines_z3_5"
    "mview_land_ohm_lines_z6_7"
    "mview_land_ohm_lines_z8_9"
    "mview_land_ohm_lines_z10_12"
    "mview_land_ohm_lines_z13_15"
    "mview_land_ohm_lines_z16_20"
)

transport_views=(
    "mview_transport_lines_z5_7"
    "mview_transport_lines_z8_9"
    "mview_transport_lines_z10_11"
    "mview_transport_lines_z12_13"
    "mview_transport_lines_z14_20"
)

water_views=(
    "mview_water_areas_z0_2_subdivided"
    "mview_water_areas_z3_5_subdivided"
    "mview_water_areas_z6_7_subdivided"
    "mview_water_areas_z8_9_subdivided"
    "mview_water_areas_centroid_z0_2"
    "mview_water_areas_centroid_z3_5"
    "mview_water_areas_centroid_z6_7"
    "mview_water_areas_centroid_z8_9"
    "mview_water_areas_centroid_z10_12"
    "mview_water_areas_centroid_z13_15"
)

landuse_views=(
    "mview_landuse_areas_centroid_z3_5"
    "mview_landuse_areas_centroid_z6_7"
    "mview_landuse_areas_centroid_z8_9"
    "mview_landuse_areas_centroid_z10_12"
    "mview_landuse_areas_centroid_z13_15"
    "mview_landuse_areas_z3_5_subdivided"
    "mview_landuse_areas_z6_7_subdivided"
    "mview_landuse_areas_z8_9_subdivided"
)

# Start refreshing in parallel
refresh_mviews_group "transport" "${transport_views[@]}" &
refresh_mviews_group "admin" "${admin_views[@]}" &
refresh_mviews_group "water" "${water_views[@]}" &
refresh_mviews_group "landuse" "${landuse_views[@]}" &
