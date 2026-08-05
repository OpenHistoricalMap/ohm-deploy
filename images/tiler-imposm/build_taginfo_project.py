"""Build the taginfo project file so mappers can see which tags reach the tiles.

A tag reaches them either by selecting a feature into a table or by getting its own
column, so this reads both from config/layers/*.json. start.sh runs it and uploads
the result to S3.

See https://wiki.openstreetmap.org/wiki/Taginfo/Projects and issue #604.
"""

import glob
import json
import logging
import os

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

# Must match where start.sh uploads it, taginfo reads it from there
DATA_URL = os.getenv(
    "TAGINFO_PROJECT_URL",
    "https://s3.amazonaws.com/planet.openhistoricalmap.org/imposm/taginfo-project.json",
)

PROJECT = {
    "name": "OpenHistoricalMap vector tiles",
    "description": "Tags that OpenHistoricalMap exposes in its official vector tiles.",
    "project_url": "https://www.openhistoricalmap.org/",
    "doc_url": "https://github.com/OpenHistoricalMap/ohm-deploy/tree/main/images/tiler-imposm/config/layers",
    "contact_name": "OpenHistoricalMap",
    "contact_email": "admin@openhistoricalmap.org",
}

# imposm table type -> OSM objects that land in it
OBJECT_TYPES = {
    "point": ["node"],
    "linestring": ["way"],
    "polygon": ["way", "relation"],
    "relation": ["relation"],
    "relation_member": ["relation"],
}

# Columns we compute, not tags the mapper writes
SKIP_FIELD_TYPES = {"id", "geometry", "area", "mapping_key", "mapping_value", "hstore_tags", "member_id", "member_role"}


def mapping_tags(table):
    """Key/value pairs that select a feature into this table. None means any value."""
    mappings = dict(table.get("mapping") or {})
    for mapping in (table.get("mappings") or {}).values():
        mappings.update(mapping.get("mapping") or {})

    for key, values in mappings.items():
        for value in values:
            yield key, None if value == "__any__" else value


def column_tags(table):
    """Keys with their own column here. A column holds any value."""
    for field in table.get("fields", []):
        if field.get("key") and field["type"] not in SKIP_FIELD_TYPES:
            yield field["key"], None


def collect(layers_path):
    """Map each tag to the object types and layers that expose it."""
    tags = {}
    for path in sorted(glob.glob(os.path.join(layers_path, "*.json"))):
        layer = os.path.splitext(os.path.basename(path))[0]
        with open(path, encoding="utf-8") as f:
            config = json.load(f)

        for name, table in config.get("tables", {}).items():
            types = OBJECT_TYPES.get(table.get("type"))
            if not types:
                logger.warning(f"{layer}: unknown table type {table.get('type')!r} in {name}, skipping")
                continue

            for tag in set(mapping_tags(table)) | set(column_tags(table)):
                entry = tags.setdefault(tag, {"object_types": set(), "layers": set()})
                entry["object_types"].update(types)
                entry["layers"].add(layer)

    # A key mapped as any value covers its listed values elsewhere:
    # natural=* in landuse_areas makes natural=water in water_areas redundant.
    for key, value in list(tags):
        if value is not None and (key, None) in tags:
            listed = tags.pop((key, value))
            tags[(key, None)]["object_types"].update(listed["object_types"])
            tags[(key, None)]["layers"].update(listed["layers"])
    return tags


def main(layers_path, output_path):
    tags = collect(layers_path)
    if not tags:
        raise SystemExit(f"No tags found in {layers_path}")

    entries = []
    for key, value in sorted(tags, key=lambda t: (t[0], t[1] or "")):
        entry = {"key": key}
        if value is not None:
            entry["value"] = value
        entry["object_types"] = sorted(tags[(key, value)]["object_types"])
        entry["description"] = "In tile layers: " + ", ".join(sorted(tags[(key, value)]["layers"]))
        entries.append(entry)

    project = {
        "data_format": 1,
        "data_url": DATA_URL,
        "project": PROJECT,
        "tags": entries,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(project, f, indent=2)
        f.write("\n")
    logger.info(f"Wrote {len(project['tags'])} tags to {output_path}")


if __name__ == "__main__":
    main("./config/layers", "./taginfo-project.json")
