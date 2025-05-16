# This script extracts layer information from Mapbox style JSON files and writes it to a CSV file.
# python3 extract_map_layers.py \
# /Users/rub21/apps/map-styles/historical/historical.json \
# /Users/rub21/apps/map-styles/railway/railway.json \
# /Users/rub21/apps/map-styles/woodblock/woodblock.json 
import json
import sys
import csv
from pathlib import Path

def simplify_filter(filter_expr):
    if not isinstance(filter_expr, list):
        return ""

    op_map = {
        "==": "=",
        "!=": "!=",
        ">": ">",
        "<": "<",
        ">=": ">=",
        "<=": "<="
    }

    if filter_expr[0] in op_map and len(filter_expr) == 3:
        op = op_map[filter_expr[0]]

        field_expr = filter_expr[1]
        if isinstance(field_expr, list) and field_expr[0] == "get":
            field = field_expr[1]
        else:
            field = str(field_expr)

        value = filter_expr[2]
        value_str = f'{value}' if isinstance(value, (int, float)) else f'{value}'
        return f"{field} {op} {value_str}"

    elif filter_expr[0] == "in" and len(filter_expr) == 3:
        field_expr = filter_expr[1]
        values = filter_expr[2][1] if isinstance(filter_expr[2], list) and filter_expr[2][0] == "literal" else []
        field = field_expr[1] if isinstance(field_expr, list) and field_expr[0] == "get" else str(field_expr)
        return f"{field} IN [{', '.join(str(v) for v in values)}]"

    elif filter_expr[0] == "!in" and len(filter_expr) == 3:
        field_expr = filter_expr[1]
        values = filter_expr[2][1] if isinstance(filter_expr[2], list) and filter_expr[2][0] == "literal" else []
        field = field_expr[1] if isinstance(field_expr, list) and field_expr[0] == "get" else str(field_expr)
        return f"{field} NOT IN [{', '.join(str(v) for v in values)}]"

    elif filter_expr[0] == "has":
        return f"has {filter_expr[1]}"

    elif filter_expr[0] == "!has":
        return f"not has {filter_expr[1]}"

    elif filter_expr[0] == "all":
        return " AND ".join(filter(None, [simplify_filter(f) for f in filter_expr[1:]]))

    elif filter_expr[0] == "any":
        return " OR ".join(filter(None, [simplify_filter(f) for f in filter_expr[1:]]))

    elif filter_expr[0] == "!":
        inner = simplify_filter(filter_expr[1])
        return f"NOT ({inner})" if inner else ""

    return json.dumps(filter_expr, ensure_ascii=False)

def extract_layer_info(json_path):
    with open(json_path, 'r', encoding='utf-8') as f:
        data = json.load(f)

    layers_info = []
    layers = data.get("layers", [])

    for layer in layers:
        if "source-layer" in layer:
            raw_filter = layer.get("filter", "")
            raw_filter_str = json.dumps(raw_filter, ensure_ascii=False)
            simplified = simplify_filter(raw_filter)
            simplified_clean = simplified.replace('"', '')

            layer_info = {
                "file_name": Path(json_path).name,
                "id": layer.get("id", ""),
                "source-layer": layer.get("source-layer", ""),
                "minzoom": layer.get("minzoom", ""),
                "maxzoom": layer.get("maxzoom", ""),
                "filter_raw": raw_filter_str,
                "filter": simplified_clean
            }
            layers_info.append(layer_info)
    return layers_info

def main(json_files):
    all_layers = []
    for path in json_files:
        all_layers.extend(extract_layer_info(path))

    output_file = "extracted_layers.csv"
    with open(output_file, "w", newline="", encoding="utf-8") as csvfile:
        fieldnames = ["file_name", "id", "source-layer", "minzoom", "maxzoom", "filter_raw", "filter"]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in all_layers:
            writer.writerow(row)
    print(f"Data written to {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_map_layers.py file1.json file2.json ...")
    else:
        main(sys.argv[1:])

