#!/bin/bash
set -e

export PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

function log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

execute_sql_file() {
    local file="$1"
    log_message "Executing: $file"

    local start_time=$SECONDS
    if psql "$PG_CONNECTION" -f "$file"; then
        local elapsed=$((SECONDS - start_time))
        log_message "✅ Successfully executed: $file (Time: ${elapsed}s)"
    else
        local elapsed=$((SECONDS - start_time))
        log_message "❌ ERROR executing: $file (Time: ${elapsed}s)"
    fi
}