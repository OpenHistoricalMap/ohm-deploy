#!/usr/bin/env python3
"""
Generates and executes Martin SQL tile functions, and produces TileJSON manifests.

Reads function definitions from config/functions.json, connects to PostgreSQL,
reads column names from materialized views, and creates PL/pgSQL functions
with hardcoded columns (no dynamic SQL at runtime).

Also generates static TileJSON files (per-function and per-group composite)
with full vector_layers and field metadata, since Martin cannot introspect
function sources for field information.

Usage: python3 generate_functions.py
  Requires env vars: POSTGRES_HOST, POSTGRES_PORT, POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
  Optional env vars: MARTIN_BASE_URL (default: "")
"""

import json
import os
import psycopg2

BASE_DIR = os.path.join(os.path.dirname(__file__), "..")
CONFIG_PATH = os.path.join(BASE_DIR, "config", "functions.json")
OUTPUT_DIR = os.path.join(BASE_DIR, "pg_functions")
TILEJSON_DIR = os.path.join(BASE_DIR, "tilejson")


def load_config():
    """Load function definitions from functions.json."""
    with open(CONFIG_PATH) as f:
        return json.load(f)


ALWAYS_EXCLUDE = ["source", "id", "source_type"]


PG_TYPE_MAP = {
    "int2": "Number", "int4": "Number", "int8": "Number",
    "float4": "Number", "float8": "Number", "numeric": "Number",
    "bool": "Boolean",
}


def get_columns(cur, table_name, exclude):
    """Get column names from a table/mview, excluding specified columns."""
    exclude = list(exclude) + ALWAYS_EXCLUDE
    cur.execute("""
        SELECT attname
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
          AND c.relname = %s
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND attname != ALL(%s)
        ORDER BY a.attnum
    """, (table_name, exclude))
    cols = [row[0] for row in cur.fetchall()]
    if not cols:
        print(f"  WARNING: No columns found for {table_name}")
    return cols


def get_columns_with_types(cur, table_name, exclude):
    """Get column names and TileJSON-compatible types from a table/mview."""
    exclude = list(exclude) + ALWAYS_EXCLUDE
    cur.execute("""
        SELECT a.attname, t.typname
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        JOIN pg_type t ON a.atttypid = t.oid
        WHERE n.nspname = 'public'
          AND c.relname = %s
          AND a.attnum > 0
          AND NOT a.attisdropped
          AND a.attname != ALL(%s)
        ORDER BY a.attnum
    """, (table_name, exclude))
    fields = {}
    for col_name, pg_type in cur.fetchall():
        fields[col_name] = PG_TYPE_MAP.get(pg_type, "String")
    return fields


def get_mvt_geom_params(max_zoom):
    """Return ST_AsMVTGeom extent and buffer based on zoom level.

    Lower zoom = less detail needed = smaller tiles.
    """
    if max_zoom is not None and max_zoom <= 5:
        return 1024, 64
    elif max_zoom is not None and max_zoom <= 9:
        return 2048, 128
    else:
        return 4096, 256


def generate_function_sql(func_def, columns_per_table):
    """Generate the CREATE FUNCTION SQL with hardcoded columns."""
    fn = func_def["function_name"]
    sl = func_def["source_layer"]
    zoom_mapping = func_def["zoom_mapping"]
    min_zoom = func_def.get("min_zoom")
    geom_col = func_def.get("geometry_column", "geometry")

    # Build the IF/ELSIF/ELSE blocks
    blocks = []
    for i, (max_zoom, table_name) in enumerate(zoom_mapping):
        cols = columns_per_table[table_name]
        col_list = ", ".join(f"t.{c}" for c in cols)
        extent, buffer = get_mvt_geom_params(max_zoom)

        query = (
            f"SELECT ST_AsMVT(q, '{sl}', {extent}) INTO mvt FROM (\n"
            f"            SELECT {col_list},\n"
            f"                   ST_AsMVTGeom(t.{geom_col}, bounds, {extent}, {buffer}, true) AS geometry\n"
            f"            FROM public.{table_name} t\n"
            f"            WHERE t.{geom_col} && bounds\n"
            f"        ) q;"
        )

        if i == 0 and max_zoom is not None:
            blocks.append(f"    IF z <= {max_zoom} THEN\n        {query}")
        elif max_zoom is None:
            if i == 0:
                # Single table, no IF needed
                blocks.append(f"    {query}")
            else:
                blocks.append(f"    ELSE\n        {query}")
        else:
            blocks.append(f"    ELSIF z <= {max_zoom} THEN\n        {query}")

    body = "\n".join(blocks)

    # Only add END IF when there are multiple zoom levels
    end_if = "\n    END IF;" if len(zoom_mapping) > 1 else ""

    # Early return for zooms below min_zoom
    min_zoom_guard = ""
    if min_zoom is not None and min_zoom > 0:
        min_zoom_guard = f"    IF z < {min_zoom} THEN\n        RETURN NULL;\n    END IF;\n\n"

    return f"""-- Function source for Martin: returns bytea MVT tiles
-- Auto-generated by generate_functions.py - do not edit manually
-- Source-layer name in MVT: "{sl}"
DROP FUNCTION IF EXISTS public.{fn}(integer, integer, integer, json);

CREATE OR REPLACE FUNCTION public.{fn}(
    z integer,
    x integer,
    y integer,
    query_params json DEFAULT '{{}}'::json
) RETURNS bytea AS $$
DECLARE
    bounds geometry := ST_TileEnvelope(z, x, y);
    mvt bytea;
BEGIN
{min_zoom_guard}{body}{end_if}

    RETURN mvt;
END;
$$ LANGUAGE plpgsql STABLE PARALLEL SAFE;
"""


