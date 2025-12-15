#!/bin/bash
set -e

# ============================================================================
# Script: refresh_mviews.sh
# Description:
#   Optimized script to refresh materialized views efficiently
#   WITHOUT competing with tile generation.
#
#   Optimization strategy:
#   - Conservative parallelism: Maximum 2 simultaneous refreshes globally
#   - Reduced parallelism per group: 1-2 views in parallel within each group
#   - Optional load monitoring: Can pause if there's high tile generation load
#   - Dependency respect: Updates base views before dependent ones
#
#   Implemented improvements:
#   1. Controlled parallelization: Updates multiple views in parallel within
#      each group, but with conservative limits to avoid competing with tiles
#   2. Dependency handling: Respects update order for views that depend on
#      others (e.g., routes, admin_boundaries)
#   3. Concurrency control: Limits the number of simultaneous refreshes
#      to avoid saturating the database (default: 2, vs previous 3)
#   4. Time tracking: Measures and reports execution time for each
#      update and complete cycle
#   5. Lock cleanup: Automatically removes locks from terminated processes
#   6. Smart pause: Option to pause refreshes during high load
#
# Environment variables:
#   MAX_CONCURRENT_REFRESHES: Maximum number of simultaneous refreshes (default: 2)
#   PAUSE_ON_HIGH_LOAD: Pause refreshes if there's high load (default: false)
#   HIGH_LOAD_THRESHOLD: Active connections threshold to pause (default: 180)
#
# Usage:
#   ./refresh_mviews.sh
#   MAX_CONCURRENT_REFRESHES=2 ./refresh_mviews.sh
#   PAUSE_ON_HIGH_LOAD=true HIGH_LOAD_THRESHOLD=170 ./refresh_mviews.sh
#
# IMPORTANT: 
#   - Tegola uses ~150 connections to generate tiles
#   - DB has ~200 max_connections
#   - This script uses maximum 2 simultaneous refreshes to leave margin
#   - CONCURRENTLY refreshes don't block reads, but consume resources
#   - If you notice tiles generate slower, reduce MAX_CONCURRENT_REFRESHES to 1
# ============================================================================

source ./scripts/utils.sh

# Global concurrency configuration
# IMPORTANT: Adjust according to DB capacity and tile load
# Tegola uses ~150 connections, DB has ~200 max_connections
# We leave margin for other operations
MAX_CONCURRENT_REFRESHES=${MAX_CONCURRENT_REFRESHES:-2}
REFRESH_LOCK_DIR="/tmp/mview_refresh_locks"
mkdir -p "$REFRESH_LOCK_DIR"

# Priority configuration: pause refreshes if there's high tile load
# You can monitor active connections and pause automatically
PAUSE_ON_HIGH_LOAD=${PAUSE_ON_HIGH_LOAD:-false}
HIGH_LOAD_THRESHOLD=${HIGH_LOAD_THRESHOLD:-180}  # Pause if there are more than 180 connections

# Function to acquire a concurrency lock
acquire_refresh_lock() {
    local lock_file="$REFRESH_LOCK_DIR/refresh.lock"
    local max_wait=${1:-300}  # Wait maximum 5 minutes by default
    local waited=0
    
    while [ $waited -lt $max_wait ]; do
        local current_count=$(find "$REFRESH_LOCK_DIR" -name "*.pid" 2>/dev/null | wc -l | tr -d ' ')
        
        if [ "$current_count" -lt "$MAX_CONCURRENT_REFRESHES" ]; then
            local pid_file="$REFRESH_LOCK_DIR/$$.pid"
            echo "$$" > "$pid_file"
            return 0
        fi
        
        sleep 1
        waited=$((waited + 1))
    done
    
    log_message "[LOCK] ⚠️  Timeout waiting for concurrency lock"
    return 1
}

# Function to release the lock
release_refresh_lock() {
    local pid_file="$REFRESH_LOCK_DIR/$$.pid"
    rm -f "$pid_file"
}

