#!/usr/bin/env bash
flag=true
while "$flag" = true; do
  pg_isready -h $POSTGRES_HOST -p 5432 >/dev/null 2>&2 || continue
  flag=false
  export TEGOLA_SQL_DEBUG=LAYER_SQL:EXECUTE_SQL
  tegola serve --config=/opt/tegola_config/config.toml
done