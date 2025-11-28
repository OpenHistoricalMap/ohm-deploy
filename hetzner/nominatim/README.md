# Nominatim Deployment

Nominatim API and UI deployment is handled manually using Docker Compose.

## Architecture

The deployment uses a **base + override** pattern with Docker Compose:
- `nominatim.base.yml` - Shared configuration for both environments
- `nominatim.staging.yml` - Staging-specific overrides
- `nominatim.production.yml` - Production-specific overrides

This approach reduces duplication and makes configuration management easier.

## Prerequisites

Before deploying, ensure the environment files exist (they are optional but referenced in the compose files):

- `envs.sample` - Staging environment file (already created, mostly empty)
- `.envs.nominatim.production` - Production environment file (already created, mostly empty)

These files are mostly empty as configuration is done through environment variables in the docker-compose files. Add any additional environment variables here if needed.

## Quick Start with Script

The easiest way to deploy is using the `deploy.sh` script from the parent directory:

```sh
# Deploy to staging
./hetzner/deploy.sh start nominatim staging

# Deploy to production
./hetzner/deploy.sh start nominatim production

# Stop service
./hetzner/deploy.sh stop nominatim staging

# Restart service
./hetzner/deploy.sh restart nominatim production
```