def get_maxzoom(zoom_mapping):
    """Derive maxzoom from zoom_mapping. null entry means up to z20."""
    last_max = zoom_mapping[-1][0]
    return 20 if last_max is None else last_max


def build_tilejson(name, description, tiles_url, vector_layers, minzoom=0, maxzoom=20):
    """Build a TileJSON 3.0.0 manifest."""
    return {
        "tilejson": "3.0.0",
        "name": name,
        "description": description,
        "tiles": [tiles_url],
        "minzoom": minzoom,
        "maxzoom": maxzoom,
        "vector_layers": vector_layers,
    }


def build_vector_layer(func_def, fields):
    """Build a single vector_layer entry for TileJSON."""
    return {
        "id": func_def["source_layer"],
        "description": func_def["function_name"],
        "minzoom": func_def.get("min_zoom", 0),
        "maxzoom": get_maxzoom(func_def["zoom_mapping"]),
        "fields": fields,
    }


def generate_tilejson_files(groups, fields_per_function, base_url):
    """Generate static TileJSON files for each function and each composite group."""
    os.makedirs(TILEJSON_DIR, exist_ok=True)
    count = 0

    for group in groups:
        group_name = group["name"]
        group_vector_layers = []
        group_minzoom = 20
        group_maxzoom = 0

        for func_def in group["functions"]:
            fn = func_def["function_name"]
            if fn not in fields_per_function:
                continue

            fields = fields_per_function[fn]
            vl = build_vector_layer(func_def, fields)
            group_vector_layers.append(vl)

            fn_minzoom = func_def.get("min_zoom", 0)
            fn_maxzoom = get_maxzoom(func_def["zoom_mapping"])
            group_minzoom = min(group_minzoom, fn_minzoom)
            group_maxzoom = max(group_maxzoom, fn_maxzoom)

            # Per-function TileJSON
            tj = build_tilejson(
                name=fn,
                description=f"Layer: {func_def['source_layer']}",
                tiles_url=f"{base_url}/maps/{group_name}/{fn}/{{z}}/{{x}}/{{y}}.pbf",
                vector_layers=[vl],
                minzoom=fn_minzoom,
                maxzoom=fn_maxzoom,
            )
            path = os.path.join(TILEJSON_DIR, f"{fn}.json")
            with open(path, "w") as f:
                json.dump(tj, f, separators=(",", ":"))
            count += 1

        # Composite group TileJSON
        if group_vector_layers:
            tj = build_tilejson(
                name=group_name,
                description=f"Composite: {group_name} ({len(group_vector_layers)} layers)",
                tiles_url=f"{base_url}/maps/{group_name}/{{z}}/{{x}}/{{y}}.pbf",
                vector_layers=group_vector_layers,
                minzoom=group_minzoom,
                maxzoom=group_maxzoom,
            )
            path = os.path.join(TILEJSON_DIR, f"{group_name}.json")
            with open(path, "w") as f:
                json.dump(tj, f, separators=(",", ":"))
            count += 1

    return count


def main():
    config = load_config()
    groups = config["groups"]
    total = sum(len(g["functions"]) for g in groups)
    print(f"Loaded {total} functions in {len(groups)} groups from {CONFIG_PATH}")

    conn_str = "host={} port={} user={} password={} dbname={}".format(
        os.environ["POSTGRES_HOST"],
        os.environ["POSTGRES_PORT"],
        os.environ["POSTGRES_USER"],
        os.environ["POSTGRES_PASSWORD"],
        os.environ["POSTGRES_DB"],
    )

    print("Connecting to PostgreSQL...")
    conn = psycopg2.connect(conn_str)
    cur = conn.cursor()

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    created = 0
    skipped = 0
    fields_per_function = {}

    for group in groups:
        group_name = group["name"]
        print(f"\n[{group_name}]")

        for func_def in group["functions"]:
            fn = func_def["function_name"]
            exclude = func_def["exclude_columns"]
            zoom_mapping = [tuple(m) for m in func_def["zoom_mapping"]]
            func_def["zoom_mapping"] = zoom_mapping

            print(f"  {fn}...", end=" ")

            # Get columns for each table
            columns_per_table = {}
            skip = False
            for _, table_name in zoom_mapping:
                cols = get_columns(cur, table_name, exclude)
                if not cols:
                    skip = True
                    break
                columns_per_table[table_name] = cols

            if skip:
                print("SKIPPED (missing table)")
                skipped += 1
                continue

            # Get fields with types from the highest-zoom table (most complete schema)
            last_table = zoom_mapping[-1][1]
            fields_per_function[fn] = get_columns_with_types(cur, last_table, exclude)

            # Generate SQL, write to file, execute
            sql = generate_function_sql(func_def, columns_per_table)

            sql_path = os.path.join(OUTPUT_DIR, f"{fn}.sql")
            with open(sql_path, "w") as f:
                f.write(sql)

            cur.execute(sql)
            conn.commit()
            created += 1
            print("OK")

    cur.close()
    conn.close()
    print(f"\nDone: {created} created, {skipped} skipped.")

    # Generate TileJSON manifests
    base_url = os.environ.get("MARTIN_BASE_URL", "")
    tj_count = generate_tilejson_files(groups, fields_per_function, base_url)
    print(f"TileJSON: {tj_count} files written to {TILEJSON_DIR}")


if __name__ == "__main__":
    main()
