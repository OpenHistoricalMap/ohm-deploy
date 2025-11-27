# Taginfo Deployment

Taginfo is automatically deployed through GitHub Actions. However, you can also deploy it manually.

## Architecture

The deployment uses a **base + override** pattern with Docker Compose:
- `taginfo.base.yml` - Shared configuration for both environments
- `taginfo.staging.yml` - Staging-specific overrides
- `taginfo.production.yml` - Production-specific overrides

This approach reduces duplication and makes configuration management easier.

## Quick Start with Script

The easiest way to deploy is using the `start.sh` script from the parent directory:

```sh

# Deploy to staging explicitly
./hetzner/start.sh taginfo staging
docker compose  -f hetzner/taginfo/taginfo.base.yml up taginfo
# docker compose  -f hetzner/taginfo/taginfo.base.yml run taginfo_db_processor  bash
# docker compose -f hetzner/taginfo/taginfo.base.yml -f hetzner/taginfo/taginfo.production.yml run taginfo_db_processor bash

# Deploy to production
./hetzner/start.sh taginfo production
docker compose  -f hetzner/taginfo/taginfo.base.yml -f hetzner/taginfo/taginfo.prodution.yml up taginfo

```


