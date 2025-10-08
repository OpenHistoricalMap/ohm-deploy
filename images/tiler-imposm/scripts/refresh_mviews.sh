#!/bin/bash
set -e

source ./scripts/utils.sh

function refresh_mviews_group() {
    local group_name="$1"
    local sleep_interval="$2"
    shift 2
    local materialized_views=("$@")

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "[$group_name] Refreshing $mview..."
            if psql "$PG_CONNECTION" -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;"; then
                log_message "[$group_name] ✅ Successfully refreshed $mview."
            else
                log_message "[$group_name] ❌ ERROR refreshing $mview!"
            fi
        done
        sleep "$sleep_interval"
    done
}


admin_boundaries_centroids_views=(
    mv_admin_boundaries_centroids_z0_2
    mv_admin_boundaries_centroids_z3_5
    mv_admin_boundaries_centroids_z6_7
    mv_admin_boundaries_centroids_z8_9
    mv_admin_boundaries_centroids_z10_12
    mv_admin_boundaries_centroids_z13_15
    mv_admin_boundaries_centroids_z16_20
)

admin_boundaries_lines_views=(
    mv_relation_members_boundaries
    mv_admin_boundaries_relations_ways
    mv_admin_boundaries_lines_z0_2
    mv_admin_boundaries_lines_z3_5
    mv_admin_boundaries_lines_z6_7
    mv_admin_boundaries_lines_z8_9
    mv_admin_boundaries_lines_z10_12
    mv_admin_boundaries_lines_z13_15
    mv_admin_boundaries_lines_z16_20
)

admin_maritime_lines_views=(    
    mv_admin_maritime_lines_z0_5
    mv_admin_maritime_lines_z6_9
    mv_admin_maritime_lines_z10_15
)

amenity_views=(
    mv_amenity_areas_z14_20
    mv_amenity_points_centroids_z14_20
) # TODO , missing amenity lines

landuse_views=(
    mv_landuse_areas_z3_5
    mv_landuse_areas_z6_7
    mv_landuse_areas_z8_9
    mv_landuse_areas_z10_12
    mv_landuse_areas_z13_15
    mv_landuse_points_centroids_z10_11
    mv_landuse_points_centroids_z12_13
    mv_landuse_points_centroids_z14_20
    mv_landuse_lines_z14_20
)

others_views=(
    mv_other_points_centroids_z14_20
    mv_other_areas_z14_20
    mv_other_lines_z14_20
)

places_views=(
    mv_place_points_centroids_z0_2
    mv_place_points_centroids_z3_5
    mv_place_points_centroids_z6_10
    mv_place_points_centroids_z11_20
    mv_place_areas_z14_20
)

transport_views=(
    mv_transport_lines_z5
    mv_transport_lines_z6
    mv_transport_lines_z7
    mv_transport_lines_z8
    mv_transport_lines_z9
    mv_transport_lines_z10_11
    mv_transport_lines_z12_13
    mv_transport_lines_z14_20
    mv_transport_areas_z10_11
    mv_transport_areas_z12_20
    mv_transport_points_centroids_z10_13
    mv_transport_points_centroids_z14_20
)

water_views=(
    mv_water_areas_centroids_z0_2
    mv_water_areas_centroids_z3_5
    mv_water_areas_centroids_z6_7
    mv_water_areas_centroids_z8_9
    mv_water_areas_centroids_z10_12
    mv_water_areas_centroids_z13_20
    mv_water_areas_z0_2_subdivided
    mv_water_areas_z3_5_subdivided
    mv_water_areas_z6_7_subdivided
    mv_water_areas_z8_9_subdivided
    mv_water_areas_z10_12
    mv_water_areas_z13_15
    mv_water_areas_z16_20
    mv_water_lines_z8_9
    mv_water_lines_z10_12
    mv_water_lines_z13_15
    mv_water_lines_z16_20
)

buildings_views=(
    mv_buildings_points_centroids_z14_20
    mv_osm_buildings_areas_z14_20
)

routes_views=(
    mv_routes_normalized
    mv_routes_indexed
    mv_routes_indexed_z5_6
    mv_routes_indexed_z7_8
    mv_routes_indexed_z9_10
    mv_routes_indexed_z11_13
    mv_routes_indexed_z14_20
)


admin_boundaries_areas_views=(
    mv_admin_boundaries_areas_z0_2
    mv_admin_boundaries_areas_z3_5
    mv_admin_boundaries_areas_z6_7
    mv_admin_boundaries_areas_z8_9
    mv_admin_boundaries_areas_z10_12
    mv_admin_boundaries_areas_z13_15
    mv_admin_boundaries_areas_z16_20
)



refresh_mviews_group "ADMIN_BOUNDARIES_CENTROIDS" 60 "${admin_boundaries_centroids_views[@]}" &
refresh_mviews_group "ADMIN_BOUNDARIES_LINES" 1 "${admin_boundaries_lines_views[@]}" &
refresh_mviews_group "ADMIN_MARITIME_LINES" 300 "${admin_maritime_lines_views[@]}" &
refresh_mviews_group "TRANSPORTS" 180 "${transport_views[@]}" &
refresh_mviews_group "AMENITY" 180 "${amenity_views[@]}" &
refresh_mviews_group "LANDUSE" 180 "${landuse_views[@]}" &
refresh_mviews_group "OTHERS" 180 "${others_views[@]}" &
refresh_mviews_group "PLACES" 180 "${places_views[@]}" &
refresh_mviews_group "WATER" 180 "${water_views[@]}" &
refresh_mviews_group "BUILDINGS" 180 "${buildings_views[@]}" &
refresh_mviews_group "ROUTES" 180 "${routes_views[@]}" &
refresh_mviews_group "ADMIN_BOUNDARIES_AREAS" 180 "${admin_boundaries_areas_views[@]}" &
