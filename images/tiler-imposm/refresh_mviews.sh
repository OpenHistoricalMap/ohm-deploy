#!/bin/bash
# This script refreshes materialized views in PostgreSQL concurrently.
# It is designed to run in the background and refresh views in parallel.
PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function refresh_mviews_group() {
    local group_name="$1"
    local sleep_interval="$2"
    shift 2
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
        sleep "$sleep_interval"
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
    "mview_transport_lines_z6"
    "mview_transport_lines_z7"
    "mview_transport_lines_z8"
    "mview_transport_lines_z9"
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
)


other_areas_views=(
    "mview_other_areas_centroids_z6_8"
    "mview_other_areas_centroids_z9_11"
    "mview_other_areas_centroids_z12_14"
    "mview_other_areas_centroids_z15_20"
    "mview_other_areas_z6_8"
    "mview_other_areas_z9_11"
    "mview_other_areas_z12_14"
)

mview_buildings_points_centroids_views=(
    "mview_buildings_points_centroids_z14"
    "mview_buildings_points_centroids_z15"
    "mview_buildings_points_centroids_z16"
    "mview_buildings_points_centroids_z17"
    "mview_buildings_points_centroids_z18_20"
)


# Start refreshing in parallel with a sleep interval  all of them in average of 4 min refresh
## Benchmark admin refresh those views takes 4 min to complete
refresh_mviews_group "admin" 1 "${admin_views[@]}" &
## Benchmark transport refresh those views takes 40 seconds to complete
refresh_mviews_group "transport" 200 "${transport_views[@]}" &
## Benchmark water areas and centroids refresh those views takes 1:20 min to complete
refresh_mviews_group "water" 160 "${water_views[@]}" &
## Benchmark landuse centroids refresh those views takes 22 secs to complete
refresh_mviews_group "landuse" 220 "${landuse_views[@]}" &
## Benchmark other areas and centroids refresh those views takes 3 secs to complete
refresh_mviews_group "other_areas" 230 "${other_areas_views[@]}" &
## Benchmark: Refreshing building points/centroids takes 60 seconds to complete.
refresh_mviews_group "buildings_points_centroids" 230 "${mview_buildings_points_centroids_views[@]}" &
