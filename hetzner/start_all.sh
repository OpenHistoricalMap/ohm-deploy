#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Environment (so OHM_DOMAIN is correct for traefik/nominatim when using deploy.sh)
ENVIRONMENT=${ENVIRONMENT:-staging}

# Set domain based on environment (Docker Compose substitutes ${OHM_DOMAIN} in traefik.yml)
if [ "$ENVIRONMENT" = "production" ]; then
    export OHM_DOMAIN="openhistoricalmap.org"
else
    export OHM_DOMAIN="openhistoricalmap.net"
fi

# ###################### Tiler ######################
# ./hetzner/deploy.sh start tiler $ENVIRONMENT -y

# ###################### Nominatim ######################
# ./hetzner/deploy.sh start nominatim $ENVIRONMENT -y 

# ###################### Osmcha ######################
# ./hetzner/deploy.sh start osmcha $ENVIRONMENT  -y 

# ###################### Overpass ####################
# ./hetzner/deploy.sh start overpass $ENVIRONMENT -y

#################### Taginfo ####################
./hetzner/deploy.sh start taginfo $ENVIRONMENT -y

#################### Traefik ####################
###### Update Cloudflare IPs and generate config file from template
cd "$SCRIPT_DIR/traefik" && ./update-cloudflare-ips.sh && cd "$SCRIPT_DIR"

docker compose -f $SCRIPT_DIR/services.yml up -d --force-recreate

## Stop services that is not requiered for staging
if [ "$ENVIRONMENT" = "staging" ]; then
    docker stop taginfo_data_staging
    docker stop tiler_imposm
    docker stop node_exporter
    docker stop cadvisor
fi
