# Deploy in hetzner

This folder contains the services that are being deployed on Hetzner. Currently, deployment is handled through Docker Compose, with the correct configuration and automatic restarts.

This environment is used for couple of services, since many of these secondary services consume significant resources, and deploying them on AWS would result in high maintenance costs. On Hetzner, however, the cost is much lower, and it provides large processing and memory capacities.

Each folder includes the configuration needed to start the containers. Also, remember to properly update the client configurations so that the URLs can correctly redirect traffic to these containers.

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
