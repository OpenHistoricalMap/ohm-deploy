#!/bin/bash -e
# Because of crashing updates, we wrote this small script to update every minute the Nominatim api
LOCAL_API=http://localhost:8080
# Load container env saved by docker-entrypoint.sh (cron has a minimal env)
[ -f /app/cron-env.sh ] && . /app/cron-env.sh
echo "Updating nominatim api...."
wget -q --spider $LOCAL_API
if [ ! $? -ne 0 ]; then
    sudo -u nominatim nominatim replication --project-dir /nominatim --catch-up --threads ${THREADS:-4} >>/var/log/replication.log
fi
