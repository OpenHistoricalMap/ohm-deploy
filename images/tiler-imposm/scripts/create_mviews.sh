#!/bin/bash
set -e

# ------------------------------------------------------------------------------
# Script: create_mviews.sh
# Description:
#   Creates the materialized views of the layers listed in layers.yaml, in that
#   order. The SQL files of each layer are declared in layers/<name>/layer.yaml:
#   "sql" runs on every build, "sql_init" only on the initial import (--all).
#
# Usage:
#   ./scripts/create_mviews.sh                 # views of every layer
#   ./scripts/create_mviews.sh others routes   # views of the given layers only
#   ./scripts/create_mviews.sh --all=true      # initial import: utils + sql_init + views of every layer
# ------------------------------------------------------------------------------

source ./scripts/utils.sh

ALL=false
LAYERS=()
for arg in "$@"; do
  case "$arg" in
    --all=true) ALL=true ;;
    *) LAYERS+=("$arg") ;;
  esac
done

# Resolve the SQL files first: fails before running anything when a layer name is unknown
init_files=$(python3 scripts/layers.py sql --init "${LAYERS[@]}")
sql_files=$(python3 scripts/layers.py sql "${LAYERS[@]}")

##################### Helper functions #####################
# Always (re)load helper functions first: every layer relies on them.
log_message "Loading mview helper functions"
execute_sql_file queries/utils/postgis_helpers.sql
execute_sql_file queries/utils/finalize_materialized_view.sql
execute_sql_file queries/utils/create_area_mview.sql
execute_sql_file queries/utils/create_point_mview.sql
execute_sql_file queries/utils/create_line_mview.sql
execute_sql_file queries/utils/derive_area_mview.sql
execute_sql_file queries/utils/derive_line_mview.sql
execute_sql_file queries/utils/derive_centroid_mview.sql

if [[ "$ALL" == true ]]; then
  ##################### Initial import only #####################
  log_message "Creating utility functions and one-time views"
  execute_sql_file queries/utils/utils.sql
  # This will populate languages, NOTE make sure run this first
  execute_sql_file queries/utils/fetch_db_languages.sql
  execute_sql_file queries/utils/route_priority.sql
  for sql_file in $init_files; do
    execute_sql_file "$sql_file"
  done
fi

##################### Layers #####################
log_message "Creating materialized views for layers: ${LAYERS[*]:-all}"
for sql_file in $sql_files; do
  execute_sql_file "$sql_file"
done
