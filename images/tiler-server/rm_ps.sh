#!/bin/bash
set -e

PROCESS_NAME="tegola"
MAX_RUNTIME_SECONDS=300 
SLEEP_INTERVAL=60

calculate_elapsed_seconds() {
    local start_time=$1
    local current_time=$(date +%s)
    echo $((current_time - start_time))
}

if [[ -n "${KILL_PROCESS}" && "${KILL_PROCESS}" == "manually" ]]; then
    while true; do
        for pid in $(pgrep -f ${PROCESS_NAME}); do
            start_time=$(stat -c %Y /proc/$pid)
            elapsed_seconds=$(calculate_elapsed_seconds $start_time)
            if [[ $elapsed_seconds -gt $MAX_RUNTIME_SECONDS ]]; then
                echo "The process ${PROCESS_NAME} with PID $pid has been running for $elapsed_seconds seconds"
                kill -9 $pid
                aws s3 rm s3://${TILER_CACHE_BUCKET}/mnt/data/osm/ --recursive
            fi
        done
        sleep $SLEEP_INTERVAL
    done
fi