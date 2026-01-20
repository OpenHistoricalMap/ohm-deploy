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
