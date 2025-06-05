#!/bin/bash
set -e

export PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

function log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

function execute_sql_file() {
    local file="$1"
    log_message "Executing: $file"
    if psql "$PG_CONNECTION" -f "$file"; then
        log_message "✅ Successfully executed: $file"
    else
        log_message "❌ ERROR executing: $file"
    fi
}
