#!/usr/bin/env bash

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

echo "All good: imposm and DB are healthy."
exit 0
