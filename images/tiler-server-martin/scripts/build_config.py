#!/usr/bin/env python3
"""
Generates Martin tile server configuration by:
1. Discovering materialized views from PostgreSQL
2. Generating Martin YAML config with table sources + zoom ranges
3. Generating composite layer mapping for zoom-level routing

Each materialized view becomes a table source with minzoom/maxzoom
derived from the view naming convention (e.g. mv_water_lines_z8_9).

Composite layers group multiple MVs into a single logical layer,
so clients can request e.g. /water_lines/{z}/{x}/{y} and Martin
returns data from the correct MV for that zoom level.
"""

import os
import re
import json
import psycopg2
from urllib.parse import quote
from collections import OrderedDict


def get_connection():
    return psycopg2.connect(
        host=os.environ["POSTGRES_HOST"],
        port=os.environ.get("POSTGRES_PORT", "5432"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )


def parse_zoom_range(view_name):
    """Extract min/max zoom from view name pattern like _z8_9 or _z5."""
    match = re.search(r"_z(\d+)_(\d+)(?:_v\d+)?$", view_name)
    if match:
        return int(match.group(1)), int(match.group(2))
    match = re.search(r"_z(\d+)(?:_v\d+)?$", view_name)
    if match:
        z = int(match.group(1))
        return z, z
    return 0, 22


def discover_views(conn):
    """Get all materialized views with geometry info."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT f_table_name, f_geometry_column, srid
            FROM geometry_columns
            WHERE f_table_schema = 'public'
              AND (f_table_name LIKE 'mv\\_%' OR f_table_name LIKE 'mview\\_%')
            ORDER BY f_table_name;
        """)
        return cur.fetchall()


def detect_id_column(conn, view_name):
    """Detect the best ID column for a view using pg_attribute."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT a.attname
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname = %s
              AND a.attname IN ('osm_id', 'id', 'ogc_fid')
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY
                CASE a.attname
                    WHEN 'osm_id' THEN 1
                    WHEN 'id' THEN 2
                    WHEN 'ogc_fid' THEN 3
                END
            LIMIT 1;
        """, (view_name,))
        row = cur.fetchone()
        return row[0] if row else None


PG_TYPE_MAP = {
    "int2": "number", "int4": "number", "int8": "number",
    "float4": "number", "float8": "number", "numeric": "number",
    "bool": "boolean",
    "text": "string", "varchar": "string", "bpchar": "string",
    "name": "string", "uuid": "string",
    "json": "string", "jsonb": "string",
    "date": "string", "timestamp": "string", "timestamptz": "string",
    "hstore": "string",
}


def get_view_columns(conn, view_name, geom_col, id_col):
    """Discover non-geometry columns from a materialized view via pg_attribute."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT a.attname, t.typname
            FROM pg_attribute a
            JOIN pg_class c ON c.oid = a.attrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN pg_type t ON t.oid = a.atttypid
            WHERE n.nspname = 'public'
              AND c.relname = %s
              AND a.attnum > 0
              AND NOT a.attisdropped
            ORDER BY a.attnum;
        """, (view_name,))
        skip = {geom_col, id_col, "tags"} if id_col else {geom_col, "tags"}
        columns = OrderedDict()
        for attname, typname in cur.fetchall():
            if attname in skip:
                continue
            # Skip geometry/geography types
            if typname in ("geometry", "geography"):
                continue
            columns[attname] = PG_TYPE_MAP.get(typname, "string")
        return columns


def extract_layer_name(view_name):
    """Extract the logical layer name from a materialized view name.

    e.g. mv_water_lines_z8_9 -> water_lines
         mview_ne_lakes_z0_5  -> ne_lakes
    """
    # Strip prefix
    if view_name.startswith("mview_"):
        name = view_name[len("mview_"):]
    elif view_name.startswith("mv_"):
        name = view_name[len("mv_"):]
    else:
        name = view_name
    # Strip zoom suffix like _z8_9 or _z5 or _z8_9_v2
    name = re.sub(r"_z\d+(?:_\d+)?(?:_v\d+)?$", "", name)
    return name


