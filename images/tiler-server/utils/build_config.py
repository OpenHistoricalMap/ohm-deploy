#!/usr/bin/env python3

"""
This script generates a merged TOML configuration file for a tile server.
It reads a template file and inserts provider and map configurations from individual TOML files.
Additionally, it fetches dynamic language tag columns from a PostgreSQL database (using the `languages` table),
which replaces placeholder values (like {{LENGUAGES}}) inside the provider definitions.


Requirements:
-------------
- PostgreSQL database with a populated `languages` table.
- Environment variables for DB connection:
    POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_HOST, POSTGRES_PORT
"""

import psycopg2
import os
import argparse

def fetch_languages_from_db():
    """
    Fetch only the 'alias' values from the 'languages' table in the PostgreSQL database.
    Returns:
        str: A newline-separated string of aliases sorted alphabetically.
    """
    conn = psycopg2.connect(
        dbname=os.getenv("POSTGRES_DB", "gis"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD", "password"),
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432")
    )
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT alias FROM languages ORDER BY alias;")
            return ", ".join(row[0] for row in cur.fetchall())
    finally:
        conn.close()

def indent_block(block: str, indent: str = "\t") -> str:
    lines = block.splitlines()
    return "\n".join(indent + line for line in lines)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Merge TOML files into a configuration file.')
    parser.add_argument('--template', default='config/config.template.toml')
    parser.add_argument('--providers', default='config/providers')
    parser.add_argument('--output', default='config/config.osm.toml')
    parser.add_argument('--provider_names', required=True)

    args = parser.parse_args()

    template_file = args.template
    providers_dir = args.providers
    output_file = args.output
    requested_providers = [p.strip() for p in args.provider_names.split(',')]

    # Load and process template
    with open(template_file, 'r') as f:
        template_content = f.read()

    # Get language SQL from database
    languages_content = fetch_languages_from_db()

    # Collect TOML providers
    all_toml_files = [f for f in os.listdir(providers_dir) if f.endswith('.toml')]
    selected_toml_files = []
    for rp in requested_providers:
        expected_name = rp if rp.endswith('.toml') else rp + '.toml'
        if expected_name in all_toml_files:
            selected_toml_files.append(expected_name)
        else:
            print(f"WARNING: {expected_name} not found in {providers_dir}. Skipping.")

    providers_accumulator = []
    maps_accumulator = []

    for toml_filename in selected_toml_files:
        full_path = os.path.join(providers_dir, toml_filename)
        print("Importing ->", full_path)
        with open(full_path, 'r') as f:
            raw_content = f.read()

        if '{{LENGUAGES}}' in raw_content:
            raw_content = raw_content.replace('{{LENGUAGES}}', languages_content.replace("\n", " "))
        if '{{LENGUAGES_RELATION}}' in raw_content:
            replaced_lines = "r." + languages_content.replace("\n", " r.")
            raw_content = raw_content.replace('{{LENGUAGES_RELATION}}', replaced_lines)

        if '#######Maps' in raw_content:
            provider_part, maps_part = raw_content.split('#######Maps', 1)
        else:
            provider_part, maps_part = raw_content, ""

        if provider_part.strip():
            providers_accumulator.append(provider_part.strip())
        if maps_part.strip():
            maps_accumulator.append(maps_part.strip())

    # Insert into template
    template_content = template_content.replace(
        "###### PROVIDERS",
        "###### PROVIDERS\n" + indent_block("\n\n".join(providers_accumulator), "\t")
    )

    template_content = template_content.replace(
        "###### MAPS",
        "###### MAPS\n" + indent_block("\n\n".join(maps_accumulator), "\t")
    )

    with open(output_file, 'w') as f:
        f.write(template_content)

    print(f"Successfully created merged configuration at: {output_file}")
    