# Tiler DB and Imposm Deployed in Hetzner

This is a basic manual deployment using Docker Compose to deploy `tiler-db` and `tiler-imposm` on a Hetzner server. The Compose files allocate resources for  only production enviroment

*Note 1*: This server is used only for production. Testing the instance for staging slows down the data import process the whole machine.

*Note 2*: Eventually, this approach should be improved by adding the Hetzner server as a node to EKS.

## Deploy Production

Make sure you are using the right, docker  images for production deployment,  it need to be added manully from

- Tiler Db:
https://github.com/orgs/OpenHistoricalMap/packages/container/tiler-db/versions


- Tiler Imposm
https://github.com/orgs/OpenHistoricalMap/packages/container/tiler-imposm/versions



## Deploy Staging

```sh
docker compose -f hetzner/tiler.staging.yml up db -d
docker compose -f hetzner/tiler.staging.yml up imposm -d
```

## Deploy Production

```sh
docker compose -f hetzner/tiler.production.yml up -d
```