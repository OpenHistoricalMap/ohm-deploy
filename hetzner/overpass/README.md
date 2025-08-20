# Overpass API Deployment

Overpass API is automatically deployed through GitHub Actions. However, you can also deploy it manually.


### Staging

```sh
cd /staging/overpass
docker compose -f hetzner/overpass/overpass.staging.yml up -d
# Make sure you have the correct permissions for the database.
# docker exec -it overpass_staging bash
# chmod -R u+rwX,g+rX,o+rX /db

```
For the staging environment, the exposed port is 8085

### Production

```sh
cd /production/overpass
docker compose -f hetzner/overpass/overpass.production.yml up -d
```
For the production environment, the exposed port is 8086

Make sure you set the right ports in values.staging.template.yaml and values.production.template.yaml file to avoid conflicts.


**Note:** 

Staging containers may be disabled by default. To stop deployments for staging or production, comment out or disable the corresponding branch in the relevant GitHub Actions workflow file.
