# Tiler DB and Imposm Deployed in Hetzner

This is a basic manual deployment using Docker Compose to deploy `tiler-db` and `tiler-imposm` on a Hetzner server. The Compose files allocate resources for each environment deployment.

*Note*: Eventually, this approach should be improved by adding the Hetzner server as a node to EKS.

## Deploy Production

Make sure you are using the right, docker  images for production deployment,  it need to be added manully from

- Tiler Db:
https://github.com/orgs/OpenHistoricalMap/packages/container/tiler-db/versions


- Tiler Imposm
https://github.com/orgs/OpenHistoricalMap/packages/container/tiler-imposm/versions

```sh
docker compose -f hetzner/tiler.production.yml up -d
```

## Deploy Staging

For staging, it can be built from the source image, as staging is used for testing newly added objects or layers in the vector tiles.

```sh
docker compose -f hetzner/tiler.staging.yml build
docker compose -f hetzner/tiler.staging.yml up
```
