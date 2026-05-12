#!/bin/bash
# Healthcheck for ohmx-adiff:
#   - Verifies that heartbeats exist for create_diff_files, process_diff_files and upload_diff_files
#   - If any is older than STALE_SECONDS, the container is marked unhealthy
# The watchdog inside start.sh is what forces the exit and triggers the restart.

HEARTBEAT_DIR=${HEARTBEAT_DIR:-/tmp/heartbeat}
STALE_SECONDS=${HEARTBEAT_STALE_SECONDS:-600}

if [ ! -d "$HEARTBEAT_DIR" ]; then
  echo "unhealthy: $HEARTBEAT_DIR does not exist"
  exit 1
fi

now=$(date +%s)
for name in create_diff_files process_diff_files upload_diff_files; do
  hb="$HEARTBEAT_DIR/$name"
  if [ ! -f "$hb" ]; then
    echo "unhealthy: no heartbeat for $name"
    exit 1
  fi
  mtime=$(stat -c %Y "$hb")
  age=$(( now - mtime ))
  if [ "$age" -gt "$STALE_SECONDS" ]; then
    echo "unhealthy: heartbeat $name stale (${age}s > ${STALE_SECONDS}s)"
    exit 1
  fi
done

echo "ok"
exit 0
