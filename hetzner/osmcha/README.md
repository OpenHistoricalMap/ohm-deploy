## Full OSMCha Deployment

```sh
docker compose -f hetzner/osmcha/osmcha.yml up -d --force-recreate --remove-orphans
```

> **Note:** This command starts all services: database, API, frontend, and initialization tasks.  
> The commented commands below allow you to start individual services if needed:

```sh
# docker compose -f hetzner/osmcha/osmcha.yml up osmcha-db -d --force-recreate
# docker compose -f hetzner/osmcha/osmcha.yml up osmcha-init -d --force-recreate
# docker compose -f hetzner/osmcha/osmcha.yml up osmcha-api -d --force-recreate
# docker compose -f hetzner/osmcha/osmcha.yml up frontend-nginx -d --force-recreate
# docker compose -f hetzner/osmcha/osmcha.yml up osmcha-cron -d --force-recreate
```

## Restore Database from Backup

1. Download the backup from S3:

   ```sh
   aws s3 cp s3://test/osmcha/osmcha-backup.dump /staging/ohm-deploy/hetzner/osmcha/data_backup/osmcha-backup.dump
   ```

2. Start only the database container:

   ```sh
   docker compose -f hetzner/osmcha/osmcha.staging.yml up osmcha-db -d --force-recreate
   ```

3. Restore the dump:

   ```sh
   docker exec -it osmcha-db bash
   pg_restore -U postgres -d osmcha --clean --if-exists /data_backup/osmcha-backup.dump
   psql -U postgres -d osmcha -c "\dt"
   ```

---

## Deploy OHMX

```sh
docker compose -f hetzner/osmcha/ohmx_adiff.yml up ohmx_adiff_producion -d --force-recreate
```
