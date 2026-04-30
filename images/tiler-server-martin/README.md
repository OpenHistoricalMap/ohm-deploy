# OHM Tiler Server (Martin)

Vector tile server for [OpenHistoricalMap](https://openhistoricalmap.org) using [Martin](https://github.com/maplibre/martin) with an Nginx reverse proxy for composite tile routing and caching.

## Architecture

The container runs two processes:

- **Martin** (port 3001) — serves vector tiles from PostgreSQL using function sources backed by materialized views at different zoom ranges.
- **Nginx** (port 80) — reverse proxy that handles composite tile routes, gzip compression, and tile caching.

```
Client -> Nginx (:80) -> Martin (:3001) -> PostgreSQL
```

## Configuration

Tile layers are defined in [`config/functions.json`](config/functions.json). Each function maps a layer name to materialized views at different zoom levels, allowing zoom-dependent data sources for performance optimization.

Nginx routes are auto-generated from `functions.json` by [`scripts/generate_nginx_conf.py`](scripts/generate_nginx_conf.py).

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `POSTGRES_HOST` | — | PostgreSQL host |
| `POSTGRES_USER` | — | PostgreSQL user |
| `POSTGRES_PASSWORD` | — | PostgreSQL password |
| `POSTGRES_DB` | — | PostgreSQL database |
| `POSTGRES_PORT` | — | PostgreSQL port |
| `MARTIN_INTERNAL_PORT` | `3001` | Internal Martin port |
| `MARTIN_WORKER_PROCESSES` | `8` | Martin worker processes |
| `MARTIN_POOL_SIZE` | `50` | Martin connection pool size |
| `NGINX_PORT` | `80` | Nginx listening port |
| `NGINX_GZIP` | `on` | Enable gzip compression |
| `NGINX_GZIP_COMP_LEVEL` | `4` | Gzip compression level (1-9) |

## Endpoints

### Composite tiles (all layers merged)

```
https://vtiles.openhistoricalmap.org/maps/ohm/{z}/{x}/{y}.pbf
https://vtiles.openhistoricalmap.org/maps/ohm/{z}/{x}/{y}
```

### Per-layer tiles

```
https://vtiles.openhistoricalmap.org/maps/ohm/{layer_name}/{z}/{x}/{y}.pbf
https://vtiles.openhistoricalmap.org/maps/ohm/{layer_name}/{z}/{x}/{y}
```

### Static data tiles

```
https://vtiles.openhistoricalmap.org/maps/ne/{z}/{x}/{y}.pbf
https://vtiles.openhistoricalmap.org/maps/ne/{z}/{x}/{y}
https://vtiles.openhistoricalmap.org/maps/osm_land/{z}/{x}/{y}.pbf
https://vtiles.openhistoricalmap.org/maps/osm_land/{z}/{x}/{y}
```

> The `.pbf` extension is optional and supported for backward compatibility with Tegola. Martin serves tiles natively without the extension.

## Tile Groups and Layers

### `ohm` — Main OHM layers

| Layer | Zoom Range |
|---|---|
| `land_ohm_lines` | z0–20 |
| `land_ohm_centroids` | z0–20 |
| `land_ohm_maritime` | z0–12 |
| `place_areas` | z14–20 |
| `place_points_centroids` | z0–20 |
| `water_areas` | z0–20 |
| `water_areas_centroids` | z8–20 |
| `water_lines` | z8–20 |
| `transport_areas` | z10–20 |
| `transport_lines` | z5–20 |
| `route_lines` | z5–20 |
| `transport_points_centroids` | z10–20 |
| `amenity_areas` | z14–20 |
| `amenity_points_centroids` | z14–20 |
| `buildings` | z14–20 |
| `buildings_points_centroids` | z14–20 |
| `landuse_areas` | z6–20 |
| `landuse_points_centroids` | z6–20 |
| `landuse_lines` | z14–20 |
| `other_areas` | z8–20 |
| `other_points_centroids` | z8–20 |
| `other_lines` | z14–20 |
| `communication_lines` | z10–20 |

### `ohm_admin` — Administrative boundaries

| Layer | Zoom Range |
|---|---|
| `boundaries` | z0–20 |

### `ohm_other_boundaries` — Non-admin boundaries

| Layer | Zoom Range |
|---|---|
| `non_admin_boundaries_areas` | z0–20 |
| `non_admin_boundaries_centroids` | z0–20 |

### `osm_land` — Land polygons (static)

| Layer | Zoom Range |
|---|---|
| `land_polygons` | z0–20 |

### `ne` — Natural Earth (static)

| Layer | Zoom Range |
|---|---|
| `ne_lakes` | z0–20 |