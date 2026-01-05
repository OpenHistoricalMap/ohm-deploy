#!/bin/bash
set -e

# ============================================================================
# Script: refresh_mviews.sh
# Description:
#   Optimized script to refresh materialized views efficiently
#   WITHOUT competing with Imposm imports or tile generation.
#
#   KEY OPTIMIZATION: Minimize database locks to allow Imposm to write freely
#   - ONLY 1 refresh at a time globally (no parallelism)
#   - Longer intervals between refresh cycles (5+ minutes)
#   - Load monitoring enabled by default
#   - Automatic detection and termination of idle transactions blocking Imposm
#   - Dependency respect: Updates base views before dependent ones
#
#   Implemented improvements:
#   1. SEQUENTIAL refreshes: Only 1 view refreshes at a time to minimize locks
#   2. Dependency handling: Respects update order for views that depend on
#      others (e.g., routes, admin_boundaries)
#   3. Strict concurrency control: Maximum 1 simultaneous refresh globally
#   4. Time tracking: Measures and reports execution time for each update
#   5. Lock cleanup: Automatically removes locks from terminated processes
#   6. Smart pause: Pauses refreshes during high load or when Imposm is importing
#   7. Idle transaction killer: Detects and terminates transactions blocking Imposm
#
# Environment variables:
#   MAX_CONCURRENT_REFRESHES: Maximum number of simultaneous refreshes (default: 1)
#   PAUSE_ON_HIGH_LOAD: Pause refreshes if there's high load (default: true)
#   HIGH_LOAD_THRESHOLD: Active connections threshold to pause (default: 50)
#   KILL_IDLE_TRANSACTIONS: Kill idle transactions > 5min (default: true)
#   IDLE_TRANSACTION_TIMEOUT: Minutes before killing idle transaction (default: 5)
#
# Usage:
#   ./refresh_mviews.sh
#   MAX_CONCURRENT_REFRESHES=1 ./refresh_mviews.sh
#   PAUSE_ON_HIGH_LOAD=true HIGH_LOAD_THRESHOLD=50 ./refresh_mviews.sh
#
# IMPORTANT:
#   - Imposm needs EXCLUSIVE write access to osm_* tables
#   - REFRESH MATERIALIZED VIEW CONCURRENTLY can still acquire SHARE locks
#   - This script prioritizes Imposm over view freshness
#   - Views refresh every 5-10 minutes instead of constantly
# ============================================================================

source ./scripts/utils.sh

# Global concurrency configuration
# CRITICAL: Only 1 refresh at a time to minimize locks on Imposm tables
MAX_CONCURRENT_REFRESHES=${MAX_CONCURRENT_REFRESHES:-1}
REFRESH_LOCK_DIR="/tmp/mview_refresh_locks"
mkdir -p "$REFRESH_LOCK_DIR"

# Priority configuration: pause refreshes if there's high DB load or Imposm is importing
# Load monitoring ENABLED by default to protect Imposm writes
PAUSE_ON_HIGH_LOAD=${PAUSE_ON_HIGH_LOAD:-true}
HIGH_LOAD_THRESHOLD=${HIGH_LOAD_THRESHOLD:-50}  # Pause if there are more than 50 active connections

# Idle transaction killer configuration
# Automatically terminates idle transactions that may be blocking Imposm
KILL_IDLE_TRANSACTIONS=${KILL_IDLE_TRANSACTIONS:-true}
IDLE_TRANSACTION_TIMEOUT=${IDLE_TRANSACTION_TIMEOUT:-5}  # Minutes before killing

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

