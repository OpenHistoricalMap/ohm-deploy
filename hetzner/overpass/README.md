# Overpass API Deployment

Overpass API is automatically deployed through GitHub Actions. However, you can also deploy it manually.

## Architecture

The deployment uses a **base + override** pattern with Docker Compose:
- `overpass.base.yml` - Shared configuration for both environments
- `overpass.staging.yml` - Staging-specific overrides (minimal, uses base config)
- `overpass.production.yml` - Production-specific overrides

This approach reduces duplication and makes configuration management easier.

## Quick Start with Script

The easiest way to deploy is using the `deploy.sh` script from the parent directory:

```sh
# Deploy to staging
./hetzner/deploy.sh start overpass staging

# Deploy to production
./hetzner/deploy.sh start overpass production

# Stop service
./hetzner/deploy.sh stop overpass staging

# Restart service
./hetzner/deploy.sh restart overpass production
```

## Manual Deployment

### Staging

```sh
docker compose -f hetzner/overpass/overpass.base.yml up -d
```

For the staging environment, the exposed port is **8085**

### Production

```sh
docker compose -f hetzner/overpass/overpass.base.yml -f hetzner/overpass/overpass.production.yml up -d
```

For the production environment, the exposed port is **8086**

## Notes

- Make sure you have the correct permissions for the database if needed:
  ```sh
  docker exec -it overpass_staging bash
  chmod -R u+rwX,g+rX,o+rX /db
  ```

- Make sure you set the right ports in values.staging.template.yaml and values.production.template.yaml file to avoid conflicts.

- Staging containers may be disabled by default. To stop deployments for staging or production, comment out or disable the corresponding branch in the relevant GitHub Actions workflow file.