def generate_yaml(port, conn_str, pool_size, workers, table_sources):
    """Generate Martin YAML config with table sources."""
    lines = [
        f"listen_addresses: '0.0.0.0:{port}'",
        f"worker_processes: {workers}",
        "",
        "postgres:",
        f"  connection_string: '{conn_str}'",
        f"  pool_size: {pool_size}",
        "  default_srid: 3857",
        "  auto_publish:",
        "    tables: false",
        "    functions: false",
        "  tables:",
    ]

    for name, src in table_sources.items():
        lines.append(f"    {name}:")
        lines.append(f"      schema: public")
        lines.append(f"      table: {src['table']}")
        lines.append(f"      srid: {src['srid']}")
        lines.append(f"      geometry_column: {src['geometry_column']}")
        if src.get("id_column"):
            lines.append(f"      id_column: {src['id_column']}")
        else:
            lines.append("      id_column: ~")
        lines.append(f"      minzoom: {src['minzoom']}")
        lines.append(f"      maxzoom: {src['maxzoom']}")
        lines.append("      bounds: [-180.0, -85.0511, 180.0, 85.0511]")
        lines.append("      extent: 4096")
        lines.append("      buffer: 64")
        lines.append("      clip_geom: true")
        if src.get("properties"):
            lines.append("      properties:")
            for col_name, col_type in src["properties"].items():
                lines.append(f"        {col_name}: {col_type}")

    return "\n".join(lines) + "\n"


LAYER_GROUPS_PATH = "/app/config/layer_groups.json"


def load_layer_groups():
    """Load layer group mapping from JSON config file."""
    with open(LAYER_GROUPS_PATH) as f:
        return json.load(f)


def _location_block(lines, pattern, composite_url, cache_ttl=None):
    """Append a location block with optional caching."""
    lines.append(f"        location ~ {pattern} {{")
    lines.append(f"            proxy_set_header Host $http_host;")
    if cache_ttl:
        lines.append(f"            proxy_cache tile_cache;")
        lines.append(f"            proxy_cache_valid 200 204 {cache_ttl};")
        lines.append(f"            add_header X-Cache-Status $upstream_cache_status;")
    lines.append(f"            proxy_pass http://martin/{composite_url};")
    lines.append( "        }")


def generate_nginx_conf(nginx_port, martin_port, composite_mapping, layer_groups):
    """Generate nginx.conf with Tegola-compatible /maps/{group}/{layer} routes."""
    # Check if any group uses caching
    has_cache = any(g.get("cache") for g in layer_groups.values())

    lines = [
        "worker_processes auto;",
        "error_log /var/log/nginx/error.log warn;",
        "pid /run/nginx/nginx.pid;",
        "",
        "events {",
        "    worker_connections 1024;",
        "}",
        "",
        "http {",
        "    include /etc/nginx/mime.types;",
        "    default_type application/octet-stream;",
        "    access_log off;",
        "    sendfile on;",
        "    keepalive_timeout 65;",
    ]

    if has_cache:
        lines.append("")
        lines.append("    # Tile cache: 1GB disk, keys in 10MB shared memory")
        lines.append("    proxy_cache_path /tmp/nginx_tile_cache levels=1:2")
        lines.append("        keys_zone=tile_cache:10m max_size=1g inactive=30d;")
        lines.append("    proxy_cache_key $request_uri;")

    lines.extend([
        "",
        "    upstream martin {",
        f"        server 127.0.0.1:{martin_port};",
        "        keepalive 32;",
        "    }",
        "",
        f"    server {{",
        f"        listen {nginx_port};",
        "",
        "        # Pass catalog and health endpoints directly",
        "        location /catalog {",
        "            proxy_set_header Host $http_host;",
        "            proxy_pass http://martin;",
        "        }",
        "",
        "        location /health {",
        "            proxy_set_header Host $http_host;",
        "            proxy_pass http://martin;",
        "        }",
        "",
        "        # Viewer and config files",
        "        location = / {",
        "            default_type text/html;",
        "            root /app/static;",
        "            try_files /index.html =404;",
        "        }",
        "        location /config/ {",
        "            alias /app/config/;",
        "        }",
        "",
    ])

    # Generate /maps/{group}/{layer} routes (Tegola-compatible)
    for group_name, group_cfg in layer_groups.items():
        layer_map = group_cfg.get("layers", group_cfg)
        cache_ttl = group_cfg.get("cache")
        cache_label = f" [cache={cache_ttl}]" if cache_ttl else ""
        lines.append(f"        # ===== Group: {group_name}{cache_label} =====")

        if isinstance(layer_map, str):
            continue
        for tegola_name, composite_name in layer_map.items():
            if composite_name not in composite_mapping:
                lines.append(f"        # SKIP {tegola_name} -> {composite_name} (not found)")
                continue
            composite_url = composite_mapping[composite_name]["composite_url"]
            lines.append(f"        # {tegola_name} -> {composite_name}")
            _location_block(lines,
                f"^/maps/{group_name}/{tegola_name}(/\\d+/\\d+/\\d+)\\.pbf$",
                f"{composite_url}$1", cache_ttl)
            _location_block(lines,
                f"^/maps/{group_name}/{tegola_name}(/.*)?$",
                f"{composite_url}$1", cache_ttl)
            lines.append("")

    # Also keep direct /{layer} access for convenience
    lines.append("        # ===== Direct layer access =====")
    for layer_name, info in composite_mapping.items():
        composite_url = info["composite_url"]
        _location_block(lines,
            f"^/{layer_name}(/\\d+/\\d+/\\d+)\\.pbf$",
            f"{composite_url}$1")
        _location_block(lines,
            f"^/{layer_name}(/.*)?$",
            f"{composite_url}$1")

    # Fallback: pass any other request directly to Martin
    lines.append("")
    lines.append("        # Fallback: pass directly to Martin")
    lines.append("        location / {")
    lines.append("            proxy_set_header Host $http_host;")
    lines.append("            proxy_pass http://martin;")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")

    return "\n".join(lines)


