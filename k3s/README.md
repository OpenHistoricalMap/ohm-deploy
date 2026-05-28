# OHM Services - k3s Chart

Helm chart for OpenHistoricalMap secondary services (taginfo, overpass, nominatim, osmcha, tiler). Replaces the docker-compose stack in `../hetzner/`. Targets k3s but works on any standard Kubernetes distribution (EKS, RKE2, kind).

## Layout

```
k3s/
├── Chart.yaml
├── chartpress.yaml                       # OHM-owned image build config
├── values.yaml                           # defaults for all services
├── values.staging.template.yaml          # staging overrides
├── values.production.template.yaml       # production overrides
└── templates/
    ├── _helpers.tpl
    ├── taginfo/
    ├── overpass/
    ├── nominatim/
    └── osmcha/
```

Cloudflare Tunnel runs as infra outside this chart. See `ohm-deployment/hetzner/scripts/06-cloudflared-web.sh`.

Each service has its own subfolder under `templates/`. Every manifest is wrapped in `{{- if .Values.<service>.enabled -}}` so services toggle on/off in values.

## Image tag policy

Three cases:

| Case | Tag in `values.yaml` | Who updates |
|---|---|---|
| OHM-owned image built in this repo | empty / placeholder | `chartpress` on CI run |
| OHM-owned image built in another repo | hardcoded | `repository_dispatch` workflow |
| Third-party image (postgis, redis, taginfo-web) | hardcoded pinned | manual PR |

Chartpress entries live in `k3s/chartpress.yaml`. The existing `ohm-deploy/chartpress.yaml` covers the legacy `ohm/` chart and stays untouched.

## Pre-deploy: secrets

Templates expect these Secrets to exist in the target namespace. Create them before `helm upgrade` (or use sealed-secrets / external-secrets):

```bash
kubectl create namespace ohm-production

kubectl -n ohm-production create secret generic taginfo-env \
  --from-env-file=../hetzner/taginfo/.env.taginfo

kubectl -n ohm-production create secret generic nominatim-env \
  --from-env-file=../hetzner/nominatim/.env.nominatim

kubectl -n ohm-production create secret generic osmcha-env \
  --from-env-file=../hetzner/osmcha/.env.osmcha

kubectl -n ohm-production create configmap osmcha-scripts \
  --from-file=update.sh=../hetzner/osmcha/script/update.sh \
  --from-file=backfill_changesets.py=../hetzner/osmcha/script/backfill_changesets.py

kubectl -n ohm-production create configmap osmcha-nginx \
  --from-file=nginx.conf=../hetzner/osmcha/config/nginx.conf
```

## Deploy

Staging:
```bash
helm upgrade --install ohm-services . \
  -f values.yaml \
  -f values.staging.template.yaml \
  -n ohm-staging --create-namespace
```

Production:
```bash
helm upgrade --install ohm-services . \
  -f values.yaml \
  -f values.production.template.yaml \
  -n ohm-production --create-namespace
```

Deploy a single service only (other services disabled via `--set`):
```bash
helm upgrade --install ohm-taginfo . \
  -f values.yaml \
  --set overpass.enabled=false \
  --set nominatim.enabled=false \
  --set osmcha.enabled=false \
  -n ohm-production
```

## Auto-update image tags

In CI, before `helm upgrade`:

```bash
pip install chartpress
chartpress --push
# chartpress builds, pushes to ghcr.io, and rewrites values.yaml
# with the new tags for entries declared in chartpress.yaml.
helm upgrade --install ohm-services . -f /tmp/values.production.yaml \
  -n ohm-production
```

External repos can also push tag bumps via `repository_dispatch`:

```bash
gh api repos/OpenHistoricalMap/ohm-deploy/dispatches \
  -f event_type=bump-image \
  -F client_payload[service]=nominatim.ui \
  -F client_payload[tag]=$NEW_TAG
```

A workflow on this repo updates the tag in `k3s/values.<env>.template.yaml` and opens a PR.

## Cluster requirements

- Kubernetes >= 1.24 (k3s default ships Traefik v2/v3 with `traefik.io/v1alpha1` IngressRoute CRD).
- StorageClass `local-path` (k3s default) or override `global.storageClass`.
- For `osmcha-staticfiles` a `ReadWriteMany` PVC is required. On k3s use `nfs-subdir-external-provisioner` or `longhorn`. Single-node clusters can hack it with `local-path` + `accessModes: [ReadWriteOnce]` if all pods run on the same node — see workaround in `osmcha/pvc.yaml`.

## Migration from docker-compose

The `../hetzner/` folder remains as the source of truth during migration. Order:

1. Stand up k3s cluster on Hetzner.
2. Migrate `taginfo` first (simpler, single PVC).
3. Then `overpass`, `nominatim`, `osmcha`.
4. Finally `tiler` (currently disabled in values.yaml).
5. Decommission `../hetzner/` once all services pass smoke tests.
