#!/usr/bin/env python3

"""
This script generates a merged TOML configuration file for a tile server.

It reads a TOML template and merges provider/map configurations from per-layer files.
For each layer SQL block, it detects the table/view name and dynamically replaces
the `{{LENGUAGES}}` placeholder with the actual list of `name_*` columns found in the database.

Requirements:
-------------
- PostgreSQL database with views and `name_*` columns
- DB credentials passed via environment variables:
    POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST, POSTGRES_PORT
"""

import os
import argparse
import re
from utils import get_db_connection

def fetch_all_languages() -> dict:
    """
    Fetch all 'name_*' columns from materialized views starting with 'mv_' (excluding 'mview_%').

    Returns:
        dict[str, str]: A dictionary where the key is the materialized view name
                        and the value is a comma-separated string of name_* columns.
    """
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
    """Indent every line of a block with the given string."""
    return "\n".join(indent + line for line in block.splitlines())


def process_layer_blocks(raw_content: str, lang_map: dict) -> str:
    """
    Process and replace `{{LENGUAGES}}` in each [[providers.layers]] block.
    """
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
    parser = argparse.ArgumentParser(description='Merge TOML providers and inject language columns.')
    parser.add_argument('--template', default='config/config.template.toml')
    parser.add_argument('--providers', default='config/providers')
    parser.add_argument('--output', default='config/config.osm.toml')
    parser.add_argument('--provider_names', required=True)

    args = parser.parse_args()

    with open(args.template, 'r') as f:
        template_content = f.read()

    requested_providers = [
        p.strip() for p in args.provider_names.split(',')
        if p.strip()
    ]

    all_toml_files = [f for f in os.listdir(args.providers) if f.endswith('.toml')]
    selected_files = [
        p if p.endswith('.toml') else p + '.toml'
        for p in requested_providers if p + '.toml' in all_toml_files
    ]

    lang_map = fetch_all_languages()

    providers_content = []
    maps_content = []

    for toml_file in selected_files:
        path = os.path.join(args.providers, toml_file)
        print(f"Processing {path}...")
        with open(path, 'r') as f:
            content = f.read()

        updated = process_layer_blocks(content, lang_map)

        if '#######Maps' in updated:
            p_block, m_block = updated.split('#######Maps', 1)
        else:
            p_block, m_block = updated, ""

        if p_block.strip():
            providers_content.append(p_block.strip())
        if m_block.strip():
            maps_content.append(m_block.strip())

    template_content = template_content.replace(
        "###### PROVIDERS",
        "###### PROVIDERS\n" + indent_block("\n\n".join(providers_content))
    )
    template_content = template_content.replace(
        "###### MAPS",
        "###### MAPS\n" + indent_block("\n\n".join(maps_content))
    )

    with open(args.output, 'w') as f:
        f.write(template_content)

    print(f"\nConfig created: {args.output}")