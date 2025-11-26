#!/bin/bash
set -e

SERVICE=$1
ENVIRONMENT=${2:-staging}

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)/$SERVICE"
BASE_FILE="$SERVICE_DIR/$SERVICE.base.yml"
ENV_FILE="$SERVICE_DIR/$SERVICE.$ENVIRONMENT.yml"

if [ -z "$SERVICE" ]; then
    echo "Usage: $0 <service> [staging|production]"
    echo "Example: $0 nominatim staging"
    exit 1
fi

# For staging, only use base file. For production, use base + environment file
if [ "$ENVIRONMENT" = "staging" ]; then
    COMPOSE_CMD="docker compose -f $BASE_FILE"
else
    COMPOSE_CMD="docker compose -f $BASE_FILE -f $ENV_FILE"
fi

echo "================================================"
echo $COMPOSE_CMD
echo "================================================"


$COMPOSE_CMD up -d

echo "Deployment completed: $SERVICE ($ENVIRONMENT)"
