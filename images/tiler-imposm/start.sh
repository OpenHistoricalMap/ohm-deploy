#!/bin/bash
set -e

# Directories to store imposm's cache for updating the DB
WORKDIR=/mnt/data
CACHE_DIR=$WORKDIR/cachedir
DIFF_DIR=$WORKDIR/diff
IMPOSM3_EXPIRE_DIR=$WORKDIR/imposm3_expire_dir

PBFFILE="${WORKDIR}/osm.pbf"
STATEFILE="state.txt"
LIMITFILE="limitFile.geojson"

# Folder to store the imposm expirer files in S3 or GCS
BUCKET_IMPOSM_FOLDER=imposm
INIT_FILE="$WORKDIR/init_done"

PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

mkdir -p "$CACHE_DIR" "$DIFF_DIR" "$IMPOSM3_EXPIRE_DIR"

# Tracking file for uploaded files
TRACKING_FILE="$WORKDIR/uploaded_files.log"
[ -f "$TRACKING_FILE" ] || touch "$TRACKING_FILE"

# Create config map for imposm
python build_imposm3_config.py

# Create config file for imposm
cat <<EOF >"$WORKDIR/config.json"
{
    "cachedir": "$CACHE_DIR",
    "diffdir": "$DIFF_DIR",
    "connection": "postgis://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB",
    "mapping": "/osm/config/imposm3.json",
    "replication_url": "$REPLICATION_URL"
}
EOF

function log_message() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1"
}

# Function to download the PBF file
function getData() {
    if [[ "$TILER_IMPORT_FROM" == "osm" && ! -f "$PBFFILE" ]]; then
        log_message "Downloading PBF file..."
        wget "$TILER_IMPORT_PBF_URL" -O "$PBFFILE"
    fi
}

# Function to get the modification date of a file
getFormattedDate() {
    local file_path="$1"
    if command -v stat >/dev/null 2>&1; then
        local modification_date=$(stat -c %Y "$file_path")
        if [ $? -eq 0 ]; then
            local formatted_date=$(date -d "@$modification_date" "+%Y-%m-%d:%H:%M:%S")
            log_message "Created/Updated date of $file_path: $formatted_date"
        else
            log_message "Error: Unable to get file modification date for file ${file_path}"
        fi
    else
        log_message "Error: 'stat' command not found. Unable to get file modification date, for file ${file_path}"
    fi
}

