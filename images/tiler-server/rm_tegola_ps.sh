#!/bin/bash
set -e
PROCESS_NAME="tegola"
SLEEP_INTERVAL=20
CPU_USAGE_THRESHOLD=70

check_total_cpu_usage() {
    local total_cpu_usage=0
    for cpu in $(ps -eo comm,pcpu | grep ${PROCESS_NAME} | awk '{print $2}'); do
        total_cpu_usage=$(echo "$total_cpu_usage + $cpu" | bc)
    done
    echo $total_cpu_usage
}

while true; do
    total_cpu_usage=$(check_total_cpu_usage)
    total_cpu_usage=${total_cpu_usage%.*}
    echo "Total cpu usage: $total_cpu_usage"
    if [[ $total_cpu_usage -gt $CPU_USAGE_THRESHOLD ]]; then
        echo "Total CPU usage of ${PROCESS_NAME} processes is ${total_cpu_usage}%, which is greater than the threshold of ${CPU_USAGE_THRESHOLD}%."
        
        echo "Terminating all ${PROCESS_NAME} processes..."
        killall -9 ${PROCESS_NAME}

        echo "Manually clearing S3 cache..."
        aws s3 rm s3://${TILER_CACHE_BUCKET}/mnt/data/osm/ --recursive
    fi

    sleep $SLEEP_INTERVAL
done