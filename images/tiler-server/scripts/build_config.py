#!/usr/bin/env python3
"""
Generates a TOML configuration file by merging a template and provider files.

- Supports grouping providers into different markers using dictionaries.
- Template path, providers directory, and output path can be passed as arguments or use defaults.
"""

import os
import re
import argparse
from collections import defaultdict
from utils import get_db_connection


def fetch_all_languages() -> dict:
    """Fetches name_* columns from all materialized views mv_* (except mview_*)."""
    conn = get_db_connection()
    result = {}
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                  c.relname AS mview_name,
                  string_agg(a.attname, ', ' ORDER BY a.attname) AS name_columns
                FROM
                  pg_class c
                JOIN
                  pg_namespace n ON n.oid = c.relnamespace
                JOIN
                  pg_attribute a ON a.attrelid = c.oid
                WHERE
                  c.relkind = 'm'
                  AND c.relname LIKE 'mv_%'
                  AND c.relname NOT LIKE 'mview_%'
                  AND a.attname LIKE 'name_%'
                  AND NOT a.attisdropped
                GROUP BY
                  c.relname
                ORDER BY
                  c.relname;
            """)
            for view_name, name_columns in cur.fetchall():
                result[view_name] = name_columns
    finally:
        conn.close()
    return result


def indent_block(block: str, indent: str = "\t") -> str:
    """Indents every line in a block with the given indent string."""
    return "\n".join(indent + line for line in block.splitlines())


def process_layer_blocks(raw_content: str, lang_map: dict) -> str:
    """Replaces {{LENGUAGES}} in each [[providers.layers]] block."""
    parts = re.split(r'(\[\[providers\.layers\]\])', raw_content)
    final = []
    for i in range(1, len(parts), 2):
        header = parts[i]
        block = parts[i + 1] if i + 1 < len(parts) else ''
        sql_match = re.search(r'FROM\s+([\w_]+)', block)
        if sql_match:
            view_name = sql_match.group(1)
            langs = lang_map.get(view_name)
            if langs:
                block = block.replace('{{LENGUAGES}}', langs)
            else:
                block = re.sub(r',?\s*{{LENGUAGES}}\s*', '', block)
        else:
            block = block.replace('{{LENGUAGES}}', '')
        final.append(header + block)
    return ''.join(parts[0:1] + final)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Generates config.toml by merging template and providers.')
    parser.add_argument('--template', default="/app/config/config.template.toml", help='TOML template file')
    parser.add_argument('--providers', default="/app/config/providers", help='Directory containing provider TOML files')
    parser.add_argument('--output', default="/app/config/config.toml", help='Output TOML file')

    args = parser.parse_args()

    TEMPLATE_FILE = args.template
    PROVIDERS_DIR = args.providers
    OUTPUT_FILE = args.output

    # Group definitions with their associated markers
    provider_osm = {
        "provider_marker": "###### PROVIDERS_OSM",
        "map_marker": "###### MAPS_OSM",
        "providers": [
            "admin_boundaries_lines",
            "admin_boundaries_centroids",
            "admin_boundaries_maritime",
            "place_areas",
            "place_points_centroids",
            "water_areas",
            "water_areas_centroids",
            "water_lines",
            "transport_areas",
            "transport_lines",
            "route_lines",
            "transport_points_centroids",
            "amenity_areas",
            "amenity_points_centroids",
            "buildings_areas",
            "buildings_points_centroids",
            "landuse_areas",
            "landuse_points_centroids",
            "landuse_lines",
            "other_areas",
            "other_points_centroids",
            "other_lines"
        ]
    }

    provider_ohm_admin_boundary = {
        "provider_marker": "###### PROVIDERS_ADMIN_BOUNDARIES_AREAS",
        "map_marker": "###### MAPS_ADMIN_BOUNDARIES_AREAS",
        "providers": [
            "admin_boundaries_polygon"
        ]
    }

    groups = [provider_osm, provider_ohm_admin_boundary]

    with open(TEMPLATE_FILE, 'r') as f:
        template_content = f.read()

    lang_map = fetch_all_languages()
    marker_blocks = defaultdict(list)

    # Process each provider file and split into provider/map sections
    for group in groups:
        for provider_name in group["providers"]:
            toml_file = provider_name + ".toml"
            path = os.path.join(PROVIDERS_DIR, toml_file)

            if not os.path.exists(path):
                print(f"File not found: {toml_file}, skipping.")
                continue

            print(f"Processing {toml_file}...")
            with open(path, 'r') as f:
                content = f.read()

            updated = process_layer_blocks(content, lang_map)

            if '#######Maps' in updated:
                p_block, m_block = updated.split('#######Maps', 1)
            else:
                p_block, m_block = updated, ""

            if p_block.strip():
                marker_blocks[group["provider_marker"]].append(p_block.strip())
            if m_block.strip():
                marker_blocks[group["map_marker"]].append(m_block.strip())

    # Replace markers in the template with indented merged blocks
    for marker, blocks in marker_blocks.items():
        joined_block = indent_block("\n\n".join(blocks))
        template_content = template_content.replace(marker, "\n" + joined_block)

    with open(OUTPUT_FILE, 'w') as f:
        f.write(template_content)

    print(f"Config file created: {OUTPUT_FILE}")
