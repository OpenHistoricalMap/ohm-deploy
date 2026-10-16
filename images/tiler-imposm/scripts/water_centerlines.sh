#!/bin/bash
set -e

source ./scripts/utils.sh

# Regenerates water centerlines (#1374) every WATER_CENTERLINES_INTERVAL seconds.
# The Python script is incremental, so runs after the first one only process
# water bodies whose geometry changed.

INTERVAL="${WATER_CENTERLINES_INTERVAL:-604800}"

while true; do
    log_message "${YELLOW}Generating water centerlines..."
    start_time=$SECONDS
    if python3 scripts/water_centerlines.py; then
        elapsed=$((SECONDS - start_time))
        log_message "${GREEN}Water centerlines done (Time: ${elapsed}s)"
        write_status "WATER_CENTERLINES" "success" "$elapsed" 0 0 "" ""
    else
        elapsed=$((SECONDS - start_time))
        log_message "${RED}Water centerlines failed (Time: ${elapsed}s)"
        write_status "WATER_CENTERLINES" "error" "$elapsed" 0 0 "" "water_centerlines.py failed"
    fi
    sleep "$INTERVAL"
done
