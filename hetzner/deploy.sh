#!/bin/bash
set -e

ACTION=$1
SERVICE=$2
ENVIRONMENT=${3:-staging}

# Check if first arg is an action (start/stop/restart)
if [ "$ACTION" = "start" ] || [ "$ACTION" = "stop" ] || [ "$ACTION" = "restart" ]; then
    # First arg is an action, so SERVICE is $2
    if [ -z "$SERVICE" ]; then
        echo "Usage: $0 start|stop|restart <service> [staging|production]"
        echo "Example: $0 start taginfo staging"
        exit 1
    fi
fi

if [ -z "$SERVICE" ]; then
    echo "Usage: $0 [start|stop|restart] <service> [staging|production]"
    echo "Examples:"
    echo "  $0 taginfo staging          # Start service"
    echo "  $0 stop taginfo staging     # Stop service"
    echo "  $0 restart taginfo staging # Restart service"
    exit 1
fi

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)/$SERVICE"
BASE_FILE="$SERVICE_DIR/$SERVICE.base.yml"
ENV_FILE="$SERVICE_DIR/$SERVICE.$ENVIRONMENT.yml"

# For staging, only use base file. For production, use base + environment file
if [ "$ENVIRONMENT" = "staging" ]; then
    COMPOSE_CMD="docker compose -f $BASE_FILE"
else
    COMPOSE_CMD="docker compose -f $BASE_FILE -f $ENV_FILE"
fi

echo "================================================"
echo "Action: $ACTION"
echo "Service: $SERVICE"
echo "Environment: $ENVIRONMENT"
echo "Command: $COMPOSE_CMD"
echo "================================================"

case "$ACTION" in
    start)
        $COMPOSE_CMD up -d
        echo "Service started: $SERVICE ($ENVIRONMENT)"
        ;;
    stop)
        $COMPOSE_CMD down
        echo "Service stopped: $SERVICE ($ENVIRONMENT)"
        ;;
    restart)
        $COMPOSE_CMD restart
        echo "Service restarted: $SERVICE ($ENVIRONMENT)"
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac
