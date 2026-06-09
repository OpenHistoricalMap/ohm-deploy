#!/bin/bash
# Runs the pipeline as two loops plus a watchdog:
#   make_diffs : update.sh turns replication files into per-changeset adiffs
#   publish    : merge fragments -> upload to S3 -> garbage-collect
#   watchdog   : if a loop stalls, exit so docker restarts the container
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh

mkdir -p "$OSMX_DB_DIR" "$SPLIT_ADIFFS_DIR" "$CHANGESET_DIR" \
         "$BUCKET_DIR" "$BAD_CHANGESETS_DIR" "$HEARTBEAT_DIR"
beat() { touch "$HEARTBEAT_DIR/$1"; }

# Tag every line from a loop with "time [component]" so the parallel loops
# (make_diffs, publish, watchdog) stay readable in the combined log and can be
# grepped apart, e.g. `kubectl logs ... | grep '\[merge\]'`.
log_prefix() {
  local tag="$1"
  while IFS= read -r line; do
    printf '%s [%-10s] %s\n' "$(date '+%F %T')" "$tag" "$line"
  done
}

create_database() {
  [ -f "$OSMX_DB_PATH" ] && { echo "Database already exists."; return; }
  if [ ! -f "$PLANET_FILE_PATH" ]; then
    [ -n "${PLANET_PBF_URL:-}" ] || { echo "ERROR: no planet file and PLANET_PBF_URL unset"; exit 1; }
    wget -O "$PLANET_FILE_PATH" "$PLANET_PBF_URL"
  fi
  "$OSMX_BIN" expand "$PLANET_FILE_PATH" "$OSMX_DB_PATH"

  # osmx expand copies osmosis_replication_sequence_number from the PBF header into
  # the db (OSMExpress src/expand.cpp), so the db already knows its position.
  # planet-dump writes that seqno into the header, so there is nothing else to seed:
  # update.sh resumes from `osmx query seqnum`.
  local seqnum
  seqnum=$("$OSMX_BIN" query "$OSMX_DB_PATH" seqnum 2>/dev/null || true)
  if [ -z "$seqnum" ] || [ "$seqnum" = "0" ]; then
    echo "FATAL: planet has no replication sequence number in its header." >&2
    echo "Regenerate the planet with planet-dump so the header carries the seqno." >&2
    exit 1
  fi
  echo "Database ready at seqnum=$seqnum (from planet header)"
}

make_diffs() {
  while true; do
    beat make_diffs
    # timeout caps a run below the watchdog limit, so a stalled replication stream
    # gets killed and retried instead of wedging the loop. The db is transactional,
    # so the next run just resumes from the last committed seqno.
    timeout "$UPDATE_TIMEOUT" ./update.sh || echo "update.sh failed/timed out, retrying"
    sleep 60
  done
}

publish() {
  while true; do
    beat publish
    echo "STEP merge: building changeset-aligned adiffs from split fragments"
    make -f merge.mk SPLIT_ADIFFS_DIR="$SPLIT_ADIFFS_DIR" CHANGESET_DIR="$CHANGESET_DIR" \
                     BUCKET_DIR="$BUCKET_DIR" API_URL="$API_URL" || echo "merge failed"
    echo "STEP upload: pushing merged adiffs to s3"
    upload_changesets
    echo "STEP gc: removing changesets older than the retention window"
    ./gc.sh "$SPLIT_ADIFFS_DIR" "$CHANGESET_DIR"
    echo "STEP idle: sleeping 60s"
    sleep 60
  done
}

# Upload each merged adiff; delete it locally only after S3 confirms, so a failed
# upload is simply retried next pass and never lost.
upload_changesets() {
  [ -n "${AWS_S3_BUCKET:-}" ] || { echo "AWS_S3_BUCKET unset, skipping upload"; return; }
  find "$BUCKET_DIR" -type f -name '*.adiff' | while read -r f; do
    aws s3 cp "$f" "s3://$AWS_S3_BUCKET/$S3_PREFIX/$(basename "$f")" \
      --content-type application/xml --content-encoding gzip && rm -f "$f"
  done
}

watchdog() {
  while sleep 60; do
    now=$(date +%s)
    for name in make_diffs publish; do
      hb="$HEARTBEAT_DIR/$name"; [ -f "$hb" ] || continue
      if [ $(( now - $(stat -c %Y "$hb") )) -gt "$HEARTBEAT_STALE_SECONDS" ]; then
        echo "FATAL: '$name' stalled, exiting for restart" >&2; kill 0
      fi
    done
  done
}

create_database
make_diffs 2>&1 | log_prefix create  &
publish    2>&1 | log_prefix merge   &
watchdog   2>&1 | log_prefix watchdog &
wait -n
echo "FATAL: a loop exited, exiting for restart" >&2
kill 0
