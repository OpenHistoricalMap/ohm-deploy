#!/bin/bash
set -e

source ./scripts/utils.sh

# Uploads an RSS feed with the status of all processes to S3 every hour.
# Reads JSON status files from /tmp/mview_status/ written by:
#   - refresh_mviews.sh (mview refresh groups)
#   - start.sh (imposm replication monitor)

S3_PATH="${AWS_S3_BUCKET}/${BUCKET_IMPOSM_FOLDER}/status.rss"

while true; do
    sleep 3600
    items=""
    for f in "$STATUS_DIR"/*.json; do
        [ -f "$f" ] || continue
        group=$(grep -o '"group":"[^"]*"' "$f" | cut -d'"' -f4)
        status=$(grep -o '"status":"[^"]*"' "$f" | cut -d'"' -f4)
        timestamp=$(grep -o '"timestamp":"[^"]*"' "$f" | cut -d'"' -f4)
        duration=$(grep -o '"duration_seconds":[0-9]*' "$f" | cut -d: -f2)
        total=$(grep -o '"views_total":[0-9]*' "$f" | cut -d: -f2)
        failed=$(grep -o '"views_failed":[0-9]*' "$f" | cut -d: -f2)
        failed_views=$(grep -o '"failed_views":"[^"]*"' "$f" | cut -d'"' -f4)
        error=$(grep -o '"error":"[^"]*"' "$f" | cut -d'"' -f4)

        title="$group - $status"
        if [ "$total" -gt 0 ] 2>/dev/null; then
            desc="$((total - failed))/${total} views refreshed in ${duration}s"
            [ "$failed" -gt 0 ] && desc="$desc | Failed: $failed_views"
        else
            desc="$status"
            [ -n "$error" ] && desc="$desc | $error"
        fi

        items="$items<item><title>$title</title><description>$desc</description><pubDate>$timestamp</pubDate></item>"
    done

    rss="<?xml version=\"1.0\" encoding=\"UTF-8\"?><rss version=\"2.0\"><channel><title>OHM Tiler Status</title><link>${S3_PATH}</link><lastBuildDate>$(date -u '+%Y-%m-%dT%H:%M:%SZ')</lastBuildDate>${items}</channel></rss>"
    echo "$rss" > /tmp/status.rss
    aws s3 cp /tmp/status.rss "$S3_PATH" --acl public-read 2>/dev/null && \
        log_message "RSS feed uploaded to $S3_PATH" || \
        log_message "Failed to upload RSS feed"
done
