# Tiler Service Deployment in Hetzner

This repository provides the deployment setup for the Tiler service used in OpenHistoricalMap, utilizing Docker Compose.

🚀 Deploying to Production

Ensure you are using the correct Docker images for production deployment, https://github.com/orgs/OpenHistoricalMap/packages/


📌 Deploy Production Services

```sh
docker compose -f hetzner/tiler.production.yml up -d
```

🛠 Deploying to Staging

To deploy the staging environment, use the following commands:

```sh
docker compose -f hetzner/tiler.staging.yml up db -d
docker compose -f hetzner/tiler.staging.yml up imposm -d
docker compose -f hetzner/tiler.staging.yml up tiler -d
docker compose -f hetzner/tiler.staging.yml up cache -d
docker compose -f hetzner/tiler.staging.yml up global_seeding -d
docker compose -f hetzner/tiler.staging.yml up tile_coverage_seeding -d
```

📌 Notes
	•	Ensure that you are using the correct Docker images for each environment.
	•	Manually update the images before deploying production services.
	•	For troubleshooting, check logs using:
