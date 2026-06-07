#!/bin/bash
# Inspect the current state of the pipeline.
#
# Usage:
#   ./status.sh            overall summary (db sync, lag, file counts, liveness)
#   ./status.sh <changeset_id>   detail for one changeset (split/merged/uploaded)
set -uo pipefail
cd "$(dirname "$0")"
source ./config.sh

count() { find "$1" -mindepth 1 "${@:2}" 2>/dev/null | wc -l | tr -d ' '; }
age()   { [ -f "$1" ] && echo $(( $(date +%s) - $(stat -c %Y "$1") )) || echo "-"; }
mtime() { stat -c %y "$1" 2>/dev/null | cut -d. -f1; }   # "2026-06-05 13:55:20"

# ---------------------------------------------------------------------------
# Per-changeset detail
# ---------------------------------------------------------------------------
if [ "$#" -ge 1 ]; then
  cs="$1"
  echo "Changeset $cs"
  echo "------------------------------------------------------------"

  splitdir="$SPLIT_ADIFFS_DIR/$cs"
  frags=$(ls "$splitdir"/*.adiff 2>/dev/null)
  if [ -n "$frags" ]; then
    seqnos=$(for f in $frags; do basename "$f" .adiff; done | paste -sd, -)
    echo "split fragments : $(echo "$frags" | wc -l | tr -d ' ') seqno(s) -> $seqnos"
  else
    echo "split fragments : none (not seen, or already garbage-collected)"
  fi

  stamp="$CHANGESET_DIR/$cs.adiff.md5"
  if [ -f "$stamp" ]; then
    echo "merged          : yes (merged $(age "$stamp")s ago, md5 $(awk '{print $1}' "$stamp"))"
  else
    echo "merged          : no"
  fi

  bucket="$BUCKET_DIR/$cs.adiff"
  if [ -f "$bucket" ]; then
    echo "upload          : PENDING (in bucket-data, not yet uploaded)"
  else
    echo "upload          : not pending locally (uploaded already, or not merged yet)"
  fi

  if [ -n "${AWS_S3_BUCKET:-}" ] && command -v aws >/dev/null 2>&1; then
    if aws s3 ls "s3://$AWS_S3_BUCKET/$S3_PREFIX/$cs.adiff" >/dev/null 2>&1; then
      echo "on S3           : yes (s3://$AWS_S3_BUCKET/$S3_PREFIX/$cs.adiff)"
    else
      echo "on S3           : NO"
    fi
  else
    echo "on S3           : (set AWS_S3_BUCKET to check)"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Overall summary
# ---------------------------------------------------------------------------
echo "============================================================"
echo " ohmx-adiff-builder status — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

echo ""
echo "Database sync"
echo "------------------------------------------------------------"
if [ -f "$OSMX_DB_PATH" ]; then
  local_seq=$("$OSMX_BIN" query "$OSMX_DB_PATH" seqnum 2>/dev/null | tr -d ' ')
  local_ts=$("$OSMX_BIN" query "$OSMX_DB_PATH" timestamp 2>/dev/null)
  echo "local db seqno   : ${local_seq:-?}   ($local_ts)"

  remote_seq=$(curl -fsSL --max-time 20 "$REPLICATION_URL/state.txt" 2>/dev/null \
                | grep '^sequenceNumber=' | cut -d= -f2 | tr -d ' \r')
  if [ -n "${remote_seq:-}" ] && [ -n "${local_seq:-}" ]; then
    lag=$(( remote_seq - local_seq ))
    echo "latest available : $remote_seq"
    echo "lag              : $lag replication file(s) behind (~$lag min)"
  else
    echo "latest available : (could not fetch $REPLICATION_URL/state.txt)"
  fi
else
  echo "local db         : NOT FOUND at $OSMX_DB_PATH"
fi

echo ""
echo "Pipeline files"
echo "------------------------------------------------------------"
echo "split-adiffs     : $(count "$SPLIT_ADIFFS_DIR" -maxdepth 1 -type d) changeset(s) accumulating"
echo "merged (stamps)  : $(count "$CHANGESET_DIR" -name '*.adiff.md5' -type f) changeset(s) merged"
echo "pending upload   : $(count "$BUCKET_DIR" -name '*.adiff' -type f) file(s) in bucket-data"
echo "bad changesets   : $(count "$BAD_CHANGESETS_DIR" -name '*.osc' -type f) failed .osc"
echo "stage-data size  : $(du -sh "$WORKDIR/stage-data" 2>/dev/null | cut -f1)"

echo ""
echo "Last processed"
echo "------------------------------------------------------------"
# Highest seqno seen = how far the pipeline advanced (matches the db seqno).
# busybox-safe: no find -printf, no date -d @epoch.
last_seq=$(ls "$SPLIT_ADIFFS_DIR"/*/*.adiff 2>/dev/null | sed 's:.*/::; s:\.adiff$::' | sort -n | tail -1)
if [ -n "$last_seq" ]; then
  last_file=$(ls "$SPLIT_ADIFFS_DIR"/*/"$last_seq.adiff" 2>/dev/null | head -1)
  echo "last seqno        : $last_seq (changeset $(basename "$(dirname "$last_file")"), $(mtime "$last_file"))"
else
  echo "last seqno        : none"
fi
last_stamp=$(ls -t "$CHANGESET_DIR"/*.adiff.md5 2>/dev/null | head -1)
if [ -n "$last_stamp" ]; then
  echo "last merged      : changeset $(basename "$last_stamp" .adiff.md5) ($(mtime "$last_stamp"))"
else
  echo "last merged      : none"
fi

echo ""
echo "Liveness (heartbeats)"
echo "------------------------------------------------------------"
for name in make_diffs publish; do
  a=$(age "$HEARTBEAT_DIR/$name")
  if [ "$a" = "-" ]; then
    echo "$name : no heartbeat yet"
  elif [ "$a" -gt "$HEARTBEAT_STALE_SECONDS" ]; then
    echo "$name : STALE (${a}s old > ${HEARTBEAT_STALE_SECONDS}s)"
  else
    echo "$name : ok (${a}s ago)"
  fi
done

echo ""
echo "Tip: ./status.sh <changeset_id>  to inspect a single changeset."
