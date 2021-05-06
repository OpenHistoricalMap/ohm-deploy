#!/bin/sh
set -e
if [[ "${MAX_CONNECTIONS}X" != "X" ]]; then
  sed -i -e"s/^.*max_connections =.*$/max_connections = $MAX_CONNECTIONS/" $PGDATA/postgresql.conf
fi
