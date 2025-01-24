#!/usr/bin/env bash
export PGPASSWORD=$POSTGRES_PASSWORD

flag=true
while [ "$flag" = true ]; do
  # Wait until PostgreSQL is ready
  pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER -p $POSTGRES_PORT >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    continue
  fi

  flag=false

  # Execute VACUUM and ANALYZE if enabled
  if [ "$EXECUTE_VACUUM_ANALYZE" = "true" ]; then
    echo "Running VACUUM and ANALYZE for tables to refresh the tables"
    tables=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -Atc "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
    for table in $tables; do
      echo "---------------------------------------------"
      echo "Processing table: $table"

      # Run VACUUM
      start_time=$(date +%s)
      psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "VACUUM $table;" >/dev/null 2>&1
      end_time=$(date +%s)
      elapsed_time=$((end_time - start_time))
      echo "VACUUM completed for $table in $elapsed_time seconds."

      # Run ANALYZE
      start_time=$(date +%s)
      psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "ANALYZE $table;" >/dev/null 2>&1
      end_time=$(date +%s)
      elapsed_time=$((end_time - start_time))
      echo "ANALYZE completed for $table in $elapsed_time seconds."
    done
  fi

  # Execute REINDEX if enabled
  if [ "$EXECUTE_REINDEX" = "true" ]; then
    echo "Running REINDEX for primary keys"
    psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "
    DO \$\$
    DECLARE
        tbl RECORD;
        idx_name TEXT;
    BEGIN
        FOR tbl IN
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'public'
        LOOP
            SELECT indexname INTO idx_name
            FROM pg_indexes
            WHERE schemaname = 'public' AND tablename = tbl.tablename AND indexname LIKE tbl.tablename || '_pkey';

            IF idx_name IS NOT NULL THEN
                RAISE NOTICE 'Reindexing index: %', idx_name;
                EXECUTE format('REINDEX INDEX %I;', idx_name);
            END IF;
        END LOOP;
    END
    \$\$;" >/dev/null 2>&1
    echo "REINDEX completed."
  fi

  # Start Tegola server
  tegola serve --config=/opt/tegola_config/config.toml
done