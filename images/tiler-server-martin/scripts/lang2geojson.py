#!/usr/bin/env python3

"""
Export Languages to GeoJSON and Upload to S3
--------------------------------------------

Connects to PostgreSQL, reads the `languages` table (entries with a bbox),
and writes a GeoJSON FeatureCollection. Optionally uploads the file to S3
when AWS credentials / bucket are provided via environment variables.

Used by the Martin tile server image to expose the same language bbox feed
that the previous Tegola image produced.

Usage:
    python lang2geojson.py --output vtiles_languages.geojson --s3-key vtiles_languages.geojson
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

            features.append({
                "type": "Feature",
                "geometry": json.loads(geom_json),
                "properties": {
                    "alias": alias,
                    "key_name": key_name,
                    "count": count,
                    "is_new": is_new,
                },
            })

        geojson = {
            "type": "FeatureCollection",
            "features": features,
        }

        write_json_and_upload(geojson, output_file, s3_key)

    except Exception as e:
        print(f"Error: {e}")
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
