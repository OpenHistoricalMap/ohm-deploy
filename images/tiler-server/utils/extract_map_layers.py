# This script extracts layer information from Mapbox style JSON files and writes it to a CSV file.
# python3 extract_map_layers.py \
# /Users/rub21/apps/map-styles/historical/historical.json \
# /Users/rub21/apps/map-styles/railway/railway.json \
# /Users/rub21/apps/map-styles/woodblock/woodblock.json 
import json
import sys
import csv
from pathlib import Path
from collections import defaultdict

def extract_layer_info(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    layers_info = []
    layers = data.get("layers", [])

    for layer in layers:
        if "source-layer" in layer:
            layer_info = {
                "file_name": Path(json_path).name,
                "id": layer.get("id", ""),
                "source-layer": layer.get("source-layer", ""),
                "minzoom": layer.get("minzoom", ""),
                "maxzoom": layer.get("maxzoom", "")
            }
            layers_info.append(layer_info)
    return layers_info

def main(json_files):
    all_layers = []
    for path in json_files:
        all_layers.extend(extract_layer_info(path))

    # Save detailed CSV
    output_file = "extracted_layers.csv"
    with open(output_file, "w", newline="", encoding="utf-8") as csvfile:
        fieldnames = ["file_name", "id", "source-layer", "minzoom", "maxzoom"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in all_layers:
            writer.writerow(row)
    print(f"✅ Data written to {output_file}")

    # Build summary
    summary = defaultdict(lambda: {"minzoom": float("inf"), "maxzoom": float("-inf")})
    for row in all_layers:
        sl = row["source-layer"]
        try:
            minz = int(row["minzoom"]) if row["minzoom"] != "" else 0
        except:
            minz = 0
        try:
            maxz = int(row["maxzoom"]) if row["maxzoom"] != "" else 0
        except:
            maxz = 0
        summary[sl]["minzoom"] = min(summary[sl]["minzoom"], minz)
        summary[sl]["maxzoom"] = max(summary[sl]["maxzoom"], maxz)

    # Save summary CSV
    summary_file = "summary_layers.csv"
    with open(summary_file, "w", newline="", encoding="utf-8") as csvfile:
        fieldnames = ["source-layer", "minzoom", "maxzoom"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for sl, z in summary.items():
            writer.writerow({
                "source-layer": sl,
                "minzoom": z["minzoom"],
                "maxzoom": z["maxzoom"]
            })
    print(f"📊 Summary written to {summary_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_map_layers.py file1.json file2.json ...")
    else:
        main(sys.argv[1:])