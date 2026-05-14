# OHM Overpass API

OpenHistoricalMap-specific Overpass API image built from source.

This image **builds Overpass from the upstream tarball** at
[`dev.overpass-api.de/releases`](http://dev.overpass-api.de/releases) and
applies OHM-specific patches before compiling. The runtime layout mirrors
[`wiktorn/Overpass-API`](https://github.com/wiktorn/Overpass-API) so the rest
of the OHM stack (envs, init scripts, supervisor config, nginx template) stays
compatible.

## Build

```sh
docker build -t openhistoricalmap/overpass-api:latest \
    --build-arg OVERPASS_VERSION=0.7.62.11 \
    --build-arg WIKTORN_TAG=v0.7.62.9 \
    ./images/overpass-api
```

`OVERPASS_VERSION` controls the source tarball (must match a release in
`dev.overpass-api.de/releases`). `WIKTORN_TAG` controls which wiktorn image we
borrow helper scripts and the Python venv from.

## OHM patches applied

### Issue [#558](https://github.com/OpenHistoricalMap/issues/issues/558) — Copyright string

The upstream binary emits a hardcoded ODbL / `www.openstreetmap.org` notice in
every JSON, XML, and HTML response. The Dockerfile patches three source files
with `sed` before `make`:

| File | Lines |
| --- | --- |
| `src/overpass_api/frontend/basic_formats.cc` | 64–65 |
| `src/overpass_api/output_formats/output_json.cc` | 46–47 |
| `src/overpass_api/output_formats/output_xml.cc` | 38–39 |

Replacements:

- `www.openstreetmap.org` → `www.openhistoricalmap.org`
- `made available under ODbL` → `made available under CC0`

Tracked upstream as
[`drolbr/Overpass-API#721`](https://github.com/drolbr/Overpass-API/issues/721).

## Configuration

Same envs as `osm-seed/images/overpass-api`. See
[`envs/.env.overpass.example`](../../envs/.env.overpass.example).

## Run

```sh
docker-compose run overpass-api
```