# Function to kill idle transactions that may be blocking Imposm
kill_idle_transactions() {
    if [ "$KILL_IDLE_TRANSACTIONS" != "true" ]; then
        return 0
    fi

    local killed_pids=$(psql "$PG_CONNECTION" -t -A -c \
        "SELECT pg_terminate_backend(pid)
         FROM pg_stat_activity
         WHERE state = 'idle in transaction'
           AND NOW() - state_change > interval '${IDLE_TRANSACTION_TIMEOUT} minutes'
           AND pid != pg_backend_pid()
           AND usename != 'imposm';" 2>/dev/null)

    if [ -n "$killed_pids" ] && [ "$killed_pids" != "f" ]; then
        log_message "[CLEANUP] ⚠️  Terminated idle transaction(s) blocking database"
    fi
}

# Function to check if Imposm is actively importing
check_imposm_activity() {
    # Check if there are active queries from Imposm user
    local imposm_active=$(psql "$PG_CONNECTION" -t -A -c \
        "SELECT count(*) FROM pg_stat_activity
         WHERE state = 'active'
           AND usename = 'imposm'
           AND pid != pg_backend_pid();" 2>/dev/null | tr -d ' \n')

    if [ -n "$imposm_active" ] && [ "$imposm_active" -gt "0" ]; then
        return 1  # Imposm is importing, pause refreshes
    fi
    return 0  # Imposm not active
}

# Function to check database load
check_db_load() {
    if [ "$PAUSE_ON_HIGH_LOAD" != "true" ]; then
        return 0  # Don't check if disabled
    fi

    # First, check if Imposm is actively importing
    if ! check_imposm_activity; then
        log_message "[LOAD] ⏸️  Imposm is importing, pausing refreshes..."
        return 1
    fi

    local active_connections=$(psql "$PG_CONNECTION" -t -A -c \
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active' AND pid != pg_backend_pid();" 2>/dev/null | tr -d ' \n')

    if [ -z "$active_connections" ]; then
        # If we can't get the count, assume it's okay (don't block)
        return 0
    fi

    if [ "$active_connections" -gt "$HIGH_LOAD_THRESHOLD" ]; then
        log_message "[LOAD] ⏸️  High DB load ($active_connections active connections, threshold: $HIGH_LOAD_THRESHOLD)"
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
        # Kill idle transactions before starting cycle
        kill_idle_transactions

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
        # Kill idle transactions before starting cycle
        kill_idle_transactions

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
# CRITICAL OPTIMIZATION: All refreshes are SEQUENTIAL (parallelism = 1)
# This minimizes locks on Imposm tables and allows Imposm to write freely
#
# Strategy:
#   - Only 1 background process per group (10 groups total)
#   - MAX_CONCURRENT_REFRESHES=1 ensures only 1 view refreshes at a time globally
#   - Longer intervals (5-10 minutes) between refresh cycles
#   - Load monitoring enabled by default to pause during Imposm imports
#   - Idle transaction killer runs before each cycle

# Groups with dependencies (must be refreshed in order)
# ADMIN_BOUNDARIES_LINES: Increased from 1s to 300s to reduce lock contention
refresh_dependent_group "ADMIN_BOUNDARIES_LINES" 300 \
    "admin_boundaries_lines_base_views" \
    "admin_boundaries_lines_intermediate_views" \
    "admin_boundaries_lines_views" \
    1 &  # Sequential refresh only

# ROUTES: Keep 300s interval, sequential refresh
refresh_dependent_group "ROUTES" 300 \
    "routes_base_views" \
    "routes_intermediate_views" \
    "routes_views" \
    1 &  # Sequential refresh only

# Independent groups - ALL SEQUENTIAL (parallelism = 1)
# Increased intervals from 60-180s to 300-600s to reduce lock frequency
refresh_mviews_group "ADMIN_BOUNDARIES_CENTROIDS" 300 1 "${admin_boundaries_centroids_views[@]}" &
refresh_mviews_group "ADMIN_MARITIME_LINES" 600 1 "${admin_maritime_lines_views[@]}" &
refresh_mviews_group "TRANSPORTS" 300 1 "${transport_views[@]}" &
refresh_mviews_group "AMENITY" 300 1 "${amenity_views[@]}" &
refresh_mviews_group "LANDUSE" 300 1 "${landuse_views[@]}" &
refresh_mviews_group "OTHERS" 300 1 "${others_views[@]}" &
refresh_mviews_group "PLACES" 300 1 "${places_views[@]}" &
refresh_mviews_group "WATER" 300 1 "${water_views[@]}" &
refresh_mviews_group "BUILDINGS" 300 1 "${buildings_views[@]}" &
refresh_mviews_group "ADMIN_BOUNDARIES_AREAS" 300 1 "${admin_boundaries_areas_views[@]}" &

# Wait for all processes to finish (should never happen in an infinite loop)
wait