def main():
    conn = get_connection()

    views = discover_views(conn)
    print(f"Discovered {len(views)} materialized views with geometry")

    table_sources = OrderedDict()
    composite_layers = OrderedDict()

    for view_name, geom_col, srid in views:
        id_col = detect_id_column(conn, view_name)
        minzoom, maxzoom = parse_zoom_range(view_name)
        properties = get_view_columns(conn, view_name, geom_col, id_col)

        table_sources[view_name] = {
            "table": view_name,
            "srid": srid if srid else 3857,
            "geometry_column": geom_col,
            "id_column": id_col,
            "minzoom": minzoom,
            "maxzoom": maxzoom,
            "properties": properties,
        }
        print(f"  {view_name}: z{minzoom}-{maxzoom} (id={id_col or '~'}, geom={geom_col}, cols={len(properties)})")

        # Group into composite layers
        layer_name = extract_layer_name(view_name)
        if layer_name not in composite_layers:
            composite_layers[layer_name] = []
        composite_layers[layer_name].append({
            "source": view_name,
            "minzoom": minzoom,
            "maxzoom": maxzoom,
        })

    # Build connection string
    password = quote(os.environ["POSTGRES_PASSWORD"], safe="")
    conn_str = (
        f"postgresql://{os.environ['POSTGRES_USER']}:{password}"
        f"@{os.environ['POSTGRES_HOST']}:{os.environ.get('POSTGRES_PORT', '5432')}"
        f"/{os.environ['POSTGRES_DB']}"
    )

    nginx_port = os.environ.get("NGINX_PORT", "80")
    martin_port = os.environ.get("MARTIN_INTERNAL_PORT", "3001")

    yaml_content = generate_yaml(
        port=martin_port,
        conn_str=conn_str,
        pool_size=int(os.environ.get("MARTIN_POOL_SIZE", "20")),
        workers=int(os.environ.get("MARTIN_WORKER_PROCESSES", "8")),
        table_sources=table_sources,
    )

    output = "/app/config/config.yaml"
    os.makedirs(os.path.dirname(output), exist_ok=True)
    with open(output, "w") as f:
        f.write(yaml_content)

    print(f"\nConfig written to {output}")
    print(f"Table sources: {len(table_sources)}")

    # Build composite layers mapping
    # Each layer maps to a comma-separated list of sources for Martin composite URL
    composite_mapping = OrderedDict()
    for layer_name, sources in composite_layers.items():
        sources_sorted = sorted(sources, key=lambda s: s["minzoom"])
        composite_mapping[layer_name] = {
            "sources": [s["source"] for s in sources_sorted],
            "composite_url": ",".join(s["source"] for s in sources_sorted),
            "zoom_ranges": [
                {"source": s["source"], "minzoom": s["minzoom"], "maxzoom": s["maxzoom"]}
                for s in sources_sorted
            ],
        }

    composite_output = "/app/config/composite_layers.json"
    with open(composite_output, "w") as f:
        json.dump(composite_mapping, f, indent=2)

    print(f"Composite layers: {len(composite_mapping)}")
    print(f"Composite mapping written to {composite_output}")

    # Load layer groups and generate Nginx config
    layer_groups = load_layer_groups()
    print(f"Layer groups: {list(layer_groups.keys())}")
    nginx_conf = generate_nginx_conf(nginx_port, martin_port, composite_mapping, layer_groups)
    nginx_output = "/app/config/nginx.conf"
    with open(nginx_output, "w") as f:
        f.write(nginx_conf)

    print(f"Nginx config written to {nginx_output}")
    print(f"\nNginx listening on :{nginx_port} → Martin on :{martin_port}")
    print("\nClean layer URLs:")
    for layer_name in list(composite_mapping.keys())[:5]:
        print(f"  /{layer_name}/{{z}}/{{x}}/{{y}}")

    conn.close()


if __name__ == "__main__":
    main()
