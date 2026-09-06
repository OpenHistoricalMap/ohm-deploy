#!/usr/bin/env python3
"""Reads layers.yaml and layers/<name>/layer.yaml and produces what the other tools need.

  layers.py imposm  [--layers a,b] [-o config/imposm3.json]   imposm mapping (default: IMPOSM3_IMPORT_LAYERS or all)
  layers.py sql     [--init] [LAYER ...]                      SQL files to run, in build order
  layers.py refresh                                            one line per refresh group: NAME|profile|interval|mview mview ...
  layers.py missing                                            layers with a table missing, table names read from stdin
  layers.py check                                              validate the manifests
"""
import argparse
import json
import os
import re
import sys

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "config", "imposm3.template.json")


def load():
    index = yaml.safe_load(open(os.path.join(ROOT, "layers.yaml")))
    layers = []
    for name in index["layers"]:
        path = os.path.join(ROOT, "layers", name, "layer.yaml")
        layer = yaml.safe_load(open(path))
        layer.setdefault("tables", [])
        layer.setdefault("sql", [])
        layer.setdefault("sql_init", [])
        layer.setdefault("refresh", [])
        layer["dir"] = os.path.join("layers", name)
        layers.append(layer)
    return index, layers


def select(layers, names):
    names = list(dict.fromkeys(names))  # keep order, drop duplicates
    if not names:
        return layers
    by_name = {l["name"]: l for l in layers}
    unknown = [n for n in names if n not in by_name]
    if unknown:
        sys.exit(f"unknown layer(s): {', '.join(unknown)}. Available: {', '.join(by_name)}")
    return [by_name[n] for n in names]


def mapping(layer):
    path = os.path.join(ROOT, layer["dir"], "mapping.json")
    return json.load(open(path)) if os.path.exists(path) else {"tables": {}}


# --- commands --------------------------------------------------------------

def cmd_imposm(args, index, layers):
    wanted = args.layers or os.getenv("IMPOSM3_IMPORT_LAYERS", "all")
    names = [] if wanted.strip() == "all" else [n.strip() for n in wanted.split(",") if n.strip()]
    config = json.load(open(TEMPLATE))
    for layer in select(layers, names):
        m = mapping(layer)
        config.setdefault("generalized_tables", {}).update(m.get("generalized_tables", {}))
        config.setdefault("tables", {}).update(m.get("tables", {}))
    write_json(args.output, config)
    print(f"imposm mapping: {len(config['tables'])} tables -> {args.output}", file=sys.stderr)


def cmd_sql(args, index, layers):
    key = "sql_init" if args.init else "sql"
    for layer in select(layers, args.layers):
        for f in layer[key]:
            print(os.path.join(layer["dir"], f))


def cmd_refresh(args, index, layers):
    for layer in layers:
        for g in layer["refresh"]:
            print(f"{g['name']}|{g.get('profile', 'light')}|{g.get('interval', 180)}|{' '.join(g['mviews'])}")


def cmd_missing(args, index, layers):
    existing = set(sys.stdin.read().split())
    for layer in layers:
        if layer["tables"] and any(f"osm_{t}" not in existing for t in layer["tables"]):
            print(layer["name"])


def cmd_check(args, index, layers):
    problems, warnings = [], []
    seen_tables = {}
    for layer in layers:
        name = layer["name"]
        m = mapping(layer)
        if list(m.get("tables", {})) != layer["tables"]:
            problems.append(f"{name}: tables in layer.yaml {layer['tables']} != mapping.json {list(m.get('tables', {}))}")
        for t in layer["tables"]:
            if t in seen_tables:
                problems.append(f"{name}: table {t} already defined in {seen_tables[t]}")
            seen_tables[t] = name
        sql_text = ""
        for f in layer["sql"] + layer["sql_init"]:
            path = os.path.join(ROOT, layer["dir"], f)
            if not os.path.exists(path):
                problems.append(f"{name}: missing SQL file {f}")
            else:
                sql_text += open(path).read()
        created = {v[:-4] if v.endswith("_tmp") else v for v in re.findall(r"(?:'|CREATE MATERIALIZED VIEW (?:IF NOT EXISTS )?)(mv[a-z0-9_]*)", sql_text)}
        for g in layer["refresh"]:
            for mv in g["mviews"]:
                if mv not in created:
                    warnings.append(f"{name}: refresh group {g['name']} lists {mv}, not created by this layer's SQL")
    for w in warnings:
        print(f"warning: {w}")
    for p in problems:
        print(f"error: {p}")
    print(f"{len(layers)} layers, {len(seen_tables)} tables, {len(problems)} errors, {len(warnings)} warnings")
    sys.exit(1 if problems else 0)


# --- output helpers ----------------------------------------------------------

def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("imposm"); p.add_argument("--layers", default=""); p.add_argument("-o", "--output", default=os.path.join(ROOT, "config", "imposm3.json"))
    p = sub.add_parser("sql"); p.add_argument("--init", action="store_true"); p.add_argument("layers", nargs="*")
    sub.add_parser("refresh")
    sub.add_parser("missing")
    sub.add_parser("check")
    args = parser.parse_args()
    index, layers = load()
    globals()[f"cmd_{args.command}"](args, index, layers)


if __name__ == "__main__":
    main()
