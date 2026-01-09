#!/bin/bash
set -e

source ./scripts/utils.sh

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

# Function to monitor imposm process and handle connection errors
# Parameters:
#   $1: IMPOSM_PID - Process ID of the imposm process
#   $2: UPLOADER_PID - Process ID of the uploader background process
function monitorImposmErrors() {
    local IMPOSM_PID=$1
    local UPLOADER_PID=$2
    local ERROR_COUNT=0
    local MAX_ERRORS=3
    local LOG_FILE="/tmp/imposm.log"
    
    while true; do
        log_message "Checking minute replication import into the database"
        
        # Check for connection errors specifically
        if grep -q "driver: bad connection" "$LOG_FILE" || grep -q "\[error\] Importing.*bad connection" "$LOG_FILE"; then
            ERROR_COUNT=$((ERROR_COUNT + 1))
            log_message "Detected bad connection error (count: $ERROR_COUNT/$MAX_ERRORS). Waiting before retry..."
            
            # Check if imposm process is still running
            if ! kill -0 $IMPOSM_PID 2>/dev/null; then
                log_message "Imposm process has died. Restarting container..."
                kill $UPLOADER_PID 2>/dev/null
                exit 1
            fi
            
            # If we've hit max errors, restart
            if [ $ERROR_COUNT -ge $MAX_ERRORS ]; then
                log_message "Max connection errors reached ($MAX_ERRORS). Restarting container..."
                kill $UPLOADER_PID 2>/dev/null
                kill $IMPOSM_PID 2>/dev/null
                exit 1
            fi
            
            # Wait a bit and check if connection recovers
            sleep 30
            # Clear the error from log to avoid immediate re-trigger
            sed -i '/driver: bad connection/d' "$LOG_FILE" 2>/dev/null || true
        elif grep -q "\[error\] Importing" "$LOG_FILE"; then
            # Other import errors - log but don't immediately restart
            log_message "Detected [error] Importing in Imposm log. Monitoring..."
            ERROR_COUNT=$((ERROR_COUNT + 1))
            
            if [ $ERROR_COUNT -ge $MAX_ERRORS ]; then
                log_message "Max errors reached ($MAX_ERRORS). Restarting container..."
                kill $UPLOADER_PID 2>/dev/null
                kill $IMPOSM_PID 2>/dev/null
                exit 1
            fi
        else
            # Reset error count if no errors found
            if [ $ERROR_COUNT -gt 0 ]; then
                log_message "No errors detected. Resetting error count."
                ERROR_COUNT=0
            fi
        fi
        
        sleep 10
    done
}

function updateData() {
    log_message "Starting database update process..."

    # Step 1: Refreshing materialized views
    if [ "$REFRESH_MVIEWS" = "true" ]; then
        log_message "Refreshing materialized views..."
        ./scripts/refresh_mviews.sh &
    else
        log_message "Skipping materialized views refresh (REFRESH_MVIEWS=$REFRESH_MVIEWS)"
    fi

    local local_last_state_path="$DIFF_DIR/last.state.txt"

    # Step 2: Handle last.state.txt if OVERWRITE_STATE is enabled
    if [ "$OVERWRITE_STATE" = "true" ]; then
    log_message "Overwriting last.state.txt..."
    timestamp=$(date -u +"%Y-%m-%dT%H\\:%M\\:%SZ")
    cat <<EOF > "$local_last_state_path"
timestamp=${timestamp}
sequenceNumber=${SEQUENCE_NUMBER:-0}
replicationUrl=${REPLICATION_URL}
EOF
    fi

    # Step 3: Start uploader in background and store its PID
    log_message "Starting background upload process..."
    (
        while true; do
            log_message "Uploading expired files..."
            uploadExpiredFiles

            log_message "Uploading last.state.txt..."
            uploadLastState

            sleep 30s
        done
    ) &
    UPLOADER_PID=$!

    # Step 4: Run Imposm update process
    log_message "Running Imposm update process..."
    # Note: The Go pq driver used by imposm doesn't support keepalive parameters
    # in connection URLs or via environment variables. We rely on:
    # 1. connect_timeout in the connection string (already set)
    # 2. The monitorImposmErrors function to handle connection errors gracefully
    # 3. System-level TCP keepalive settings (if configured)

    imposm run \
        -config "${WORKDIR}/config.json" \
        -cachedir "${CACHE_DIR}" \
        -diffdir "${DIFF_DIR}" \
        -expiretiles-dir "${IMPOSM3_EXPIRE_DIR}" \
        -quiet 2>&1 | tee /tmp/imposm.log &
    IMPOSM_PID=$!

    # Step 5: Monitor imposm process and handle errors
    monitorImposmErrors $IMPOSM_PID $UPLOADER_PID
}

function importData() {
    ### Import the PBF  and Natural Earth files to the DB
    execute_sql_file ./queries/utils/postgis_helpers.sql

    if [ "$IMPORT_NATURAL_EARTH" = "true" ]; then
        log_message "Importing Natural Earth..."
        ./scripts/natural_earth.sh
    fi

    if [ "$IMPORT_OSM_LAND" = "true" ]; then
        log_message "Import OSM Land..."
        ./scripts/osm_land.sh
    fi
    
    log_message "Import PBF file..."

    imposm import \
        -config $WORKDIR/config.json \
        -read $PBFFILE \
        -write \
        -diff \
        -cachedir $CACHE_DIR \
        -overwritecache \
        -diffdir $DIFF_DIR \
        -optimize 


    imposm import \
        -config $WORKDIR/config.json \
        -deployproduction

    # Create materialized views
    ./scripts/create_mviews.sh --all=true

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
execute_sql_file /usr/local/datefunctions/datefunctions.sql

# Check the number of tables in the database
table_count=$(countTables)

## Start the main process
# Check if the INIT_FILE exists or if the table count is greater than 30
if [[ -f "$INIT_FILE" || "$table_count" -gt 30 ]]; then
    updateData
else
    getData
    importData
    updateData
fi
