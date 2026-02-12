#!/bin/bash
set -e

# Parse --yes / -y so script can run non-interactively
AUTO_YES=false
ARGS=()
for a in "$@"; do
    if [[ "$a" == "--yes" || "$a" == "-y" ]]; then
        AUTO_YES=true
    else
        ARGS+=("$a")
    fi
done

ACTION=${ARGS[0]}
SERVICE=${ARGS[1]}
ENVIRONMENT=${ARGS[2]}

# Check if first arg is an action (start/stop/restart)
if [ "$ACTION" = "start" ] || [ "$ACTION" = "stop" ] || [ "$ACTION" = "restart" ]; then
    # First arg is an action, so SERVICE is $2
    if [ -z "$SERVICE" ]; then
        echo "Usage: $0 [--yes|-y] start|stop|restart <service> [staging|production]"
        echo "Example: $0 start taginfo staging"
        exit 1
    fi
fi

if [ -z "$SERVICE" ]; then
    echo "Usage: $0 [--yes|-y] [start|stop|restart] <service> [staging|production]"
    echo "  --yes, -y    Skip confirmation prompts"
    echo "Examples:"
    echo "  $0 taginfo staging          # Start service"
    echo "  $0 --yes start taginfo production   # Start without prompting"
    echo "  $0 stop taginfo staging     # Stop service"
    echo "  $0 restart taginfo staging  # Restart service"
    exit 1
fi

SERVICE_DIR="$(cd "$(dirname "$0")" && pwd)/$SERVICE"
BASE_FILE="$SERVICE_DIR/$SERVICE.base.yml"
ENV_FILE="$SERVICE_DIR/$SERVICE.$ENVIRONMENT.yml"

# Load environment variables from .env.traefik
HETZNER_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HETZNER_DIR/.env.traefik" ]; then
    export $(grep -v '^#' "$HETZNER_DIR/.env.traefik" | xargs)
fi

# Always use base + environment file for both staging and production
COMPOSE_CMD="docker compose -f $BASE_FILE -f $ENV_FILE"

echo "================================================"
echo "Action: $ACTION"
echo "Service: $SERVICE"
echo "Environment: $ENVIRONMENT"
echo "Command: $COMPOSE_CMD"
echo "================================================"

case "$ACTION" in
    start)
        # Show merged configuration before deploying
        echo ""
        echo "Preview of merged configuration:"
        echo "================================================"
        
        # Try to use colored output if available
        if command -v bat &> /dev/null; then
            $COMPOSE_CMD config | bat --language yaml --style=plain
        elif command -v pygmentize &> /dev/null; then
            $COMPOSE_CMD config | pygmentize -l yaml
        elif command -v highlight &> /dev/null; then
            $COMPOSE_CMD config | highlight --out-format=ansi --syntax=yaml
        else
            # Fallback: use basic colors with grep/awk
            $COMPOSE_CMD config | while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*# ]]; then
                    # Comments in gray
                    echo -e "\033[0;90m$line\033[0m"
                elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*: ]]; then
                    # Keys in yellow
                    key=$(echo "$line" | sed 's/:.*//')
                    rest=$(echo "$line" | sed 's/^[^:]*://')
                    echo -e "\033[0;33m$key\033[0m:\033[0;36m$rest\033[0m"
                elif [[ "$line" =~ ^[[:space:]]*- ]]; then
                    # List items in cyan
                    echo -e "\033[0;36m$line\033[0m"
                else
                    echo "$line"
                fi
            done
        fi
        
        echo "================================================"
        echo ""
        
        # Ask for confirmation (skip if --yes/-y)
        if [ "$AUTO_YES" != "true" ]; then
            if [ "$ENVIRONMENT" = "production" ]; then
                echo "⚠️  WARNING: You are about to deploy to PRODUCTION"
                echo ""
                read -p "Do you want to continue? (yes/no): " confirm
                if [ "$confirm" != "yes" ]; then
                    echo "Deployment cancelled."
                    exit 0
                fi
            else
                read -p "Do you want to continue with deployment? (yes/no): " confirm
                if [ "$confirm" != "yes" ]; then
                    echo "Deployment cancelled."
                    exit 0
                fi
            fi
        fi
        
        echo ""
        echo "Starting deployment..."
        $COMPOSE_CMD up -d
        echo ""
        echo "✓ Service started: $SERVICE ($ENVIRONMENT)"
        echo ""
        echo "================================================"
        echo "Useful commands:"
        echo "================================================"
        echo ""
        echo "# List running containers for this service:"
        echo "docker ps | grep ${SERVICE}"
        echo "docker exec -it ${SERVICE}_${ENVIRONMENT} bash"
        echo ""
        echo "# View logs:"
        echo "$COMPOSE_CMD logs -f"
        echo ""
        ;;
    stop)
        $COMPOSE_CMD down
        echo "Service stopped: $SERVICE ($ENVIRONMENT)"
        ;;
    restart)
        echo ""
        echo "Restarting with force recreate..."
        $COMPOSE_CMD up -d --force-recreate
        echo ""
        echo "✓ Service restarted (force recreated): $SERVICE ($ENVIRONMENT)"
        echo ""
        ;;
    *)
        echo "Unknown action: $ACTION"
        exit 1
        ;;
esac
