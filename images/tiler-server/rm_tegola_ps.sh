#!/bin/bash
set -e
if [[ -n "${KILL_PROCESS}" && "${KILL_PROCESS}" == "manually" ]]; then
    while true; do
        NUM_PS=$(ps | grep ${PROCESS_NAME} | grep -v grep | wc -l)
        if [[ $NUM_PS -gt $MAX_NUM_PS ]]; then
            echo "${PROCESS_NAME} processes"
            ps aux | grep ${PROCESS_NAME} | grep -v grep
            # After clearing the S3 cache, terminate all 'tegola' processes.
            killall ${PROCESS_NAME}
            # Clean cache manually from s3
            aws s3 rm s3://${TILER_CACHE_BUCKET}/mnt/data/osm/ --recursive
        fi
        sleep 600
    done
fi
