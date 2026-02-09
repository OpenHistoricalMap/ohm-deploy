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


def main():
    with open(CONFIG_PATH) as f:
        config = json.load(f)

    with open(TEMPLATE_PATH) as f:
        template = f.read()

    composite_routes = []
    perlayer_routes = []

    for group in config["groups"]:
        group_name = group["name"]
        fn_names = [fn["function_name"] for fn in group["functions"]]

        if not fn_names:
            continue

        # Composite: /maps/{group}/{z}/{x}/{y}.pbf -> Martin composite source
        composite_src = ",".join(fn_names)
        composite_routes.append(
            f"        # Composite: /maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf\n"
            f"        location ~ ^/maps/{group_name}/(\\d+/\\d+/\\d+)\\.pbf$ {{\n"
            f"            proxy_set_header Host $http_host;\n"
            f"            proxy_pass http://martin/{composite_src}/$1;\n"
            f"        }}"
        )

        # Per-layer: /maps/{group}/{layer}/{z}/{x}/{y}.pbf
        perlayer_routes.append(
            f"        # Per-layer: /maps/{group_name}/{{layer}}/{{z}}/{{x}}/{{y}}.pbf\n"
            f"        location ~ ^/maps/{group_name}/([^/]+)(\\d+/\\d+/\\d+)\\.pbf$ {{\n"
            f"            proxy_set_header Host $http_host;\n"
            f"            proxy_pass http://martin/$1/$2;\n"
            f"        }}\n"
            f"        location ~ ^/maps/{group_name}/([^/]+)(/.*)$ {{\n"
            f"            proxy_set_header Host $http_host;\n"
            f"            proxy_pass http://martin/$1$2;\n"
            f"        }}"
        )

        print(f"  {group_name}: composite={len(fn_names)} functions -> /maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf")

    nginx_conf = template.replace(
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
