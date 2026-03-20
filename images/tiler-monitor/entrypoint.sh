#!/bin/bash
set -e

echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting tiler-monitor (combined)"

# Start language monitor in background
echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting language monitor in background..."
bash /app/language-monitor/monitor_languages.sh &

# Start pipeline monitor in foreground
echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting pipeline monitor (FastAPI on port 8001)..."
cd /app/pipeline-monitor
exec python monitor.py
