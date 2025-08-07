#!/bin/bash
# set -e

WORKDIR=/data

## Database path
OSMX_DB_PATH=$WORKDIR/db/osmx.db
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

## Sequence number
OSMX_INITIAL_SEQNUM=${OSMX_INITIAL_SEQNUM:-0}

## Process diff files from the last 60 min
FILTER_ADIFF_FILES=60

mkdir -p $REPLICATION_ADIFFS_DIR $SPLIT_ADIFFS_DIR $CHANGESET_DIR $BUCKET_DIR

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
    ./update.sh $OSMX_DB_PATH $REPLICATION_ADIFFS_DIR $OSMX_INITIAL_SEQNUM
    ## Start generating files with no initial sequence number
    create_diff_files

  else
    echo "Database already exists. Skipping creation."
  fi
}


create_diff_files() {
  while true; do
    echo "Running update.sh at $(date)..."
    ./update.sh "$OSMX_DB_PATH" "$REPLICATION_ADIFFS_DIR"
    sleep 60
  done
}

process_diff_files() {
  while true; do
    echo "Processing diff files at $(date)..."
    ./process.sh \
      "$REPLICATION_ADIFFS_DIR" \
      "$SPLIT_ADIFFS_DIR" \
      "$CHANGESET_DIR" \
      "$BUCKET_DIR" \
      "$API_URL" \
      "$FILTER_ADIFF_FILES"
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
    echo "Uploading files at $(date)..."
    find "$BUCKET_DIR" -type f -name '*.adiff' -mmin -60 | while read -r filepath; do
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

      aws s3 cp "$filepath" "s3://$AWS_S3_BUCKET/osm-augmented-diffs/$filename" \
        --content-type "application/xml" \
        --content-encoding "gzip"

      uploaded_md5s["$filename"]="$current_md5"
    done

    # Actualiza archivo de control
    : > "$UPLOAD_TRACK_FILE"
    for fname in "${!uploaded_md5s[@]}"; do
      echo "$fname ${uploaded_md5s[$fname]}" >> "$UPLOAD_TRACK_FILE"
    done

    sleep 15
  done
}

## Start process diff files
create_database
create_diff_files &
process_diff_files &
upload_diff_files
