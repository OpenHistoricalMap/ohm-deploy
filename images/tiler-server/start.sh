#!/usr/bin/env bash
export PGPASSWORD=$POSTGRES_PASSWORD

flag=true
while "$flag" = true; do
  pg_isready -h $POSTGRES_HOST -U $POSTGRES_USER -p $POSTGRES_PORT >/dev/null 2>&1 || continue
  flag=false
  echo "Running ANALYZE for tables"

  # Set temporary statement_timeout
  time psql -U $POSTGRES_USER -h $POSTGRES_HOST -d $POSTGRES_DB -c "SET statement_timeout = '300000'; DO \$\$ DECLARE r RECORD; BEGIN FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP EXECUTE 'ANALYZE ' || r.tablename; END LOOP; END \$\$;"

  export TEGOLA_SQL_DEBUG=LAYER_SQL:EXECUTE_SQL
  tegola serve --config=/opt/tegola_config/config.toml
done