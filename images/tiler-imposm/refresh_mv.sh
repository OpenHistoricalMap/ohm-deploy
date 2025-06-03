#!/bin/bash
# This script continuously refreshes PostgreSQL materialized views using wrapper functions, running in background per group.

PG_CONNECTION="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

function log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

function run_pg_function_loop() {
    local group_name="$1"
    local sql="$2"
    local interval="$3"

    while true; do
        log_message "[$group_name] ▶️ Running: $sql"
        if psql "$PG_CONNECTION" -c "$sql;"; then
            log_message "[$group_name] ✅ Successfully executed."
        else
            log_message "[$group_name] ❌ ERROR executing."
        fi
        log_message "[$group_name] ⏳ Sleeping ${interval}s before next run..."
        sleep "$interval"
    done
}

# Start both loops in background
run_pg_function_loop "admin_boundaries_centroids" "SELECT refresh_all_admin_boundaries_centroids(FALSE)" 600 &
run_pg_function_loop "admin_boundaries_lines" "SELECT refresh_all_admin_boundaries_lines()" 600 &
run_pg_function_loop "admin_maritime_lines" "SELECT refresh_all_admin_maritime_lines(FALSE)" 600 &
run_pg_function_loop "amenity_areas" "SELECT refresh_all_osm_amenity_areas(TRUE)" 60 &


