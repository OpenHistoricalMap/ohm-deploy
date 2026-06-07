#!/bin/bash
# Shared configuration. Sourced by start.sh and process_min_range.sh.
export WORKDIR=${WORKDIR:-/data}

# Binaries: osmx (C++) for expand/update/query, osmx-rs (Rust) for augmented diffs.
export OSMX_BIN=${OSMX_BIN:-osmx}
export OSMX_RS_BIN=${OSMX_RS_BIN:-osmx-rs}

# Database
export OSMX_DB_DIR=$WORKDIR/db
export OSMX_DB_PATH=$OSMX_DB_DIR/osmx.db
export PLANET_FILE_PATH=$WORKDIR/planet.osm.pbf

# Services
export REPLICATION_URL="${REPLICATION_URL:-https://s3.amazonaws.com/planet.openhistoricalmap.org/replication/minute}"
export API_URL=${API_URL:-https://api.openstreetmap.org}

# Working directories
export SPLIT_ADIFFS_DIR=$WORKDIR/stage-data/split-adiffs   # per-changeset fragments
export CHANGESET_DIR=$WORKDIR/stage-data/changesets        # merge.mk stamp files
export BUCKET_DIR=$WORKDIR/stage-data/bucket-data          # merged adiffs ready to upload
export BAD_CHANGESETS_DIR=$WORKDIR/stage-data/bad_changesets

# Upload target: s3://$AWS_S3_BUCKET/$S3_PREFIX/<changeset>.adiff
export S3_PREFIX=${S3_PREFIX:-ohm-augmented-diffs/changesets}

# Seqno to start from when building the database from scratch
export OSMX_INITIAL_SEQNUM=${OSMX_INITIAL_SEQNUM:-0}

# Liveness (watchdog in start.sh + healthcheck.sh)
export HEARTBEAT_DIR=${HEARTBEAT_DIR:-/tmp/heartbeat}
export HEARTBEAT_STALE_SECONDS=${HEARTBEAT_STALE_SECONDS:-600}

# Kill one update.sh run if it exceeds this (must be < HEARTBEAT_STALE_SECONDS)
export UPDATE_TIMEOUT=${UPDATE_TIMEOUT:-540}
