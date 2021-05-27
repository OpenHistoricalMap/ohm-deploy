#!/bin/bash
set -a
set +a

workDir=/mnt/data

expire_dir=$workDir/imposm/imposm3_expire_dir
mkdir -p $expire_dir

# This will be essentially treated as a pidfile
queued_jobs=$workDir/imposm/in_progress.list
# Output of seeded
completed_jobs=$workDir/imposm/completed.list

# Directory to place the worked expiry lists
completed_dir=$workDir/imposm/imposm3_expire_purged
mkdir -p $completed_dir

# List files in expire_dir
imp_list=$(find $expire_dir -name '*.tiles' -type f)

for f in $imp_list; do
    echo "$f" >>$queued_jobs
done

# Sort the files and set unique rows
if [ -f $queued_jobs ]; then
    sort -u $queued_jobs >$workDir/imposm/tmp.list && mv $workDir/imposm/tmp.list $queued_jobs
fi

for f in $imp_list; do
    echo "Purge tiles from...$f"
    set -x
    tegola cache purge tile-list $f \
        --config=/opt/tegola_config/config.toml \
        --format="/zxy" \
        --min-zoom=0 \
        --max-zoom=20 \
        --overwrite=true
    set +x
    # while IFS= read -r tile; do
    #     bounds="$(python3 tile2bounds.py $tile)"
    #     # Get tiles values
    #     arraytile=($(echo "$tile" | tr '/' '\n'))
    #     zoom=${arraytile[0]}
    #     x=${arraytile[1]}
    #     y=${arraytile[2]}
    #     set -x
    #     tegola cache purge \
    #         --config=/opt/tegola_config/config.toml \
    #         --min-zoom=$zoom \
    #         --max-zoom=20 \
    #         --overwrite=true \
    #         --bounds=$bounds \
    #         tile-name=$tile
    #     err=$?
    #     set +x
    #     if [[ $err != "0" ]]; then
    #         echo "tegola exited with error code $err"
    #         exit
    #     fi
    # done <"$f"
    echo "$f" >>$completed_jobs
    mv $f $completed_dir
done

if [ -f $queued_jobs ]; then
    echo "finished seeding"
    rm $queued_jobs
fi
