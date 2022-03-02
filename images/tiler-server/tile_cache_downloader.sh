#!/usr/bin/env bash

workDir=/mnt/data
expire_dir=$workDir/imposm/imposm3_expire_dir
mkdir -p $expire_dir

s3_tiles_expired_log=$workDir/imposm/s3_tiles_expired_from_$(date +'%Y%m%d%H').log

function downloadExpiredTiles() {
    # Get S3 tiles files from the last 1 minute  , eg. -50 min, -4 hour, -4 day
    dateStr="$(date -d '-1 min' +'%Y-%m-%dT%H:%M:%S.000Z')"
    # Store log of request
    echo "Date:${dateStr}" >>$s3_tiles_expired_log
    # echo "Getting expired tiles from... $dateStr"
    if [ "$CLOUDPROVIDER" == "aws" ]; then
        # Download list of latest files according to dateStr
        today=$(date +%Y%m%d)
        (set -x; aws s3api list-objects-v2 \
            --bucket ${AWS_S3_BUCKET#*"s3://"} \
            --prefix imposm/imposm3_expire_dir/$today \
            --query "Contents[?LastModified>'$dateStr']" >$workDir/imposm/tmp_s3_file.json )
        # Filter tiles with extencion .tiles
        cat $workDir/imposm/tmp_s3_file.json |
            jq -c '[ .[] | select( .Key | contains(".tiles")) ]' |
            jq '.[].Key' |
            sed 's/\"//g' >$workDir/imposm/tmp_s3_file.list

        # Download the expired tiles that is needed for cleaning cache
        while IFS= read -r tileFile; do
            (set -x; aws s3 cp ${AWS_S3_BUCKET}/${tileFile} $workDir/${tileFile})
            echo "${AWS_S3_BUCKET}/${tileFile}" >>$s3_tiles_expired_log
        done <$workDir/imposm/tmp_s3_file.list

        # Remove tmp files
        rm $workDir/imposm/tmp_s3_file.json
        rm $workDir/imposm/tmp_s3_file.list
    fi
    # TODO downloader for GS
}

while true; do
    downloadExpiredTiles
    sleep 1m
done
