#!/bin/bash
# Common functions for ohmx-adiff-builder scripts

upload_diff_files() {
  # Optional parameter: "once" to execute only once, any other value or empty for continuous loop
  local mode="${1:-loop}"
  
  mkdir -p "$(dirname "$UPLOAD_TRACK_FILE")"
  touch "$UPLOAD_TRACK_FILE"

  declare -A uploaded_md5s
  while read -r line; do
    file=$(echo "$line" | awk '{print $1}')
    hash=$(echo "$line" | awk '{print $2}')
    uploaded_md5s["$file"]="$hash"
  done < "$UPLOAD_TRACK_FILE"

  # Function to process files once
  process_upload() {
    echo "Uploading files at $(date)..."
    # Search in bucket-data (where compressed changeset files are)
    # and also in bucket-data/replication/minute (where replication files are)
    # Use process substitution to avoid subshell
    while IFS= read -r filepath; do
      [ -z "$filepath" ] || [ ! -f "$filepath" ] && continue
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

      aws s3 cp "$filepath" "s3://$AWS_S3_BUCKET/ohm-augmented-diffs/changesets/$filename" \
        --content-type "application/xml" \
        --content-encoding "gzip" && \
      uploaded_md5s["$filename"]="$current_md5"
    done < <(find "$BUCKET_DIR" -type f -name '*.adiff' -mmin -60 2>/dev/null)

    # Update control file
    : > "$UPLOAD_TRACK_FILE"
    for fname in "${!uploaded_md5s[@]}"; do
      echo "$fname ${uploaded_md5s[$fname]}" >> "$UPLOAD_TRACK_FILE"
    done
  }

  if [[ "$mode" == "once" ]]; then
    # Execute only once
    process_upload
  else
    # Execute in continuous loop
    while true; do
      process_upload
      sleep 60
    done
  fi
}

# Function to download and generate adiff files for a seqno range
# Downloads .osc files from replication server, generates .adiff files, and updates osmx database
download_and_generate_adiffs() {
  local seqno_min=$1
  local seqno_max=$2
  
  echo "Downloading and generating adiffs for range: $seqno_min - $seqno_max"
  
  eval "$(mise activate bash --shims)"
  
  for seqno in $(seq "$seqno_min" "$seqno_max"); do
    echo "Processing seqno: $seqno"
    
    # Get the replication URL for this seqno
    # Format: seqno is padded to 9 digits, split into 3 parts: XXX/XXX/XXX
    seqno_padded=$(printf "%09d" "$seqno")
    part1=$(echo "$seqno_padded" | cut -c1-3)
    part2=$(echo "$seqno_padded" | cut -c4-6)
    part3=$(echo "$seqno_padded" | cut -c7-9)
    url="${REPLICATION_URL}/${part1}/${part2}/${part3}.osc.gz"
    
    # Download and decompress the .osc file
    if ! curl -sL "$url" | gzip -d > "${seqno}.osc" 2>/dev/null; then
      echo "Warning: Failed to download seqno $seqno from $url, skipping..."
      continue
    fi
    
    # Check if .osc file was downloaded successfully
    if [ ! -f "${seqno}.osc" ] || [ ! -s "${seqno}.osc" ]; then
      echo "Warning: Empty or missing .osc file for seqno $seqno, skipping..."
      continue
    fi
    
    # Generate augmented diff
    tmpfile=$(mktemp)
    if ! python augmented_diff.py "$OSMX_DB_PATH" "${seqno}.osc" | xmlstarlet format > "$tmpfile" 2>/dev/null; then
      echo "Warning: Failed to generate adiff for seqno $seqno, skipping..."
      rm -f "${seqno}.osc" "$tmpfile"
      continue
    fi
    
    # Move adiff to replication directory
    mkdir -p "$REPLICATION_ADIFFS_DIR"
    mv "$tmpfile" "$REPLICATION_ADIFFS_DIR/${seqno}.adiff"
    
    # Get timestamp from replication state (if available) or use current time
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    
    # Update osmx database
    if osmx update "$OSMX_DB_PATH" "${seqno}.osc" "$seqno" "$timestamp" --commit 2>/dev/null; then
      echo "Successfully processed seqno $seqno"
    else
      echo "Warning: Failed to update osmx database for seqno $seqno"
    fi
    
    # Clean up .osc file
    rm -f "${seqno}.osc"
  done
}

# Function to process adiff files by sequence number (seqno) range
# Splits adiffs, moves them to bucket-data, merges split adiffs, uploads, and cleans up
process_adiff_range() {
  local seqno_start=$1
  local seqno_end=$2
  
  mkdir -p "$REPLICATION_ADIFFS_DIR" "$SPLIT_ADIFFS_DIR" "$CHANGESET_DIR" "$BUCKET_DIR/replication/minute"
  
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
}
