#!/bin/bash
# One-shot language monitor for Kubernetes (run by a CronJob, no while loop).
#
# Detects new language tags in the tiler DB and, when found, regenerates the
# materialized views (so they get the new name_<lang> columns) and restarts
# Martin so it serves the new schema. The docker-compose variant lives in
# monitor_languages.sh; this one uses kubectl instead.
set -euo pipefail

log() { echo "$(date +'%Y-%m-%d %H:%M:%S') - $*"; }

PG_CONNECTION="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"

NIM_NUMBER_LANGUAGES="${TILER_MONITORING_NIM_NUMBER_LANGUAGES:-5}"
FORCE_LANGUAGES_GENERATION="${TILER_MONITORING_FORCE_LANGUAGES_GENERATION:-false}"

# Targets to act on (namespace + release-scoped resource names)
NAMESPACE="${K8S_NAMESPACE:-default}"
IMPOSM_STS="${IMPOSM_STATEFULSET}"            # e.g. ohm-staging-tiler-imposm-sts
MARTIN_DEPLOY="${MARTIN_DEPLOYMENT}"          # e.g. ohm-staging-tiler-server-martin

log "Checking for new languages (threshold=${NIM_NUMBER_LANGUAGES}, force=${FORCE_LANGUAGES_GENERATION})"

# Populate languages table; flags rows is_new=TRUE when new languages appear.
psql "$PG_CONNECTION" -v ON_ERROR_STOP=1 \
  -c "SELECT populate_languages(${NIM_NUMBER_LANGUAGES}, '${FORCE_LANGUAGES_GENERATION}'::BOOLEAN);"

HAS_CHANGED=$(psql "$PG_CONNECTION" -t -A \
  -c "SELECT EXISTS (SELECT 1 FROM languages WHERE is_new = TRUE);")

log "has_changed = ${HAS_CHANGED}"

if [[ "$HAS_CHANGED" != "t" ]]; then
  log "No new languages. Nothing to do."
  exit 0
fi

# 1) Regenerate materialized views so they include the new language columns.
#    statement_timeout=0 so large CREATE MATERIALIZED VIEW statements finish.
#    NOTE: this recreates all ohm mviews; scope it to language-bearing views
#    later for efficiency.
log "New languages detected. Recreating materialized views in ${IMPOSM_STS}..."
kubectl -n "$NAMESPACE" exec "statefulset/${IMPOSM_STS}" -- \
  bash -c 'cd /osm && PGOPTIONS="-c statement_timeout=0" ./scripts/create_mviews.sh'

# 2) Restart Martin so it re-introspects the new schema.
log "Restarting Martin (${MARTIN_DEPLOY})..."
kubectl -n "$NAMESPACE" rollout restart "deployment/${MARTIN_DEPLOY}"
kubectl -n "$NAMESPACE" rollout status "deployment/${MARTIN_DEPLOY}" --timeout=300s

log "Done."
