# Deploy in Hetzner

This folder contains the services that are being deployed on Hetzner. Currently, deployment is handled through Docker Compose, with the correct configuration and automatic restarts.

This environment is used for couple of services, since many of these secondary services consume significant resources, and deploying them on AWS would result in high maintenance costs. On Hetzner, however, the cost is much lower, and it provides large processing and memory capacities.

Each folder includes the configuration needed to start the containers. Also, remember to properly update the client configurations so that the URLs can correctly redirect traffic to these containers.

## Deploying Services

Most services can be deployed using the `deploy.sh` script, which provides a unified way to manage staging and production environments.

### Available Services

The following services support the `deploy.sh` script:

- **nominatim** - Geocoding service
- **taginfo** - Tag information service
- **overpass** - Overpass API
- **osmcha** - OSM Changeset Analyzer

### Using deploy.sh

```sh
# Start a service
./hetzner/deploy.sh start <service> [staging|production]

# Stop a service
./hetzner/deploy.sh stop <service> [staging|production]

# Restart a service
./hetzner/deploy.sh restart <service> [staging|production]
```

**Note:** The `tiler` service does not use `deploy.sh` due to its complexity. It is managed through separate configuration files. Please refer to `hetzner/tiler/README.md` for deployment instructions.

## Create Networks to Deploy Staging/Producion Services

```sh
docker network create --driver bridge ohm_network
```

## Check volumes that are been used by a container 

```sh
## used volumnes
docker inspect $(docker ps -q) --format='{{.Name}} => {{range .Mounts}}{{.Name}} {{end}}'
## not used volumes
docker volume ls --filter "dangling=true"
```


## Set up routing and exporter for services

This is important because this is charged to serve the site through the setup IP and also start up the node-exporter and cadvisor


```sh
docker compose -f hetzner/services.yml up -d --remove-orphans  --force-recreate
```
