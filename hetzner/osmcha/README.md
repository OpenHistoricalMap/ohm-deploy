# OSMCha Deployment

Deploy  OSMCha

## Architecture

The deployment uses a **base + override** pattern with Docker Compose:
- `osmcha.base.yml` - Shared configuration for both environments
- `osmcha.staging.yml` - Staging-specific overrides (minimal, uses base config)
- `osmcha.production.yml` - Production-specific overrides

This approach reduces duplication and makes configuration management easier.

## Prerequisites

Before deploying, ensure the environment file exists:

```sh
# Copy the example environment file
cp hetzner/osmcha/env.osmcha.example hetzner/osmcha/.env.osmcha
```

Edit `.env.osmcha` and fill in all the required values.

## Quick Start with Script

The easiest way to deploy is using the `deploy.sh` script from the parent directory:

```sh
# Deploy to staging
./hetzner/deploy.sh start osmcha staging

# Deploy to production
./hetzner/deploy.sh start osmcha production

# Stop service
./hetzner/deploy.sh stop osmcha staging

# Restart service
./hetzner/deploy.sh restart osmcha production
```

## Manual Deployment

### Full Deployment

```sh
# Staging
docker compose -f hetzner/osmcha/osmcha.base.yml up -d

# Production
docker compose -f hetzner/osmcha/osmcha.base.yml -f hetzner/osmcha/osmcha.production.yml up -d
```

### Individual Services

You can start individual services if needed:

```sh
# Start database only
docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha-db -d --force-recreate

# Start initialization
docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha-init -d --force-recreate

# Start API
docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha-api -d --force-recreate

# Start frontend
docker compose -f hetzner/osmcha/osmcha.base.yml up frontend-nginx -d --force-recreate

# Start cron job
docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha-cron -d --force-recreate

# Start ohmx adiff builder
docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha_ohmx_adiff -d --force-recreate
```

## Restore Database from Backup

1. Download the backup from S3:

   ```sh
   aws s3 cp s3://test/osmcha/osmcha-backup.dump /staging/ohm-deploy/hetzner/osmcha/data_backup/osmcha-backup.dump
   ```

2. Start only the database container:

   ```sh
   docker compose -f hetzner/osmcha/osmcha.base.yml up osmcha-db -d --force-recreate
   ```

3. Restore the dump:

   ```sh
   docker exec -it osmcha-db bash
   pg_restore -U postgres -d osmcha --clean --if-exists /data_backup/osmcha-backup.dump
   psql -U postgres -d osmcha -c "\dt"
   ```

## Services

- **osmcha-db**: PostgreSQL database with PostGIS extension
- **osmcha-redis**: Redis cache
- **osmcha-init**: Initialization container (migrations and static files)
- **osmcha-api**: Django API server (Gunicorn)
- **frontend-nginx**: Frontend web server
- **osmcha-cron**: Cron job container for periodic tasks
- **osmcha_ohmx_adiff**: OSMX adiff builder service
