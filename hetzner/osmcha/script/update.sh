while true; do
    python manage.py fetchchangesets;
    sleep 300;
    ## Check the latest changeset https://osmcha.openhistoricalmap.org/changesets/198800
    # python manage.py backfill_changesets_id --start_id=198800;
done
