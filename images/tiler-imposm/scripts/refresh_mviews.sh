#!/bin/bash
set -e

source ./scripts/utils.sh

# ============================================================================
# Function: refresh_mviews_group
# Description:
#   Refreshes a group of materialized views sequentially in an infinite loop.
#   Each view is refreshed using REFRESH MATERIALIZED VIEW CONCURRENTLY to
#   avoid blocking reads during the refresh operation.
#
# Parameters:
#   $1 - group_name: Name of the group (used for logging purposes)
#   $2 - sleep_interval: Number of seconds to wait between refresh cycles
#   $@ - materialized_views: Array of materialized view names to refresh
#
# Behavior:
#   - Runs in an infinite loop
#   - Refreshes all views in the group sequentially (one after another)
#   - Uses CONCURRENTLY to avoid blocking database reads
#   - Logs success/failure for each view refresh
#   - Waits for sleep_interval seconds after completing each full cycle
#
# Usage:
#   refresh_mviews_group "GROUP_NAME" 180 "${views_array[@]}" &
#
# Example:
#   refresh_mviews_group "WATER" 180 "${water_views[@]}" &
# ============================================================================
LIGHT_WORK_MEM="64MB"
LIGHT_MAINT_MEM="256MB"
HEAVY_WORK_MEM="512MB"
HEAVY_MAINT_MEM="4GB"

