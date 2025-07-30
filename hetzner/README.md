# Tiler Service Deployment in Hetzner

This repository provides the deployment setup for the Tiler service used in OpenHistoricalMap, utilizing Docker Compose.

🚀 Deploying to Production

Ensure you are using the correct Docker images for production deployment, https://github.com/orgs/OpenHistoricalMap/packages/


📌 Deploy Production Services

```sh
docker compose -f hetzner/tiler.production.yml up -d
# docker compose -f hetzner/tiler.production.yml up db_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml up imposm_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml up tiler_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml up tiler_sqs_cleaner_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml up tile_global_seeding_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml up tile_coverage_seeding_production -d --force-recreate
# docker compose -f hetzner/tiler.production.yml run tiler_s3_cleaner_production tiler-cache-cleaner clean_by_prefix
# docker compose -f hetzner/tiler.production.yml up tiler_monitor_production -d --force-recreate 
```

🛠 Deploying to Staging

To deploy the staging environment, use the following commands:

```sh
docker compose -f hetzner/tiler.staging.yml up -d
# docker compose -f hetzner/tiler.staging.yml up db_staging -d --force-recreate
# docker compose -f hetzner/tiler.staging.yml up imposm_staging -d --force-recreate
# docker compose -f hetzner/tiler.staging.yml up tiler_staging -d --force-recreate
# docker compose -f hetzner/tiler.staging.yml up tiler_sqs_cleaner_staging -d --force-recreate
# docker compose -f hetzner/tiler.staging.yml up tiler_s3_cleaner_staging tiler-cache-cleaner clean_by_prefix
# docker compose -f hetzner/tiler.staging.yml up tiler_monitor_staging -d --force-recreate
```

📌 Notes
	•	Ensure that you are using the correct Docker images for each environment.
	•	Manually update the images before deploying production services.
	•	For troubleshooting, check logs.


# Enable Language Monitoring
To enable language monitoring, we need to start the container tiler_monitor_*, which is connected to the Docker socket (docker.sock). This allows it to start and manage other containers from within the monitoring container.


Here’s your README section rewritten in clearer English and with improved formatting:


---

# Nominatim Deployment

Nominatim API and UI are automatically deployed through GitHub Actions. However, you can also deploy it manually:


### Staging

```sh
cd /staging/nominatim
docker compose -f hetzner/nominatim/nominatim.staging.yml up -d

```
For the staging environment, the exposed ports are:
	•	API: 8081
	•	Nominatim UI: 8082


### Production

In production, Nominatim is currently limited to:
	•	Memory: 10g (mem_limit)
	•	CPUs: 4.0 (cpus)

```sh
cd /production/nominatim
docker compose -f hetzner/nominatim/nominatim.production.yml up
```

For the production environment, the exposed ports are:
	•	API: 8083
	•	Nominatim UI: 8084


Since both environments run on the same server, these ports must be configured correctly in the values.staging.template.yaml and values.production.template.yaml file to avoid conflicts.

---

# Overpass API Deployment

Overpass API is automatically deployed through GitHub Actions. However, you can also deploy it manually.


### Staging

```sh
cd /staging/overpass
docker compose -f hetzner/overpass/overpass.staging.yml up -d

```
For the staging environment, the exposed port is 8085

### Production

```sh
cd /production/overpass
docker compose -f hetzner/nominatim/nominatim.producion.yml up -d
```
For the production environment, the exposed port is 8086

Make sure you set the right ports in values.staging.template.yaml and values.production.template.yaml file to avoid conflicts.


---
**Note:** 

Staging containers may be disabled by default. To stop deployments for staging or production, comment out or disable the corresponding branch in the relevant GitHub Actions workflow file.
