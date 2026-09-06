#!/bin/bash
set -e

source ./scripts/utils.sh

# ============================================================================
# Function: refresh_mviews_group
# Description:
#   Refreshes a group of materialized views in an infinite loop.
#   Each view is refreshed using REFRESH MATERIALIZED VIEW CONCURRENTLY to
#   avoid blocking reads during the refresh operation.
#   Each group runs as a background process for parallel execution.
#
# Parameters:
#   $1 - group_name: Name of the group (used for logging purposes)
#   $2 - sleep_interval: Number of seconds to wait between refresh cycles
#   $3 - mem_profile: "light" or "heavy" memory profile
#   $@ - materialized_views: Array of materialized view names to refresh
#
# Usage:
#   refresh_mviews_group "WATER" 180 light "${water_views[@]}" &
# ============================================================================
LIGHT_WORK_MEM="${LIGHT_WORK_MEM:-256MB}"
LIGHT_MAINT_MEM="${LIGHT_MAINT_MEM:-2GB}"
HEAVY_WORK_MEM="${HEAVY_WORK_MEM:-1GB}"
HEAVY_MAINT_MEM="${HEAVY_MAINT_MEM:-8GB}"

function refresh_mviews_group() {
    local group_name="$1"
    local sleep_interval="$2"
    local mem_profile="${3:-light}"  # "light" or "heavy"
    shift 3
    local materialized_views=("$@")

    local work_mem="$LIGHT_WORK_MEM"
    local maint_mem="$LIGHT_MAINT_MEM"
    local parallel_workers="${LIGHT_PARALLEL_WORKERS:-0}"
    if [ "$mem_profile" = "heavy" ]; then
        work_mem="$HEAVY_WORK_MEM"
        maint_mem="$HEAVY_MAINT_MEM"
        parallel_workers="${HEAVY_PARALLEL_WORKERS:-4}"
    fi

    local total_views=${#materialized_views[@]}

    while true; do
        local cycle_start=$SECONDS
        local failed_count=0
        local failed_list=""
        local last_error=""
        for mview in "${materialized_views[@]}"; do
            log_message "[$group_name] Refreshing $mview (work_mem=$work_mem, maintenance_work_mem=$maint_mem)..."
            local error_output
            local exit_code=0
            local start_time=$SECONDS
            error_output=$(psql "$PG_CONNECTION" -v ON_ERROR_STOP=1 \
                -c "SET statement_timeout = 0" \
                -c "SET work_mem = '$work_mem'" \
                -c "SET maintenance_work_mem = '$maint_mem'" \
                -c "SET max_parallel_workers_per_gather = $parallel_workers" \
                -c "REFRESH MATERIALIZED VIEW CONCURRENTLY $mview;" 2>&1) || exit_code=$?
            local elapsed=$((SECONDS - start_time))
            if [ $exit_code -eq 0 ]; then
                log_message "[$group_name] ✅ Successfully refreshed $mview. Time: ${elapsed}s"
            else
                failed_count=$((failed_count + 1))
                failed_list="${failed_list}${mview} "
                last_error="$error_output"
                log_message "[$group_name] ❌ ERROR refreshing $mview! Exit code: $exit_code"
                log_message "[$group_name] ❌ Error details: $error_output"
                if echo "$error_output" | grep -qi "connection\|could not connect\|server closed\|SSL\|recovery mode"; then
                    log_message "[$group_name] ⚠️ Connection error detected. Waiting 180s for DB to recover..."
                    sleep 180
                    break
                fi
            fi
        done
        local cycle_duration=$((SECONDS - cycle_start))
        local status="success"
        [ $failed_count -gt 0 ] && status="error"
        write_status "$group_name" "$status" "$cycle_duration" "$total_views" "$failed_count" "$failed_list" "$last_error"
        sleep "$sleep_interval"
    done
}

log_message "Starting parallel refresh of materialized views..."
# One background loop per refresh group declared in layers/<name>/layer.yaml
while IFS='|' read -r group_name profile interval mviews; do
    refresh_mviews_group "$group_name" "$interval" "$profile" $mviews &
done < <(python3 scripts/layers.py refresh)
wait
