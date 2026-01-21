#!/bin/bash
# Configuration file for ohmx-adiff-builder

export WORKDIR=/data

## Database path
export OSMX_DB_DIR=$WORKDIR/db/
export OSMX_DB_PATH=$OSMX_DB_DIR/osmx.db
export PLANET_FILE_PATH=$WORKDIR/planet.osm.pbf

## URLs services
export REPLICATION_URL="${REPLICATION_URL:-https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute}"
export API_URL=${API_URL:-https://api.openstreetmap.org}

## Required directories (sin barra final para evitar dobles barras)
export REPLICATION_ADIFFS_DIR=$WORKDIR/stage-data/replication-adiffs
export SPLIT_ADIFFS_DIR=$WORKDIR/stage-data/split-adiffs
export CHANGESET_DIR=$WORKDIR/stage-data/changesets
export BUCKET_DIR=$WORKDIR/stage-data/bucket-data
export UPLOAD_TRACK_FILE=$WORKDIR/stage-data/uploaded_files.md5
export BAD_CHANGESETS_DIR=$WORKDIR/stage-data/bad_changesets

## Sequence number
export OSMX_INITIAL_SEQNUM=${OSMX_INITIAL_SEQNUM:-0}

## Process diff files from the last 60 min
export FILTER_ADIFF_FILES=60
