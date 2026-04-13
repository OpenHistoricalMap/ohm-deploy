#!/usr/bin/env bash

DIFF_DIR="/mnt/data/diff"
STATE_FILE="$DIFF_DIR/last.state.txt"
MAX_STALE_SECONDS="${MAX_STALE_SECONDS:-3600}" # 1 hour
READY_FILE="/tmp/imposm_ready"
STARTUP_GRACE_SECONDS="${STARTUP_GRACE_SECONDS:-300}" # 5 minutes

# Skip checks if imposm hasn't started yet (still in startup/config phase)
if [ ! -f "$READY_FILE" ]; then
  # Check how long the container has been running
  UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime)
  if [ "$UPTIME_SECONDS" -lt "$STARTUP_GRACE_SECONDS" ]; then
    echo "Imposm still starting up (${UPTIME_SECONDS}s < ${STARTUP_GRACE_SECONDS}s grace). Skipping checks."
    exit 0
  else
    echo "Startup grace period exceeded and imposm never became ready. Exiting..."
    pkill -f start.sh && exit 1
  fi
fi

# 1) Check if imposm is running
if ! pgrep -f imposm >/dev/null; then
  echo "imposm is NOT running. Exiting..."
  pkill -f start.sh && exit 1
fi

# 2) Check DB connection
PGPASSWORD="$POSTGRES_PASSWORD" psql \
  -h "$POSTGRES_HOST" \
  -p "$POSTGRES_PORT" \
  -U "$POSTGRES_USER" \
  -d "$POSTGRES_DB" \
  -c "\q" >/dev/null 2>&1

if [ $? -ne 0 ]; then
  echo "Database connection failed. Exiting..."
  pkill -f start.sh && exit 1
fi

# 3) Check if imposm is actually processing data
# If last.state.txt hasn't been updated in MAX_STALE_SECONDS, imposm is stuck
if [ -f "$STATE_FILE" ]; then
  last_modified=$(stat -c %Y "$STATE_FILE" 2>/dev/null || stat -f %m "$STATE_FILE" 2>/dev/null)
  now=$(date +%s)
  age=$((now - last_modified))
  if [ "$age" -gt "$MAX_STALE_SECONDS" ]; then
    echo "last.state.txt is ${age}s old (max: ${MAX_STALE_SECONDS}s). Imposm appears stuck. Exiting..."
    pkill -f start.sh && exit 1
  fi
fi

# 4) Check for connection errors in imposm log
LOG_FILE="/tmp/imposm.log"
if [ -f "$LOG_FILE" ]; then
  if grep -q "server closed the connection unexpectedly" "$LOG_FILE" || \
     grep -q "driver: bad connection" "$LOG_FILE"; then
    echo "Connection error detected in imposm log. Exiting..."
    pkill -f start.sh && exit 1
  fi
fi

echo "All good: imposm and DB are healthy."
exit 0
