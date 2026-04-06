#!/usr/bin/env python3
"""
Generates nginx.conf from template + functions.json.

Reads group/function definitions and creates:
  - Composite routes: /maps/{group}/{z}/{x}/{y}.pbf -> all group functions in one tile
  - Per-layer routes: /maps/{group}/{layer}/{z}/{x}/{y}.pbf -> single function
"""

import json
import os

BASE_DIR = os.path.join(os.path.dirname(__file__), "..")
CONFIG_PATH = os.path.join(BASE_DIR, "config", "functions.json")
TEMPLATE_PATH = os.path.join(BASE_DIR, "config", "nginx.conf.template")
OUTPUT_PATH = os.path.join(BASE_DIR, "config", "nginx.conf")

# Zoom-based nginx cache TTLs for dynamic tiles.
# proxy_cache_valid doesn't accept variables, so we generate
# separate location blocks per zoom range.
ZOOM_RANGES = [
    {"label": "z0-2",   "regex": "[0-2]",                    "ttl": "48h"},
    {"label": "z3-5",   "regex": "[3-5]",                    "ttl": "24h"},
    {"label": "z6-7",   "regex": "[6-7]",                    "ttl": "16h"},
    {"label": "z8-9",   "regex": "[8-9]",                    "ttl": "12h"},
    {"label": "z10-12", "regex": "1[0-2]",                   "ttl": "8h"},
    {"label": "z13-15", "regex": "1[3-5]",                   "ttl": "4h"},
    {"label": "z16-20", "regex": "(?:1[6-9]|20)",            "ttl": "1h"},
]


