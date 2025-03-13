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

        # Iterate through providers
        for provider in data.get("providers", []):
            provider_name = provider.get("name")
            results[provider_name] = []
            print(f"\n{'#' * 40} PROVIDER: {provider_name}")

            for provider_layer_entry in provider.get("layers", []):
                layer_name = provider_layer_entry.get("name")

                # Find matching layers in maps
                for map_entry in data.get("maps", []):
                    for layer in map_entry.get("layers", []):
                        if layer.get("provider_layer") == f"{provider_name}.{layer_name}":
                            min_zoom = layer.get("min_zoom", 0)
                            max_zoom = layer.get("max_zoom", 20)

                            # Check if zoom is within range
                            if is_zoom_in_range(zoom, min_zoom, max_zoom):
                                sql_script = provider_layer_entry.get("sql")

                                if sql_script:
                                    # Replace !BBOX! placeholder with the provided BBOX
                                    sql_with_bbox = sql_script.replace("!BBOX!", formatted_bbox)
                                    sql_with_bbox = sql_with_bbox.replace("'''", "''").replace("3857.0", "3857") + ";"

                                    print(f"\n{'******' * 20} Running Query for {provider_name}.{layer_name}")
                                    print(sql_with_bbox)

                                    # Measure execution time
                                    start_time = time()
                                    try:
                                        cursor.execute(sql.SQL(sql_with_bbox))
                                        rows = cursor.fetchall()  # Retrieve results
                                        elapsed_time = time() - start_time

                                        results[provider_name].append({
                                            "layer": layer_name,
                                            "sql": sql_with_bbox,
                                            "execution_time": elapsed_time,
                                            "row_count": len(rows)
                                        })
                                    except Exception as e:
                                        print(f"⚠️ Error executing SQL for {provider_name}.{layer_name}: {e}")

        # Print Summary
        for provider_name, layers in results.items():
            print(f"\n{'=' * 40} SUMMARY for {provider_name} {'=' * 40}")
            total_time = sum(layer["execution_time"] for layer in layers)
            total_rows = sum(layer["row_count"] for layer in layers)

            print(f"✅ Total Execution Time: {total_time:.2f} seconds")
            print(f"✅ Total Rows Retrieved: {total_rows}\n")

            for layer in layers:
                print(f"  🔹 Layer: {layer['layer']}")
                print(f"  ⏳ Execution Time: {layer['execution_time']:.2f} seconds")
                print(f"  📊 Rows Returned: {layer['row_count']}\n")

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