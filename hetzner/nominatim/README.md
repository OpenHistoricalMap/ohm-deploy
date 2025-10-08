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
docker compose -f hetzner/nominatim/nominatim.production.yml up -d --remove-orphans  --force-recreate
```

For the production environment, the exposed ports are:
	•	API: 8083
	•	Nominatim UI: 8084


Since both environments run on the same server, these ports must be configured correctly in the values.staging.template.yaml and values.production.template.yaml file to avoid conflicts.

