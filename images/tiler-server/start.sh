#!/usr/bin/env bash
export PGPASSWORD=$POSTGRES_PASSWORD

flag=true
while "$flag" = true; do
  pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER -p $POSTGRES_PORT >/dev/null 2>&1 || continue
  flag=false
  echo "Running VACUUM and ANALYZE for tables to refresh the tables"
  tables=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -Atc "SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
  for table in $tables; do
      echo "---------------------------------------------"
      echo "Processing table: $table"
      # Run VACUUM
      start_time=$(date +%s)
      psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "VACUUM $table;" > /dev/null 2>&1
      end_time=$(date +%s)
      elapsed_time=$((end_time - start_time))
      echo "VACUUM completed for $table in $elapsed_time seconds."

      # Run ANALYZE
      start_time=$(date +%s)
      psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -d "$POSTGRES_DB" -c "ANALYZE $table;" > /dev/null 2>&1
      end_time=$(date +%s)
      elapsed_time=$((end_time - start_time))
      echo "ANALYZE completed for $table in $elapsed_time seconds."
  done

  TEGOLA_SQL_DEBUG=LAYER_SQL:EXECUTE_SQL tegola serve --config=/opt/tegola_config/config.toml
done