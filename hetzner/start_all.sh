#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENVIRONMENT=${ENVIRONMENT}

# Validate ENVIRONMENT is set and is either staging or production
if [ -z "$ENVIRONMENT" ]; then
    echo "Error: ENVIRONMENT variable is not set"
    echo ""
    echo "Please export ENVIRONMENT before running this script:"
    echo "  export ENVIRONMENT=staging"
    echo "  export ENVIRONMENT=production"
    echo ""
    echo "Then run: $0"
    exit 1
fi

echo "########################## ENVIRONMENT -> $ENVIRONMENT ##########################"

# Load environment variables from .env.traefik
source "$SCRIPT_DIR/.env.traefik"
echo "########################## OHM_DOMAIN -> $OHM_DOMAIN ##########################"

# ###################### Tiler ######################
./hetzner/deploy.sh start tiler $ENVIRONMENT -y

# ###################### Osmcha ######################
./hetzner/deploy.sh start osmcha $ENVIRONMENT -y 

# ###################### Nominatim ######################
./hetzner/deploy.sh start nominatim $ENVIRONMENT -y 

# ###################### Overpass ####################
./hetzner/deploy.sh start overpass $ENVIRONMENT -y

#################### Taginfo ####################
./hetzner/deploy.sh start taginfo $ENVIRONMENT -y

#################### Traefik ####################

###### Update Cloudflare IPs and generate config file from template
cd "$SCRIPT_DIR/traefik" && ./update-cloudflare-ips.sh && cd "$SCRIPT_DIR"

docker compose -f $SCRIPT_DIR/services.yml --env-file $SCRIPT_DIR/.env.traefik up -d --force-recreate

## Stop services that is not requiered for staging
if [ "$ENVIRONMENT" = "staging" ]; then
    docker stop node_exporter
    docker stop cadvisor
    docker stop tiler_db
    docker stop tiler_imposm
fi

docker stop tiler_s3_cleaner
## clean tiler cache 
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml  run tiler_s3_cleaner tiler-cache-cleaner clean_by_prefix