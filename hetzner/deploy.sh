#!/bin/bash
set -e

AUTO_YES=false
ARGS=()
for a in "$@"; do
    [[ "$a" == "--yes" || "$a" == "-y" ]] && AUTO_YES=true || ARGS+=("$a")
done

ACTION=${ARGS[0]}
SERVICE=${ARGS[1]}
ENVIRONMENT=${ARGS[2]}

if [ -z "$SERVICE" ] || [ -z "$ENVIRONMENT" ]; then
    echo "Usage: $0 [--yes|-y] start|stop|restart <service> staging|production"
    echo "Example: $0 start taginfo staging"
    exit 1
fi

HETZNER_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_FILE="$HETZNER_DIR/$SERVICE/$SERVICE.base.yml"
ENV_FILE="$HETZNER_DIR/$SERVICE/$SERVICE.$ENVIRONMENT.yml"

[ -f "$HETZNER_DIR/.env.traefik" ] && export $(grep -v '^#' "$HETZNER_DIR/.env.traefik" | xargs)

if [ -f "$ENV_FILE" ]; then
    COMPOSE="docker compose -f $BASE_FILE -f $ENV_FILE"
else
    COMPOSE="docker compose -f $BASE_FILE"
fi

echo "==> $ACTION $SERVICE ($ENVIRONMENT)"

# Confirm before start/restart (skip with --yes)
if [[ "$ACTION" == "start" || "$ACTION" == "restart" ]] && [ "$AUTO_YES" != "true" ]; then
    [ "$ENVIRONMENT" = "production" ] && echo "WARNING: Deploying to PRODUCTION"
    echo ""
    $COMPOSE config
    echo ""
    read -p "Continue? (yes/no): " confirm
    [ "$confirm" != "yes" ] && echo "Cancelled." && exit 0
fi

case "$ACTION" in
    start)   $COMPOSE up -d ;;
    stop)    $COMPOSE down ;;
    restart) $COMPOSE up -d --force-recreate ;;
    *)       echo "Unknown action: $ACTION"; exit 1 ;;
esac

echo "Done: $ACTION $SERVICE ($ENVIRONMENT)"
