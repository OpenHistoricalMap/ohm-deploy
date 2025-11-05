#!/usr/bin/env python3
"""Verify that all materialized views referenced in TOML provider files have a 'geometry' column."""

import re
import toml
from pathlib import Path
from utils import get_db_connection


def extract_mview_from_sql(sql_text):
    """Extract materialized view name from SQL query."""
    if not sql_text:
        return None
    pattern = r'\bFROM\s+(?:[a-zA-Z_][a-zA-Z0-9_]*\.)?(mv_[a-zA-Z0-9_]+)'
    matches = re.findall(pattern, sql_text, re.IGNORECASE)
    return matches[0] if matches else None


def check_geometry_column(conn, mview_name):
    """Verify if the 'geometry' column exists in the materialized view."""
    sql_check = """
    SELECT EXISTS (
        SELECT 1
        FROM pg_attribute a
        JOIN pg_class c ON a.attrelid = c.oid
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public'
        AND c.relname = %s
        AND a.attname = 'geometry'
        AND a.attnum > 0
        AND NOT a.attisdropped
    );
    """
    try:
        cur = conn.cursor()
        cur.execute(sql_check, (mview_name,))
        exists = cur.fetchone()[0]
        cur.close()
        return exists
    except Exception as e:
        print(f"❌ Error checking {mview_name}: {e}")
        return None


def main():
    script_dir = Path(__file__).parent
    providers_dir = script_dir.parent / 'config' / 'providers'
    
    conn = get_db_connection()
    has_errors = False
    
    for toml_file in providers_dir.glob("*.toml"):
        with open(toml_file, 'r', encoding='utf-8') as f:
            data = toml.load(f)
        
        for layer in data.get('providers', {}).get('layers', []):
            layer_name = layer.get('name', 'unknown')
            mview_name = extract_mview_from_sql(layer.get('sql', ''))
            
            if not mview_name:
                print(f"❌ {toml_file.name} -> {layer_name}: No materialized view found")
                has_errors = True
                continue
            
            has_geometry = check_geometry_column(conn, mview_name)
            if has_geometry is None or not has_geometry:
                print(f"❌ {toml_file.name} -> {layer_name} -> {mview_name}: No geometry column")
                has_errors = True
            else:
                print(f"✅ {toml_file.name} -> {layer_name} -> {mview_name}")
    
    conn.close()
    exit(1 if has_errors else 0)


if __name__ == "__main__":
    main()

