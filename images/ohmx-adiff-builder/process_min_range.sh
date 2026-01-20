#!/bin/bash
# Script to process adiff files by sequence number (seqno) range
# Usage: ./process_min_range.sh SEQNO_START SEQNO_END
# Example: ./process_min_range.sh 1884610 1884615
# ./process_min_range.sh 1884950 1884970
#
# Does the following:
# - splits all adiffs in the specified range from stage-data/replication-adiffs/*.adiff into stage-data/split-adiffs/*/
# - moves processed adiffs to bucket-data
# - merges all split adiffs in each split-adiffs/*/ into one merged-adiffs/*.adiff

# Load configuration
source "config.sh"
source "functions.sh"

seqno_start=$1
seqno_end=$2

mkdir -p $REPLICATION_ADIFFS_DIR $SPLIT_ADIFFS_DIR $CHANGESET_DIR $BUCKET_DIR/replication/minute

echo "Processing range: $seqno_start - $seqno_end"

# Find files in the specified range
for seqno in $(seq "$seqno_start" "$seqno_end"); do
  adiff_file="$REPLICATION_ADIFFS_DIR/${seqno}.adiff"
  echo "Processing adiff file: $adiff_file"
  [ ! -f "$adiff_file" ] && continue

  seqno=$(basename -s .adiff "$adiff_file")
  tmpdir=$(mktemp -d)

  # split the adiff file
  python split_adiff.py "$adiff_file" "$tmpdir"

  for file in "$tmpdir"/*.adiff; do
    [ ! -f "$file" ] && continue
    changeset=$(basename -s .adiff "$file")
    mkdir -p "${SPLIT_ADIFFS_DIR}/${changeset}"
    mv "$file" "${SPLIT_ADIFFS_DIR}/${changeset}/${seqno}.adiff"
  done

  rm -rf "$tmpdir"

  # move the adiff file to the output directory. this means it won't be processed
  # again in the future and can be uploaded to R2 and deleted locally.
  # compress it first
  tmpfile=$(mktemp)
  gzip -c < "$adiff_file" > "$tmpfile"
  # move it into place atomically
  mkdir -p "${BUCKET_DIR}/replication/minute"
  mv "$tmpfile" "${BUCKET_DIR}/replication/minute/$(basename "$adiff_file")"
  rm "$adiff_file"
done

# merge all our split files, potentially updating existing changesets.
# this is done using a makefile script in order to avoid needlessly reprocessing
# changesets whose set of input (split-adiffs/) files haven't changed.
[ -f "merge.mk" ] && make -f merge.mk || true

upload_diff_files "once"

# clean up old stage-data that we don't need anymore
[ -f "gc.sh" ] && ./gc.sh "$SPLIT_ADIFFS_DIR" "$CHANGESET_DIR" || true
