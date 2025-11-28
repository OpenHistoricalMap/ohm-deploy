# Nominatim Deployment

Nominatim API and UI are automatically deployed through GitHub Actions. However, you can also deploy it manually.

## Architecture

The deployment uses a **base + override** pattern with Docker Compose:
- `nominatim.base.yml` - Shared configuration for both environments
- `nominatim.staging.yml` - Staging-specific overrides
- `nominatim.production.yml` - Production-specific overrides

This approach reduces duplication and makes configuration management easier.

## Quick Start with Script

The easiest way to deploy is using the `start.sh` script from the parent directory:

```sh


# Deploy to staging explicitly
./hetzner/start.sh nominatim staging

# Deploy to production
# cp /hetzner/nominatim/.env.sample /hetzner/nominatim/.envs.nominatim.production
./hetzner/start.sh nominatim production

```
