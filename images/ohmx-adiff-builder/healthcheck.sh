#!/bin/bash
# Healthcheck para ohmx-adiff:
#   - Verifica que existan heartbeats para create_diff_files, process_diff_files y upload_diff_files
#   - Si alguno es mas viejo que STALE_SECONDS, el contenedor se marca unhealthy
# El watchdog dentro de start.sh es quien fuerza la salida y dispara el restart.

HEARTBEAT_DIR=${HEARTBEAT_DIR:-/tmp/heartbeat}
STALE_SECONDS=${HEARTBEAT_STALE_SECONDS:-600}

if [ ! -d "$HEARTBEAT_DIR" ]; then
  echo "unhealthy: no existe $HEARTBEAT_DIR"
  exit 1
fi

now=$(date +%s)
for name in create_diff_files process_diff_files upload_diff_files; do
  hb="$HEARTBEAT_DIR/$name"
  if [ ! -f "$hb" ]; then
    echo "unhealthy: no hay heartbeat para $name"
    exit 1
  fi
  mtime=$(stat -c %Y "$hb")
  age=$(( now - mtime ))
  if [ "$age" -gt "$STALE_SECONDS" ]; then
    echo "unhealthy: heartbeat $name viejo (${age}s > ${STALE_SECONDS}s)"
    exit 1
  fi
done

echo "ok"
exit 0
