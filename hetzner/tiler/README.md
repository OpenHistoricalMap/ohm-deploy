# Tiler Service Deployment in Hetzner

This repository provides the deployment setup for the Tiler service used in OpenHistoricalMap, utilizing Docker Compose.

🚀 Deploying to Production

Ensure you are using the correct Docker images for production deployment, https://github.com/orgs/OpenHistoricalMap/packages/


📌 Deploy Production Services


🛠 Deploying to Staging

To deploy the staging environment, use the following commands:

```sh
docker compose -f hetzner/tiler/tiler.base.yml up -d
# docker compose -f hetzner/tiler/tiler.base.yml up tiler_db -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml up tiler_imposm -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml up tiler_server -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml up tiler_sqs_cleaner -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml run tiler_s3_cleaner tiler-cache-cleaner clean_by_prefix
# docker compose -f hetzner/tiler/tiler.base.yml up tiler_monitor -d --force-recreate
```


```sh
docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up -d
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tiler_db -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tiler_imposm -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tiler_server -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tiler_sqs_cleaner -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tile_global_seeding -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tile_coverage_seeding -d --force-recreate
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml run tiler_s3_cleaner tiler-cache-cleaner clean_by_prefix
# docker compose -f hetzner/tiler/tiler.base.yml -f hetzner/tiler/tiler.production.yml up tiler_monitor -d --force-recreate 
```



📌 Notes
	•	Ensure that you are using the correct Docker images for each environment.
	•	Manually update the images before deploying production services.
	•	For troubleshooting, check logs.


# Enable Language Monitoring
To enable language monitoring, we need to start the container tiler_monitor_*, which is connected to the Docker socket (docker.sock). This allows it to start and manage other containers from within the monitoring container.


Here’s your README section rewritten in clearer English and with improved formatting:


## Environment variables

The environment variables for Tiler are quite large, so they need to be set up manually before deploying production services.
