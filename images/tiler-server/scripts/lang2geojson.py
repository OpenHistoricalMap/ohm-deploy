#!/usr/bin/env python3

"""
Export Languages to GeoJSON and Upload to S3
--------------------------------------------

This script connects to a PostgreSQL database, retrieves language records from the `languages` table that contain
bounding boxes (`bbox`), and exports the data as a GeoJSON FeatureCollection. Each feature includes metadata such as 
language alias, key name, count, and whether the language is new.

If specified, the resulting GeoJSON file can be automatically uploaded to an S3 bucket using AWS credentials 
provided via environment variables.

Usage:
    python export_languages_geojson.py --output languages.geojson --s3-key myfolder/languages.geojson

Arguments:
--output     Local path to save the resulting GeoJSON file (default: languages.geojson)
--s3-key     Path/key in the S3 bucket to upload the GeoJSON file (default: vtiles_languages.geojson)
"""

import json
import argparse
from utils import get_db_connection, write_json_and_upload

def export_languages_to_geojson(output_file, s3_key):
    conn = None
    cursor = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        query = """
        SELECT
            alias,
            key_name,
            count,
            is_new,
            ST_AsGeoJSON(ST_Transform(ST_SetSRID(bbox, 3857), 4326)) AS geometry
        FROM languages
        WHERE bbox IS NOT NULL;
        """

        cursor.execute(query)
        rows = cursor.fetchall()

        features = []
        for row in rows:
            alias, key_name, count, is_new, geom_json = row
            if not geom_json:
                continue

            feature = {
                "type": "Feature",
                "geometry": json.loads(geom_json),
                "properties": {
                    "alias": alias,
                    "key_name": key_name,
                    "count": count,
                    "is_new": is_new
                }
            }
            features.append(feature)

        geojson = {
            "type": "FeatureCollection",
            "features": features
        }

        write_json_and_upload(geojson, output_file, s3_key)

    except Exception as e:
        print(f"Error: {e}")
        raise
    finally:
        if cursor:
            cursor.close()
        if conn:
            conn.close()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export languages with bbox to GeoJSON")
    parser.add_argument("--output", help="Output GeoJSON file", default="vtiles_languages.geojson")
    parser.add_argument("--s3-key", help="S3 key (filename in S3 bucket)", default="vtiles_languages.geojson")

    args = parser.parse_args()
    export_languages_to_geojson(args.output, args.s3_key)
