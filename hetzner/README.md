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
