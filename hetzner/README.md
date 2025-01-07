# Tiler DB and Imposm Deployed in Hetzner

This is a basic manual deployment using Docker Compose to deploy `tiler-db` and `tiler-imposm` on a Hetzner server. The Compose files allocate resources for each environment deployment.

*Note*: Eventually, this approach should be improved by adding the Hetzner server as a node to EKS.

## Deploy Production


Make sure you import al the required 
```sh
docker compose -f hetzner/tiler.production.yml up -d
```


## Deploy Staging

```sh
docker compose -f hetzner/tiler.staging.yml build
docker compose -f hetzner/tiler.staging.yml up
```
