#!/bin/bash
set -e

export PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_message() {
    local message="$1"
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') - ${message}${NC}"
}

STATUS_DIR="/tmp/mview_status"
mkdir -p "$STATUS_DIR"

write_status() {
    local name="$1" status="$2" duration="$3" total="$4" failed="$5" failed_views="$6" error_msg="$7"
    cat > "$STATUS_DIR/${name}.json" <<EOF
{"group":"$name","status":"$status","timestamp":"$(date -u '+%Y-%m-%dT%H:%M:%SZ')","duration_seconds":$duration,"views_total":$total,"views_failed":$failed,"failed_views":"$failed_views","error":"$error_msg"}
EOF
}

execute_sql_file() {
    local file="$1"
    log_message "${YELLOW}⚙️  Executing: $file"

    local start_time=$SECONDS
    if psql "$PG_CONNECTION" -f "$file"; then
        local elapsed=$((SECONDS - start_time))
        log_message "${GREEN}✅ Successfully executed: $file (Time: ${elapsed}s)"
    else
        local elapsed=$((SECONDS - start_time))
        log_message "${RED}❌ ERROR executing: $file (Time: ${elapsed}s)"
    fi
}