function refresh_mviews_group() {
    local group_name="$1"
    local sleep_interval="$2"
    local mem_profile="${3:-light}"  # "light" or "heavy"
    shift 3
    local materialized_views=("$@")

    local work_mem="$LIGHT_WORK_MEM"
    local maint_mem="$LIGHT_MAINT_MEM"
    if [ "$mem_profile" = "heavy" ]; then
        work_mem="$HEAVY_WORK_MEM"
        maint_mem="$HEAVY_MAINT_MEM"
    fi

    while true; do
        for mview in "${materialized_views[@]}"; do
            log_message "[$group_name] Refreshing $mview (work_mem=$work_mem, maintenance_work_mem=$maint_mem)..."
            local error_output
            # Disable statement_timeout for long-running refresh operations (0 = no limit)
            local exit_code=0
            local start_time=$SECONDS
            error_output=$(psql "$PG_CONNECTION" -v ON_ERROR_STOP=1 \
                -c "SET statement_timeout = 0" \
                -c "SET work_mem = '$work_mem'" \
                -c "SET maintenance_work_mem = '$maint_mem'" \
                -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" 2>&1) || exit_code=$?
            local elapsed=$((SECONDS - start_time))
            if [ $exit_code -eq 0 ]; then
                log_message "[$group_name] ✅ Successfully refreshed $mview. Time: ${elapsed}s"
            else
                log_message "[$group_name] ❌ ERROR refreshing $mview! Exit code: $exit_code"
                log_message "[$group_name] ❌ Error details: $error_output"
                # If connection failed, skip remaining views and wait before retrying
                if echo "$error_output" | grep -qi "connection\|could not connect\|server closed\|SSL"; then
                    log_message "[$group_name] ⚠️ Connection error detected. Waiting ${sleep_interval}s before retrying all views..."
                    break
                fi
            fi
        done
        sleep "$sleep_interval"
    done
}


admin_boundaries_lines_views=(
    mv_relation_members_boundaries
    mv_admin_boundaries_relations_ways
    mv_admin_boundaries_lines_z16_20
    mv_admin_boundaries_lines_z13_15
    mv_admin_boundaries_lines_z10_12
    mv_admin_boundaries_lines_z8_9
    mv_admin_boundaries_lines_z6_7
    mv_admin_boundaries_lines_z3_5
    mv_admin_boundaries_lines_z0_2
)

admin_boundaries_areas_centroids_views=(
    # areas
    mv_admin_boundaries_areas_z16_20
    mv_admin_boundaries_areas_z13_15
    mv_admin_boundaries_areas_z10_12
    mv_admin_boundaries_areas_z8_9
    mv_admin_boundaries_areas_z6_7
    mv_admin_boundaries_areas_z3_5
    mv_admin_boundaries_areas_z0_2
    # centroids
    mv_admin_boundaries_centroids_z0_2
    mv_admin_boundaries_centroids_z3_5
    mv_admin_boundaries_centroids_z6_7
    mv_admin_boundaries_centroids_z8_9
    mv_admin_boundaries_centroids_z10_12
    mv_admin_boundaries_centroids_z13_15
    mv_admin_boundaries_centroids_z16_20
)

admin_maritime_lines_views=(    
    mv_admin_maritime_lines_z0_5_v2
    mv_admin_maritime_lines_z6_9
    mv_admin_maritime_lines_z10_15
)

amenity_views=(
    # areas
    mv_amenity_areas_z14_15
    mv_amenity_areas_z16_20
    # points
    mv_amenity_points
    # points centroids
    mv_amenity_points_centroids_z14_15
    mv_amenity_points_centroids_z16_20
)

landuse_views=(
    # areas
    mv_landuse_areas_z6_7
    mv_landuse_areas_z8_9
    mv_landuse_areas_z10_12
    mv_landuse_areas_z13_15
    mv_landuse_areas_z16_20
    # points
    mv_landuse_points
    # points centroids
    mv_landuse_points_centroids_z6_7
    mv_landuse_points_centroids_z8_9
    mv_landuse_points_centroids_z10_12
    mv_landuse_points_centroids_z13_15
    mv_landuse_points_centroids_z16_20
    # lines
    mv_landuse_lines_z14_15
    mv_landuse_lines_z16_20
)

others_views=(
    # areas
    mv_other_areas_z8_9
    mv_other_areas_z10_12
    mv_other_areas_z13_15
    mv_other_areas_z16_20
    # points
    mv_other_points
    # points centroids
    mv_other_points_centroids_z8_9
    mv_other_points_centroids_z10_12
    mv_other_points_centroids_z13_15
    mv_other_points_centroids_z16_20
    # lines
    mv_other_lines_z16_20
    mv_other_lines_z14_15
)

communication_views=(
    # lines
    mv_communication_z16_20
    mv_communication_z13_15
    mv_communication_z10_12
)

places_views=(
    mv_place_points_centroids_z0_2
    mv_place_points_centroids_z3_5
    mv_place_points_centroids_z6_10
    mv_place_points_centroids_z11_20
    mv_place_areas_z14_20
)


transport_views=(
    # lines
    mv_transport_lines_z16_20
    mv_transport_lines_z13_15
    mv_transport_lines_z10_12
    mv_transport_lines_z8_9
    mv_transport_lines_z6_7
    mv_transport_lines_z5
    # areas
    mv_transport_areas_z16_20
    mv_transport_areas_z13_15
    mv_transport_areas_z10_12
    # points
    mv_transport_points
    # points centroids
    mv_transport_points_centroids_z16_20
    mv_transport_points_centroids_z13_15
    mv_transport_points_centroids_z10_12
)


water_views=(
    # areas
    mv_water_areas_z16_20
    mv_water_areas_z13_15
    mv_water_areas_z10_12
    mv_water_areas_z8_9
    mv_water_areas_z6_7
    mv_water_areas_z3_5
    mv_water_areas_z0_2
    # centroids
    mv_water_areas_centroids_z16_20
    mv_water_areas_centroids_z13_15
    mv_water_areas_centroids_z10_12
    mv_water_areas_centroids_z8_9
    # lines
    mv_water_lines_z16_20
    mv_water_lines_z13_15
    mv_water_lines_z10_12
    mv_water_lines_z8_9
)

buildings_views=(
    # areas
    mv_buildings_areas_z14_15
    mv_buildings_areas_z16_20
    # points
    mv_buildings_points
    # points centroids
    mv_buildings_points_centroids_z14_15
    mv_buildings_points_centroids_z16_20
)

routes_views=(
    ## normalized
    mv_routes_normalized
    mv_routes_indexed
    ## indexed
    mv_routes_indexed_z16_20
    mv_routes_indexed_z13_15
    mv_routes_indexed_z10_12
    mv_routes_indexed_z8_9
    mv_routes_indexed_z6_7
    mv_routes_indexed_z5
)

no_admin_boundaries_views=(
    # areas
    mv_non_admin_boundaries_areas_z16_20
    mv_non_admin_boundaries_areas_z13_15
    mv_non_admin_boundaries_areas_z10_12
    mv_non_admin_boundaries_areas_z8_9
    mv_non_admin_boundaries_areas_z6_7
    mv_non_admin_boundaries_areas_z3_5
    mv_non_admin_boundaries_areas_z0_2

    # centroids
    mv_non_admin_boundaries_centroids_z16_20
    mv_non_admin_boundaries_centroids_z13_15
    mv_non_admin_boundaries_centroids_z10_12
    mv_non_admin_boundaries_centroids_z8_9
    mv_non_admin_boundaries_centroids_z6_7
    mv_non_admin_boundaries_centroids_z3_5
    mv_non_admin_boundaries_centroids_z0_2
)



# REFRESH_PARALLEL: "true" = all groups in parallel (default), "false" = sequential
REFRESH_PARALLEL="${REFRESH_PARALLEL:-true}"

# NO_ADMIN_BOUNDARIES always runs in its own background loop (refreshes every 10 hours)
refresh_mviews_group "NO_ADMIN_BOUNDARIES" 36000 light "${no_admin_boundaries_views[@]}" &

if [ "$REFRESH_PARALLEL" = "true" ]; then
    log_message "Starting PARALLEL refresh of materialized views..."

    # Heavy groups
    refresh_mviews_group "ADMIN_BOUNDARIES_LINES" 60 heavy "${admin_boundaries_lines_views[@]}" &
    refresh_mviews_group "ADMIN_BOUNDARIES_AREAS_CENTROIDS" 180 heavy "${admin_boundaries_areas_centroids_views[@]}" &
    refresh_mviews_group "TRANSPORTS" 180 heavy "${transport_views[@]}" &

    # Light groups
    refresh_mviews_group "ADMIN_MARITIME_LINES" 300 light "${admin_maritime_lines_views[@]}" &
    refresh_mviews_group "AMENITY" 180 light "${amenity_views[@]}" &
    refresh_mviews_group "LANDUSE" 180 light "${landuse_views[@]}" &
    refresh_mviews_group "OTHERS" 180 light "${others_views[@]}" &
    refresh_mviews_group "COMMUNICATION" 180 light "${communication_views[@]}" &
    refresh_mviews_group "PLACES" 180 light "${places_views[@]}" &
    refresh_mviews_group "WATER" 180 light "${water_views[@]}" &
    refresh_mviews_group "BUILDINGS" 180 light "${buildings_views[@]}" &
    refresh_mviews_group "ROUTES" 180 light "${routes_views[@]}" &
else
    log_message "Starting SEQUENTIAL refresh of materialized views..."

    # Heavy groups
    refresh_mviews_group "ADMIN_BOUNDARIES_LINES" 1 heavy "${admin_boundaries_lines_views[@]}"
    refresh_mviews_group "ADMIN_BOUNDARIES_AREAS_CENTROIDS" 1 heavy "${admin_boundaries_areas_centroids_views[@]}"
    refresh_mviews_group "TRANSPORTS" 1 heavy "${transport_views[@]}"

    # Light groups
    refresh_mviews_group "ADMIN_MARITIME_LINES" 1 light "${admin_maritime_lines_views[@]}"
    refresh_mviews_group "AMENITY" 1 light "${amenity_views[@]}"
    refresh_mviews_group "LANDUSE" 1 light "${landuse_views[@]}"
    refresh_mviews_group "OTHERS" 1 light "${others_views[@]}"
    refresh_mviews_group "COMMUNICATION" 1 light "${communication_views[@]}"
    refresh_mviews_group "PLACES" 1 light "${places_views[@]}"
    refresh_mviews_group "WATER" 1 light "${water_views[@]}"
    refresh_mviews_group "BUILDINGS" 1 light "${buildings_views[@]}"
    refresh_mviews_group "ROUTES" 1 light "${routes_views[@]}"
fi