# Function to upload expired files
function uploadExpiredFiles() {
    log_message "Checking for expired files to upload..."

    # Upload the expired files to the cloud provider
    for file in $(find "$IMPOSM3_EXPIRE_DIR" -type f -cmin -1); do
        bucketFile=${file#*"$WORKDIR"}
        getFormattedDate "$file"

        # Check if the file has already been uploaded
        if grep -Fxq "$file" "$TRACKING_FILE"; then
            log_message "File ${file} has already been uploaded. Skipping..."
            continue
        fi

        # UPLOAD_EXPIRED_FILES=true to upload the expired files to cloud provider
        if [ "$UPLOAD_EXPIRED_FILES" == "true" ]; then
            log_message "Uploading expired file ${file} to ${AWS_S3_BUCKET}..."
            upload_success=false

            # AWS
            if [ "$CLOUDPROVIDER" == "aws" ]; then
                aws s3 cp "$file" "${AWS_S3_BUCKET}/${BUCKET_IMPOSM_FOLDER}${bucketFile}" --acl public-read && upload_success=true
            fi

            # Google Storage
            if [ "$CLOUDPROVIDER" == "gcp" ]; then
                gsutil cp -a public-read "$file" "${GCP_STORAGE_BUCKET}${BUCKET_IMPOSM_FOLDER}${bucketFile}" && upload_success=true
            fi

            if [ "$upload_success" = true ]; then
                log_message "$file" >> "$TRACKING_FILE"
                log_message "File ${file} uploaded successfully and recorded."
            else
                log_message "Failed to upload file ${file}. Will retry in the next run."
            fi
        else
            log_message "Expired files were not uploaded because UPLOAD_EXPIRED_FILES=${UPLOAD_EXPIRED_FILES}"
        fi
    done
}

# Function to upload last state file
function uploadLastState() {
    # Path to the last.state.txt file
    local state_file="$DIFF_DIR/last.state.txt"
    local s3_path="${AWS_S3_BUCKET}/${BUCKET_IMPOSM_FOLDER}/last.state.txt"
    local checksum_file="$DIFF_DIR/last.state.md5"

    # Check if the last.state.txt file exists
    if [ ! -f "$state_file" ]; then
        log_message "No last.state.txt file found at $state_file. Skipping upload."
        return
    fi

    # Calculate the current checksum of the file
    local current_checksum=$(md5sum "$state_file" | awk '{ print $1 }')

    # Compare with the previous checksum
    if [ -f "$checksum_file" ]; then
        local previous_checksum=$(cat "$checksum_file")
        if [ "$current_checksum" == "$previous_checksum" ]; then
            log_message "No changes in last.state.txt. Skipping upload."
            return
        fi
    fi

    # Attempt to upload the file to S3
    log_message "Uploading $state_file to S3 at $s3_path..."
    if aws s3 cp "$state_file" "${s3_path}" --acl private; then
        # Update the checksum file after a successful upload
        log_message "$current_checksum" > "$checksum_file"
        log_message "Successfully uploaded $state_file to S3."
    fi
}

function updateData() {
    log_message "Starting database update process..."

    # Step 1: Refreshing materialized views
    if [ "$REFRESH_MVIEWS" = "true" ]; then
        log_message "Refreshing materialized views..."
        ./refresh_mviews.sh &
    else
        log_message "Skipping materialized views refresh (REFRESH_MVIEWS=$REFRESH_MVIEWS)"
    fi

    local local_last_state_path="$DIFF_DIR/last.state.txt"

    # Step 2: Handle last.state.txt if OVERWRITE_STATE is enabled
    if [ "$OVERWRITE_STATE" = "true" ]; then
        log_message "Overwriting last.state.txt..."
        cat <<EOF > "$local_last_state_path"
timestamp=0001-01-01T00:00:00Z
sequenceNumber=${SEQUENCE_NUMBER:-0}
replicationUrl=${REPLICATION_URL}
EOF
    fi

    # Step 3: Run the Imposm update process
    log_message "Running Imposm update process..."
    if [ -z "$TILER_IMPORT_LIMIT" ]; then
        imposm run \
            -config "${WORKDIR}/config.json" \
            -cachedir "${CACHE_DIR}" \
            -diffdir "${DIFF_DIR}" \
            -expiretiles-dir "${IMPOSM3_EXPIRE_DIR}" \
            -quiet &
    else
        imposm run \
            -config "${WORKDIR}/config.json" \
            -cachedir "${CACHE_DIR}" \
            -diffdir "${DIFF_DIR}" \
            -limitto "${WORKDIR}/${LIMITFILE}" \
            -expiretiles-dir "${IMPOSM3_EXPIRE_DIR}" \
            -quiet &
    fi

    # Step 4: Continuously upload expired files and last state file to the cloud provider
    log_message "Starting background upload process..."
    while true; do
        log_message "Uploading expired files..."
        uploadExpiredFiles

        log_message "Uploading last.state.txt..."
        uploadLastState

        sleep 30s
    done
}

function importData() {
    ### Import the PBF  and Natural Earth files to the DB
    log_message "Execute the missing functions"
    psql $PG_CONNECTION -f queries/postgis_helpers.sql

    if [ "$IMPORT_NATURAL_EARTH" = "true" ]; then
        log_message "Importing Natural Earth..."
        ./scripts/natural_earth.sh
    fi

    if [ "$IMPORT_OSM_LAND" = "true" ]; then
        log_message "Import OSM Land..."
        ./scripts/osm_land.sh
    fi
    
    log_message "Import PBF file..."
    if [ -z "$TILER_IMPORT_LIMIT" ]; then
        imposm import \
            -config $WORKDIR/config.json \
            -read $PBFFILE \
            -write \
            -diff -cachedir $CACHE_DIR -overwritecache -diffdir $DIFF_DIR
    else
        wget $TILER_IMPORT_LIMIT -O $WORKDIR/$LIMITFILE
        imposm import \
            -config $WORKDIR/config.json \
            -read $PBFFILE \
            -write \
            -diff -cachedir $CACHE_DIR -overwritecache -diffdir $DIFF_DIR \
            -limitto $WORKDIR/$LIMITFILE
    fi

    imposm import \
        -config $WORKDIR/config.json \
        -deployproduction

    log_message "Creating material views and indexes..."
    psql $PG_CONNECTION -f queries/date_utils.sql
    psql $PG_CONNECTION -f queries/mviews_land.sql 
    psql $PG_CONNECTION -f queries/mviews_ne_lakes.sql 
    psql $PG_CONNECTION -f queries/mviews_admin_boundaries_centroids.sql 
    psql $PG_CONNECTION -f queries/mviews_admin_boundaries_merged.sql 
    psql $PG_CONNECTION -f queries/mviews_transport_lines.sql 
    psql $PG_CONNECTION -f queries/mviews_water_areas.sql 
    psql $PG_CONNECTION -f queries/mviews_water_areas_centroids.sql 
    psql $PG_CONNECTION -f queries/mviews_landuse_areas.sql 
    psql $PG_CONNECTION -f queries/mviews_landuse_areas_centroids.sql 
    psql $PG_CONNECTION -f queries/mviews_other_areas.sql 
    psql $PG_CONNECTION -f queries/mviews_other_areas_centroids.sql 
    psql $PG_CONNECTION -f queries/mviews_buildings_points_centroids.sql 
    psql $PG_CONNECTION -f queries/mviews_landuse_points_centroids.sql 
    # Create INIT_FILE to prevent re-importing
    touch $INIT_FILE
}


function countTables() {
    psql $PG_CONNECTION -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | xargs
}


# Wait for PostgreSQL to be ready
log_message "Waiting for PostgreSQL to be ready..."
until pg_isready -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" >/dev/null 2>&1; do
    log_message "PostgreSQL is not ready. Retrying in 2 seconds..."
    sleep 2
done

log_message "PostgreSQL is ready! Proceeding with setup..."

# Run date functions
psql "$PG_CONNECTION" -f /usr/local/datefunctions/datefunctions.sql

# Check the number of tables in the database
table_count=$(countTables)

# Check if the INIT_FILE exists or if the table count is greater than 30
if [[ -f "$INIT_FILE" || "$table_count" -gt 30 ]]; then
    updateData
else
    getData
    importData
    updateData
fi