# Function to clean up orphaned locks
cleanup_stale_locks() {
    find "$REFRESH_LOCK_DIR" -name "*.pid" -type f | while read pid_file; do
        local pid=$(cat "$pid_file" 2>/dev/null)
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            rm -f "$pid_file"
        fi
    done
}

# Function to check database load
check_db_load() {
    if [ "$PAUSE_ON_HIGH_LOAD" != "true" ]; then
        return 0  # Don't check if disabled
    fi
    
    local active_connections=$(psql "$PG_CONNECTION" -t -A -c \
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid != pg_backend_pid();" 2>/dev/null | tr -d ' \n')
    
    if [ -z "$active_connections" ]; then
        # If we can't get the count, assume it's okay (don't block)
        return 0
    fi
    
    if [ "$active_connections" -gt "$HIGH_LOAD_THRESHOLD" ]; then
        return 1  # High load, pause
    fi
    return 0  # Normal load, continue
}

# Function to refresh a single view with time tracking
refresh_single_mview() {
    local mview="$1"
    local use_concurrent="${2:-true}"
    local start_time=$(date +%s)
    
    # Check load before starting
    if ! check_db_load; then
        local active_conn=$(psql "$PG_CONNECTION" -t -A -c \
            "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid != pg_backend_pid();" 2>/dev/null | tr -d ' \n')
        log_message "[REFRESH] ⏸️  Pausing update of $mview (high load: $active_conn active connections, threshold: $HIGH_LOAD_THRESHOLD)"
        return 2  # Special code for "paused due to load"
    fi
    
    log_message "[REFRESH] Starting update of $mview..."
    
    # Acquire lock before refreshing
    if ! acquire_refresh_lock; then
        log_message "[REFRESH] ❌ Could not acquire lock for $mview"
        return 1
    fi
    
    local refresh_cmd
    if [ "$use_concurrent" = "true" ]; then
        refresh_cmd="REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;"
    else
        refresh_cmd="REFRESH MATERIALIZED VIEW $mview;"
    fi
    
    if psql "$PG_CONNECTION" -c "$refresh_cmd"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_message "[REFRESH] ✅ $mview updated successfully (${duration}s)"
        release_refresh_lock
        return 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_message "[REFRESH] ❌ ERROR updating $mview (${duration}s)"
        release_refresh_lock
        return 1
    fi
}

# Improved function to refresh a group of views
# Now supports parallelization and dependencies
refresh_mviews_group() {
    local group_name="$1"
    local sleep_interval="$2"
    local max_parallel="${3:-1}"  # Maximum number of views to refresh in parallel
    shift 3
    local materialized_views=("$@")
    
    # Periodically clean up orphaned locks
    cleanup_stale_locks
    
    while true; do
        # Check load before starting cycle
        local retries=0
        while ! check_db_load && [ $retries -lt 10 ]; do
            sleep 30  # Wait 30 seconds if there's high load
            retries=$((retries + 1))
        done
        
        local group_start_time=$(date +%s)
        log_message "[$group_name] Starting update cycle (${#materialized_views[@]} views)"
        
        # If max_parallel is 1, refresh sequentially (original behavior)
        if [ "$max_parallel" -eq 1 ]; then
            for mview in "${materialized_views[@]}"; do
                refresh_single_mview "$mview" "true"
                local result=$?
                # If paused due to load, wait a bit more
                if [ $result -eq 2 ]; then
                    sleep 60
                fi
            done
        else
            # Refresh in parallel with limit
            local pids=()
            local index=0
            
            while [ $index -lt ${#materialized_views[@]} ]; do
                cleanup_finished_pids pids
                # Wait if we already have the maximum parallel processes
                while [ ${#pids[@]} -ge "$max_parallel" ]; do
                    cleanup_finished_pids pids
                    sleep 1
                done
                
                # Start new refresh in background
                refresh_single_mview "${materialized_views[$index]}" "true" &
                pids+=($!)
                index=$((index + 1))
                
                # Small pause between starts to avoid saturating
                sleep 2
            done
            
            # Wait for all processes to finish
            for pid in "${pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
        fi
        
        local group_end_time=$(date +%s)
        local group_duration=$((group_end_time - group_start_time))
        log_message "[$group_name] ✅ Cycle completed in ${group_duration}s. Waiting ${sleep_interval}s before next cycle..."
        sleep "$sleep_interval"
    done
}


# Views with dependencies - must be refreshed in order
admin_boundaries_lines_base_views=(
    mv_relation_members_boundaries
)

admin_boundaries_lines_intermediate_views=(
    mv_admin_boundaries_relations_ways
)

admin_boundaries_lines_views=(
    mv_admin_boundaries_lines_z0_2
    mv_admin_boundaries_lines_z3_5
    mv_admin_boundaries_lines_z6_7
    mv_admin_boundaries_lines_z8_9
    mv_admin_boundaries_lines_z10_12
    mv_admin_boundaries_lines_z13_15
    mv_admin_boundaries_lines_z16_20
)

admin_boundaries_centroids_views=(
    mv_admin_boundaries_centroids_z0_2
    mv_admin_boundaries_centroids_z3_5
    mv_admin_boundaries_centroids_z6_7
    mv_admin_boundaries_centroids_z8_9
    mv_admin_boundaries_centroids_z10_12
    mv_admin_boundaries_centroids_z13_15
    mv_admin_boundaries_centroids_z16_20
)

admin_maritime_lines_views=(    
    mv_admin_maritime_lines_z0_5
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
    mv_landuse_areas_z10_11
    mv_landuse_areas_z12_13
    mv_landuse_areas_z14_15
    mv_landuse_areas_z16_20
    # points
    mv_landuse_points
    # points centroids
    mv_landuse_points_centroids_z6_7
    mv_landuse_points_centroids_z8_9
    mv_landuse_points_centroids_z10_11
    mv_landuse_points_centroids_z12_13
    mv_landuse_points_centroids_z14_15
    mv_landuse_points_centroids_z16_20
    # lines
    mv_landuse_lines_z14_20
)

others_views=(
    # areas
    mv_other_areas_z8_9
    mv_other_areas_z10_11
    mv_other_areas_z12_13
    mv_other_areas_z14_15
    mv_other_areas_z16_20
    # points
    mv_other_points
    # points centroids
    mv_other_points_centroids_z8_9
    mv_other_points_centroids_z10_11
    mv_other_points_centroids_z12_13
    mv_other_points_centroids_z14_15
    mv_other_points_centroids_z16_20
    # lines
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
    # lines
    mv_transport_lines_z5
    mv_transport_lines_z6
    mv_transport_lines_z7
    mv_transport_lines_z8
    mv_transport_lines_z9
    mv_transport_lines_z10_11
    mv_transport_lines_z12_13
    mv_transport_lines_z14_20
    # areas
    mv_transport_areas_z10_11
    mv_transport_areas_z12_13
    mv_transport_areas_z14_15
    mv_transport_areas_z16_20
    # points
    mv_transport_points
    # points centroids
    mv_transport_points_centroids_z10_11
    mv_transport_points_centroids_z12_13
    mv_transport_points_centroids_z14_15
    mv_transport_points_centroids_z16_20
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
    # areas
    mv_buildings_areas_z14_15
    mv_buildings_areas_z16_20
    # points
    mv_buildings_points
    # points centroids
    mv_buildings_points_centroids_z14_15
    mv_buildings_points_centroids_z16_20
)

# Route views with dependencies
routes_base_views=(
    mv_routes_normalized
)

routes_intermediate_views=(
    mv_routes_indexed
)

routes_views=(
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



# Helper function to clean up finished PIDs
cleanup_finished_pids() {
    local -n pids_ref=$1
    local new_pids=()
    for pid in "${pids_ref[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            new_pids+=("$pid")
        fi
    done
    pids_ref=("${new_pids[@]}")
}

# Function to refresh groups with dependencies
refresh_dependent_group() {
    local group_name="$1"
    local sleep_interval="$2"
    local base_array_name="$3"
    local intermediate_array_name="$4"
    local dependent_array_name="$5"
    local max_parallel="${6:-3}"
    
    # Get arrays by name
    local base_views
    local intermediate_views
    local dependent_views
    eval "base_views=(\"\${${base_array_name}[@]}\")"
    eval "intermediate_views=(\"\${${intermediate_array_name}[@]}\")"
    eval "dependent_views=(\"\${${dependent_array_name}[@]}\")"
    
    while true; do
        local cycle_start=$(date +%s)
        log_message "[$group_name] Starting update cycle with dependencies"
        
        # Step 1: Refresh base views first (sequentially)
        if [ ${#base_views[@]} -gt 0 ]; then
            for mview in "${base_views[@]}"; do
                refresh_single_mview "$mview" "true"
            done
        fi
        
        # Step 2: Refresh intermediate views (can be in parallel)
        if [ ${#intermediate_views[@]} -gt 0 ]; then
            local pids=()
            local index=0
            while [ $index -lt ${#intermediate_views[@]} ]; do
                cleanup_finished_pids pids
                while [ ${#pids[@]} -ge "$max_parallel" ]; do
                    cleanup_finished_pids pids
                    sleep 1
                done
                refresh_single_mview "${intermediate_views[$index]}" "true" &
                pids+=($!)
                index=$((index + 1))
            done
            for pid in "${pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
        fi
        
        # Step 3: Refresh dependent views in parallel
        if [ ${#dependent_views[@]} -gt 0 ]; then
            local pids=()
            local index=0
            while [ $index -lt ${#dependent_views[@]} ]; do
                cleanup_finished_pids pids
                while [ ${#pids[@]} -ge "$max_parallel" ]; do
                    cleanup_finished_pids pids
                    sleep 1
                done
                refresh_single_mview "${dependent_views[$index]}" "true" &
                pids+=($!)
                index=$((index + 1))
            done
            for pid in "${pids[@]}"; do
                wait "$pid" 2>/dev/null || true
            done
        fi
        
        local cycle_end=$(date +%s)
        local cycle_duration=$((cycle_end - cycle_start))
        log_message "[$group_name] ✅ Cycle completed in ${cycle_duration}s. Waiting ${sleep_interval}s..."
        sleep "$sleep_interval"
    done
}

# Start update groups
# NOTE: Reduced parallelism to avoid competing with tile generation
# Tegola needs ~150 connections, we leave margin for other operations

# Groups with dependencies (must be refreshed in order)
# Reduced to 1-2 in parallel to minimize impact on tiles
refresh_dependent_group "ADMIN_BOUNDARIES_LINES" 1 \
    "admin_boundaries_lines_base_views" \
    "admin_boundaries_lines_intermediate_views" \
    "admin_boundaries_lines_views" \
    1 &  # Reduced to 1 for this critical group

refresh_dependent_group "ROUTES" 180 \
    "routes_base_views" \
    "routes_intermediate_views" \
    "routes_views" \
    2 &  # Reduced to 2

# Independent groups - conservative parallelism
# We reduce parallelism within each group to leave resources for tiles
refresh_mviews_group "ADMIN_BOUNDARIES_CENTROIDS" 60 2 "${admin_boundaries_centroids_views[@]}" &
refresh_mviews_group "ADMIN_MARITIME_LINES" 300 1 "${admin_maritime_lines_views[@]}" &
refresh_mviews_group "TRANSPORTS" 180 2 "${transport_views[@]}" &
refresh_mviews_group "AMENITY" 180 2 "${amenity_views[@]}" &
refresh_mviews_group "LANDUSE" 180 2 "${landuse_views[@]}" &
refresh_mviews_group "OTHERS" 180 2 "${others_views[@]}" &
refresh_mviews_group "PLACES" 180 2 "${places_views[@]}" &
refresh_mviews_group "WATER" 180 2 "${water_views[@]}" &
refresh_mviews_group "BUILDINGS" 180 1 "${buildings_views[@]}" &
refresh_mviews_group "ADMIN_BOUNDARIES_AREAS" 180 2 "${admin_boundaries_areas_views[@]}" &

# Wait for all processes to finish (should never happen in an infinite loop)
wait
