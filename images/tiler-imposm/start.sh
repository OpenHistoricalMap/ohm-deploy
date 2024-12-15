#!/bin/bash
set -e

# directories to keep the imposm's cache for updating the db
WORKDIR=/mnt/data
CACHE_DIR=$WORKDIR/cachedir
DIFF_DIR=$WORKDIR/diff
IMPOSM3_EXPIRE_DIR=$WORKDIR/imposm3_expire_dir

PBFFILE="${WORKDIR}/osm.pbf"
STATEFILE="state.txt"
LIMITFILE="limitFile.geojson"

# Folder to store the imposm expider files in s3 or gs
BUCKET_IMPOSM_FOLDER=imposm
INIT_FILE=/mnt/data/init_done

PG_CONNECTION="postgresql://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

mkdir -p "$CACHE_DIR" "$DIFF_DIR" "$IMPOSM3_EXPIRE_DIR"

# tracking file
TRACKING_FILE="$WORKDIR/uploaded_files.log" 
[ -f "$TRACKING_FILE" ] || touch "$TRACKING_FILE"


# Create config map for imposm
python build_imposm3_config.py

# Create config file to set variables for imposm
{
    echo "{"
    echo "\"cachedir\": \"$CACHE_DIR\","
    echo "\"diffdir\": \"$DIFF_DIR\","
    echo "\"connection\": \"postgis://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB\","
    echo "\"mapping\": \"/osm/config/imposm3.json\","
    echo "\"replication_url\": \"$REPLICATION_URL\""
    echo "}"
} >"$WORKDIR/config.json"

function getData() {
    ### Get the PBF file from the cloud provider or public URL
    if [ "$TILER_IMPORT_FROM" == "osm" ]; then
        if [ ! -f "$PBFFILE" ]; then
          echo "$PBFFILE does not exist, downloading..."
          wget "$TILER_IMPORT_PBF_URL" -O "$PBFFILE"
        fi
    fi
}

getFormattedDate() {
    local file_path="$1"
    if command -v stat >/dev/null 2>&1; then
        local modification_date=$(stat -c %Y "$file_path")
        if [ $? -eq 0 ]; then
            local formatted_date=$(date -d "@$modification_date" "+%Y-%m-%d:%H:%M:%S")
            echo "Created/Updated date of $file_path: $formatted_date"
        else
            echo "Error: Unable to get file modification date for file ${file_path}"
        fi
    else
        echo "Error: 'stat' command not found. Unable to get file modification date, for file ${file_path}"
    fi
}

function uploadExpiredFiles() {
    echo "Checking for expired files to upload... $(date +%F_%H-%M-%S)"

    # Upload the expired files to the cloud provider
    for file in $(find "$IMPOSM3_EXPIRE_DIR" -type f -cmin -1); do
        bucketFile=${file#*"$WORKDIR"}
        getFormattedDate "$file"

        # Check if the file has already been uploaded
        if grep -Fxq "$file" "$TRACKING_FILE"; then
            echo "File ${file} has already been uploaded. Skipping..."
            continue
        fi

        # UPLOAD_EXPIRED_FILES=true to upload the expired files to cloud provider
        if [ "$UPLOAD_EXPIRED_FILES" == "true" ]; then
            echo "Uploading expired file ${file} to ${AWS_S3_BUCKET}..."

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
                echo "$file" >> "$TRACKING_FILE"
                echo "File ${file} uploaded successfully and recorded."
            else
                echo "Failed to upload file ${file}. Will retry in the next run."
            fi
        else
            echo "Expired files were not uploaded because UPLOAD_EXPIRED_FILES=${UPLOAD_EXPIRED_FILES}"
        fi
    done
}

function updateData() {
    ### Update the DB with the new data form minute replication
    if [ "$OVERWRITE_STATE" = "true" ]; then
        rm -f $DIFF_DIR/last.state.txt
    fi

    # Check if last.state.txt exists
    if [ -f "$DIFF_DIR/last.state.txt" ]; then
        echo "Exist... $DIFF_DIR/last.state.txt"
    else
        # Create last.state.txt file with REPLICATION_URL and SEQUENCE_NUMBER from env vars
        echo "timestamp=0001-01-01T00\:00\:00Z 
        sequenceNumber=$SEQUENCE_NUMBER
        replicationUrl=$REPLICATION_URL" >$DIFF_DIR/last.state.txt
    fi

    # Check if the limit file exists
    if [ -z "$TILER_IMPORT_LIMIT" ]; then
        imposm run -config "$WORKDIR/config.json" -expiretiles-dir "$IMPOSM3_EXPIRE_DIR" -httpprofile ":6060" &
    else
        imposm run -config "$WORKDIR/config.json" -limitto "$WORKDIR/$LIMITFILE" -expiretiles-dir "$IMPOSM3_EXPIRE_DIR" &
    fi

    while true; do
        echo "Upload expired files... $(date +%F_%H-%M-%S)"
        uploadExpiredFiles
        sleep 1m
    done
}

function importData() {
    ### Import the PBF  and Natural Earth files to the DB
    echo "Execute the missing functions"
    psql $PG_CONNECTION -f queries/postgis_helpers.sql

    if [ "$IMPORT_NATURAL_EARTH" = "true" ]; then
        echo "Importing Natural Earth..."
        ./scripts/natural_earth.sh
    fi

    if [ "$IMPORT_OSM_LAND" = "true" ]; then
        echo "Import OSM Land..."
        ./scripts/osm_land.sh
    fi
    
    echo "Import PBF file..."
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

    # These index will help speed up tegola tile generation
    # psql $PG_CONNECTION -f queries/postgis_index.sql
    psql $PG_CONNECTION -f queries/postgis_post_import.sql

    touch $INIT_FILE

    # Update tables
    python update_tables.py
    
    echo "Create Table/Tigger for osm_relation_menbers_routes_merged"
    # psql $PG_CONNECTION -f queries/osm_relation_menbers_routes_table.sql
    # psql $PG_CONNECTION -f queries/osm_relation_menbers_routes_trigger.sql
    psql $PG_CONNECTION -f queries/admin_boundaries_centroids.sql

    # Updata data with minute replication
    updateData
}

function countTables() {
    psql $PG_CONNECTION -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" | xargs
}

echo "Connecting to $POSTGRES_HOST DB"
flag=true
while $flag; do
    pg_isready -h $POSTGRES_HOST -p $POSTGRES_PORT >/dev/null 2>&2 || continue
    # Change flag to false to stop pinging the DB
    flag=false
    echo "Run date functions"
    psql $PG_CONNECTION -f /usr/local/datefunctions/datefunctions.sql
    echo "Check number of tables in the database"
    table_count=$(countTables)
    echo "Check if $INIT_FILE exists"
    if [[ -f $INIT_FILE || "$table_count" -gt 30 ]]; then
        updateData
    else
        echo "Import PBF data to DB"
        getData
        if [ -f $PBFFILE ]; then
            echo "Start importing the data"
            importData
        fi
    fi
done
