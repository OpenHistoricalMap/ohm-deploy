"""
This script is for benchmarking where SQL performance is evaluated for specific geospatial data queries.
"""
import os
import toml
import psycopg2
from psycopg2 import sql
from time import time
import argparse


def get_postgres_config():
    """
    Get PostgreSQL configuration from environment variables.
    """
    return {
        "dbname": os.getenv("POSTGRES_DB", "default_db"),
        "user": os.getenv("POSTGRES_USER", "default_user"),
        "password": os.getenv("POSTGRES_PASSWORD", "default_password"),
        "host": os.getenv("POSTGRES_HOST", "localhost"),
        "port": os.getenv("POSTGRES_PORT", "5432")
    }


def is_zoom_in_range(zoom, min_zoom, max_zoom):
    """
    Check if the provided zoom level is within the allowed range.
    """
    return min_zoom <= zoom <= max_zoom


def format_bbox(bbox):
    """
    Convert a bbox into a proper ST_MakeEnvelope format.
    """
    x_min, y_min, x_max, y_max, srid = bbox
    return f"ST_MakeEnvelope({x_min}, {y_min}, {x_max}, {y_max}, {srid})"


def main(toml_file_path, bbox, zoom):
    postgres_config = get_postgres_config()

    formatted_bbox = format_bbox(bbox)

    with open(toml_file_path, "r") as file:
        data = toml.load(file)

    results = {}

    try:
        conn = psycopg2.connect(**postgres_config)
        cursor = conn.cursor()

        # Iterate through maps and extract provider_layer
        for map_entry in data.get("maps", []):
            map_name = map_entry.get("name")
            results[map_name] = []
            print("#" * 40 + map_name)
            for layer in map_entry.get("layers", []):
                provider_layer = layer.get("provider_layer")
                min_zoom = layer.get("min_zoom", 0)
                max_zoom = layer.get("max_zoom", 20)
                # Check if zoom is within the range
                if is_zoom_in_range(zoom, min_zoom, max_zoom):
                    # Split the provider and layer name
                    if provider_layer:
                        print("-" * 20 + provider_layer)
                        provider_name, layer_name = provider_layer.split(".")
                        # Search for the SQL in the providers
                        for provider in data.get("providers", []):
                            if provider.get("name") == provider_name:
                                for provider_layer_entry in provider.get("layers", []):
                                    if provider_layer_entry.get("name") == layer_name:

                                        sql_script = provider_layer_entry.get("sql")
                                        # Replace the !BBOX! placeholder with the provided value
                                        sql_with_bbox = sql_script.replace("!BBOX!", formatted_bbox)
                                        sql_with_bbox = sql_with_bbox.replace("'''", "''").replace("3857.0", "3857") + ";"
                                        print(sql_with_bbox)
                                        # Measure the execution time of the SQL
                                        start_time = time()
                                        try:
                                            cursor.execute(sql.SQL(sql_with_bbox))
                                            rows = cursor.fetchall()  # Retrieve results
                                            elapsed_time = time() - start_time

                                            results[map_name].append({
                                                "provider_layer": provider_layer,
                                                "sql": sql_with_bbox,
                                                "execution_time": elapsed_time,
                                                "row_count": len(rows)
                                            })
                                        except Exception as e:
                                            print(f"Error executing SQL for {provider_layer}: {e}")

        for map_name, layers in results.items():
            print(f"Map: {map_name}")
            for layer in layers:
                print("### Results: ")
                print(f"  Provider Layer: {layer['provider_layer']}")
                # print(f"  SQL Script: {layer['sql']}")
                print(f"  Execution Time: {layer['execution_time']:.2f} seconds")
                print(f"  Rows Returned: {layer['row_count']}\n")

    finally:
        # Close the connection
        if cursor:
            cursor.close()
        if conn:
            conn.close()


if __name__ == "__main__":
    # Command-line arguments
    parser = argparse.ArgumentParser(description="Execute SQL queries with a BBOX and zoom.")
    parser.add_argument(
        "--toml",
        required=True,
        help="Path to the TOML configuration file."
    )
    parser.add_argument(
        "--bbox",
        required=True,
        type=str,
        help="Bounding box in the format x_min,y_min,x_max,y_max,srid (comma-separated)."
    )
    parser.add_argument(
        "--zoom",
        required=True,
        type=int,
        help="Zoom level."
    )
    args = parser.parse_args()

    # Parse the BBOX
    bbox = tuple(map(float, args.bbox.split(",")))

    # Run the main script
    main(args.toml, bbox, args.zoom)