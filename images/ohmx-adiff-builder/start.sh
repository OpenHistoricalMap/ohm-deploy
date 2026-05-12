#!/bin/bash
# set -e

WORKDIR=/data

## Database path
OSMX_DB_DIR=$WORKDIR/db/
OSMX_DB_PATH=$OSMX_DB_DIR/osmx.db
PLANET_FILE_PATH=$WORKDIR/planet.osm.pbf

## URLs services
REPLICATION_URL="${REPLICATION_URL:-https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute}"
API_URL=${API_URL:-https://api.openstreetmap.org}

## Reqeuiried directories
REPLICATION_ADIFFS_DIR=$WORKDIR/stage-data/replication-adiffs
SPLIT_ADIFFS_DIR=$WORKDIR/stage-data/split-adiffs
CHANGESET_DIR=$WORKDIR/stage-data/changesets
BUCKET_DIR=$WORKDIR/stage-data/bucket-data
UPLOAD_TRACK_FILE=$WORKDIR/stage-data/uploaded_files.md5
BAD_CHANGESETS_DIR=$WORKDIR/stage-data/bad_changesets

## Liveness — heartbeats que el watchdog y el healthcheck consultan
HEARTBEAT_DIR=${HEARTBEAT_DIR:-/tmp/heartbeat}
HEARTBEAT_STALE_SECONDS=${HEARTBEAT_STALE_SECONDS:-600}

## Sequence number
OSMX_INITIAL_SEQNUM=${OSMX_INITIAL_SEQNUM:-0}

## Process diff files from the last 60 min
FILTER_ADIFF_FILES=60

mkdir -p "$OSMX_DB_DIR" "$REPLICATION_ADIFFS_DIR" "$SPLIT_ADIFFS_DIR" \
         "$CHANGESET_DIR" "$BUCKET_DIR" "$BAD_CHANGESETS_DIR" "$HEARTBEAT_DIR" \
         "$BUCKET_DIR/replication/minute" \
         /app/bucket-data/replication/minute

beat() { touch "$HEARTBEAT_DIR/$1"; }

create_database() {
  if [ ! -f "$OSMX_DB_PATH" ]; then
    # Download the planet file if it doesn't exist and a URL is provided
    if [ ! -f "$PLANET_FILE_PATH" ] && [ -n "$PLANET_PBF_URL" ]; then
      wget -O "$PLANET_FILE_PATH" "$PLANET_PBF_URL"
    elif [ ! -f "$PLANET_FILE_PATH" ]; then
      echo "ERROR: Planet file not found at $PLANET_FILE_PATH and PLANET_PBF_URL is not set."
      exit 1
    fi
    osmx expand "$PLANET_FILE_PATH" "$OSMX_DB_PATH"
    echo "Database created successfully."

    ## Update database with initial sequence number and get adiff files, starts at OSMX_INITIAL_SEQNU
    ./update.sh $OSMX_DB_PATH $REPLICATION_ADIFFS_DIR $BAD_CHANGESETS_DIR $OSMX_INITIAL_SEQNUM
    ## Start generating files with no initial sequence number
    create_diff_files

  else
    echo "Database already exists. Skipping creation."
  fi
}


create_diff_files() {
  while true; do
    beat create_diff_files
    echo "Running update.sh at $(date)..."
    if ! ./update.sh "$OSMX_DB_PATH" "$REPLICATION_ADIFFS_DIR" "$BAD_CHANGESETS_DIR"; then
      echo "update.sh failed at $(date), restarting..."
    else
      echo "update.sh completed successfully at $(date)"
    fi

    sleep 60
  done
}

process_diff_files() {
  while true; do
    beat process_diff_files
    echo "Processing diff files at $(date)..."
    if ! ./process.sh \
      "$REPLICATION_ADIFFS_DIR" \
      "$SPLIT_ADIFFS_DIR" \
      "$CHANGESET_DIR" \
      "$BUCKET_DIR" \
      "$API_URL" \
      "$FILTER_ADIFF_FILES"; then
      echo "process.sh failed at $(date), restarting..."
    else
      echo "process.sh completed successfully at $(date)"
    fi

    sleep 60
  done
}

upload_diff_files() {
  mkdir -p "$(dirname "$UPLOAD_TRACK_FILE")"
  touch "$UPLOAD_TRACK_FILE"

  declare -A uploaded_md5s
  while read -r line; do
    file=$(echo "$line" | awk '{print $1}')
    hash=$(echo "$line" | awk '{print $2}')
    uploaded_md5s["$file"]="$hash"
  done < "$UPLOAD_TRACK_FILE"

  while true; do
    beat upload_diff_files
    echo "Uploading files at $(date)..."
    # NOTA: usamos process substitution (< <(...)) en lugar de "find | while" porque
    # el pipe ejecuta el while en un subshell y las modificaciones al array
    # uploaded_md5s se perderian al salir, causando re-uploads infinitos.
    while read -r filepath; do
      filename=$(basename "$filepath")
      current_md5=$(md5sum "$filepath" | awk '{print $1}')

      if [[ -n "${uploaded_md5s[$filename]}" ]]; then
        if [[ "${uploaded_md5s[$filename]}" == "$current_md5" ]]; then
          echo "Skipping unchanged: $filename"
          continue
        else
          echo "File changed: $filename — reuploading"
        fi
      else
        echo "New file: $filename — uploading"
      fi

      if aws s3 cp "$filepath" "s3://$AWS_S3_BUCKET/ohm-augmented-diffs/changesets/$filename" \
        --content-type "application/xml" \
        --content-encoding "gzip"; then
        uploaded_md5s["$filename"]="$current_md5"
      else
        echo "Upload failed for $filename, will retry next loop"
      fi
    done < <(find "$BUCKET_DIR" -type f -name '*.adiff' -mmin -60)

    # Actualiza archivo de control
    : > "$UPLOAD_TRACK_FILE"
    for fname in "${!uploaded_md5s[@]}"; do
      echo "$fname ${uploaded_md5s[$fname]}" >> "$UPLOAD_TRACK_FILE"
    done

    sleep 15
  done
}

# Watchdog: si alguno de los heartbeats queda viejo, salimos -> docker reinicia
watchdog() {
  while true; do
    sleep 60
    now=$(date +%s)
    for name in create_diff_files process_diff_files upload_diff_files; do
      hb="$HEARTBEAT_DIR/$name"
      [ -f "$hb" ] || continue
      mtime=$(stat -c %Y "$hb")
      age=$(( now - mtime ))
      if [ "$age" -gt "$HEARTBEAT_STALE_SECONDS" ]; then
        echo "[$(date)] FATAL: heartbeat de '$name' viejo (${age}s > ${HEARTBEAT_STALE_SECONDS}s). Saliendo para que docker reinicie el contenedor." >&2
        exit 1
      fi
    done
  done
}

## Start process diff files
create_database

create_diff_files &
CREATE_PID=$!
process_diff_files &
PROCESS_PID=$!
upload_diff_files &
UPLOAD_PID=$!
watchdog &
WATCH_PID=$!

echo "[$(date)] PIDs: create=$CREATE_PID process=$PROCESS_PID upload=$UPLOAD_PID watchdog=$WATCH_PID"

# Si CUALQUIERA de los background muere, salimos con error -> docker restartea
wait -n
EXIT_CODE=$?
echo "[$(date)] FATAL: un proceso background salió (exit=$EXIT_CODE). Matando los demás y saliendo." >&2
kill "$CREATE_PID" "$PROCESS_PID" "$UPLOAD_PID" "$WATCH_PID" 2>/dev/null
exit "$EXIT_CODE"