def main():
    with open(CONFIG_PATH) as f:
        config = json.load(f)

    with open(TEMPLATE_PATH) as f:
        template = f.read()

    composite_routes = []
    perlayer_routes = []
    tilejson_routes = []

    for group in config["groups"]:
        group_name = group["name"]
        fn_names = [fn["function_name"] for fn in group["functions"]]
        is_static = group.get("static", False)
        cache_ttl = "365d" if is_static else "30d"
        cache_zone = "static_tiles" if is_static else "tiles"

        if not fn_names:
            continue

        # TileJSON: /capabilities/{group}.json (Tegola-compatible) + /maps/{group}.json
        for prefix in ("capabilities", "maps"):
            tilejson_routes.append(
                f"        # TileJSON: /{prefix}/{group_name}.json\n"
                f"        location = /{prefix}/{group_name}.json {{\n"
                f"            default_type application/json;\n"
                f"            alias /app/tilejson/{group_name}.json;\n"
                f"            add_header Cache-Control \"no-cache\";\n"
                f"            add_header Access-Control-Allow-Origin \"*\";\n"
                f"        }}"
            )

        # TileJSON: /capabilities/{group}/{layer}.json + /maps/{group}/{layer}.json
        for fn_name in fn_names:
            for prefix in ("capabilities", "maps"):
                tilejson_routes.append(
                    f"        # TileJSON: /{prefix}/{group_name}/{fn_name}.json\n"
                    f"        location = /{prefix}/{group_name}/{fn_name}.json {{\n"
                    f"            default_type application/json;\n"
                    f"            alias /app/tilejson/{fn_name}.json;\n"
                    f"            add_header Cache-Control \"no-cache\";\n"
                    f"            add_header Access-Control-Allow-Origin \"*\";\n"
                    f"        }}"
                )

        # Composite: /maps/{group}/{z}/{x}/{y}.pbf -> Martin composite source
        composite_src = ",".join(fn_names)

        if is_static:
            # Static groups: single block, 365d cache, immutable
            composite_routes.append(
                f"        # Composite: /maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf (static)\n"
                f"        location ~ ^/maps/{group_name}/(\\d+/\\d+/\\d+)\\.pbf$ {{\n"
                f"            proxy_cache {cache_zone};\n"
                f"            proxy_cache_valid 200 365d;\n"
                f"            proxy_cache_valid 204 1m;\n"
                f"            proxy_cache_key $uri;\n"
                f"            proxy_cache_lock on;\n"
                f"            proxy_cache_use_stale error timeout updating;\n"
                f"            proxy_cache_background_update on;\n"
                f"            add_header X-Cache-Status $upstream_cache_status;\n"
                f"            add_header Cache-Control \"public, max-age=31536000\";\n"
                f"            add_header Access-Control-Allow-Origin \"*\";\n"
                f"            proxy_set_header Host $http_host;\n"
                f"            proxy_pass http://martin/{composite_src}/$1;\n"
                f"        }}"
            )
            perlayer_routes.append(
                f"        # Per-layer: /maps/{group_name}/{{layer}}/{{z}}/{{x}}/{{y}}.pbf (static)\n"
                f"        location ~ ^/maps/{group_name}/([^/]+)/(\\d+/\\d+/\\d+)\\.pbf$ {{\n"
                f"            proxy_cache {cache_zone};\n"
                f"            proxy_cache_valid 200 365d;\n"
                f"            proxy_cache_valid 204 1m;\n"
                f"            proxy_cache_key $uri;\n"
                f"            proxy_cache_lock on;\n"
                f"            proxy_cache_use_stale error timeout updating;\n"
                f"            proxy_cache_background_update on;\n"
                f"            add_header X-Cache-Status $upstream_cache_status;\n"
                f"            add_header Cache-Control \"public, max-age=31536000\";\n"
                f"            add_header Access-Control-Allow-Origin \"*\";\n"
                f"            proxy_set_header Host $http_host;\n"
                f"            proxy_pass http://martin/$1/$2;\n"
                f"        }}"
            )
        else:
            # Dynamic groups: one location block per zoom range
            for zr in ZOOM_RANGES:
                composite_routes.append(
                    f"        # Composite: /maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf ({zr['label']}, cache={zr['ttl']})\n"
                    f"        location ~ ^/maps/{group_name}/({zr['regex']})/([0-9]+)/([0-9]+)\\.pbf$ {{\n"
                    f"            proxy_cache {cache_zone};\n"
                    f"            proxy_cache_valid 200 {zr['ttl']};\n"
                    f"            proxy_cache_valid 204 1m;\n"
                    f"            proxy_cache_key $uri;\n"
                    f"            proxy_cache_lock on;\n"
                    f"            proxy_cache_use_stale error timeout updating;\n"
                    f"            proxy_cache_background_update on;\n"
                    f"            add_header X-Cache-Status $upstream_cache_status;\n"
                    f"            add_header Cache-Control \"no-cache\";\n"
                    f"            add_header Access-Control-Allow-Origin \"*\";\n"
                    f"            proxy_set_header Host $http_host;\n"
                    f"            proxy_pass http://martin/{composite_src}/$1/$2/$3;\n"
                    f"        }}"
                )
                perlayer_routes.append(
                    f"        # Per-layer: /maps/{group_name}/{{layer}}/{{z}}/{{x}}/{{y}}.pbf ({zr['label']}, cache={zr['ttl']})\n"
                    f"        location ~ ^/maps/{group_name}/([^/]+)/({zr['regex']})/([0-9]+)/([0-9]+)\\.pbf$ {{\n"
                    f"            proxy_cache {cache_zone};\n"
                    f"            proxy_cache_valid 200 {zr['ttl']};\n"
                    f"            proxy_cache_valid 204 1m;\n"
                    f"            proxy_cache_key $uri;\n"
                    f"            proxy_cache_lock on;\n"
                    f"            proxy_cache_use_stale error timeout updating;\n"
                    f"            proxy_cache_background_update on;\n"
                    f"            add_header X-Cache-Status $upstream_cache_status;\n"
                    f"            add_header Cache-Control \"no-cache\";\n"
                    f"            add_header Access-Control-Allow-Origin \"*\";\n"
                    f"            proxy_set_header Host $http_host;\n"
                    f"            proxy_pass http://martin/$1/$2/$3/$4;\n"
                    f"        }}"
                )

        static_label = " (static, cache=365d)" if is_static else ""
        print(f"  {group_name}: composite={len(fn_names)} functions -> /maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf{static_label}")

    nginx_conf = template.replace(
        "##TILEJSON_ROUTES##", "\n\n".join(tilejson_routes)
    ).replace(
        "##COMPOSITE_ROUTES##", "\n\n".join(composite_routes)
    ).replace(
        "##PERLAYER_ROUTES##", "\n\n".join(perlayer_routes)
    )

    # Substitute environment variables (${VAR_NAME})
    import re
    def env_replace(m):
        return os.environ.get(m.group(1), m.group(0))
    nginx_conf = re.sub(r'\$\{(\w+)\}', env_replace, nginx_conf)

    with open(OUTPUT_PATH, "w") as f:
        f.write(nginx_conf)

    print(f"  Written to {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
