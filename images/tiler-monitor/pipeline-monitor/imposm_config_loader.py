"""Load imposm3.json from S3 and parse it into the tag-to-table mapping used by the monitor.

The compiled imposm3.json is the source of truth for what imposm actually imports.
This module downloads it and builds a precise mapping structure that tells the monitor
exactly which tags, values, geometry types, and filters each table uses.
"""

import json
import logging
import os

import requests

from config import Config

logger = logging.getLogger(__name__)

# Geometry type in imposm → compatible OSM element types
_GEOM_TO_ELEM_TYPES = {
    "point": {"node"},
    "linestring": {"way"},
    "polygon": {"way", "relation"},
    "relation_member": {"relation"},
}

# View mappings per table prefix. Views are created by SQL scripts, not by imposm,
# so we maintain this mapping separately. The monitor also dynamically checks
# pg_matviews at runtime, but this helps narrow the search.
_TABLE_TO_VIEWS = {
    "osm_amenity_areas": ["mv_amenity_areas_z14_15", "mv_amenity_areas_z16_20"],
    "osm_amenity_points": ["mv_amenity_points", "mv_amenity_points_centroids_z14_15", "mv_amenity_points_centroids_z16_20"],
    "osm_transport_lines": ["mv_transport_lines_z5", "mv_transport_lines_z16_20"],
    "osm_transport_areas": ["mv_transport_areas_z10_12", "mv_transport_areas_z16_20"],
    "osm_transport_points": ["mv_transport_points", "mv_transport_points_centroids_z10_12", "mv_transport_points_centroids_z16_20"],
    "osm_transport_multilines": [],
    "osm_admin_areas": ["mv_admin_boundaries_areas_z0_2", "mv_admin_boundaries_areas_z16_20"],
    "osm_admin_lines": ["mv_admin_boundaries_lines_z0_2", "mv_admin_boundaries_lines_z16_20", "mv_admin_maritime_lines_z0_5_v2", "mv_admin_maritime_lines_z10_15", "mv_non_admin_boundaries_areas_z0_2", "mv_non_admin_boundaries_areas_z16_20", "mv_non_admin_boundaries_centroids_z0_2", "mv_non_admin_boundaries_centroids_z16_20"],
    "osm_admin_relation_members": ["mv_relation_members_boundaries", "mv_admin_boundaries_centroids_z0_2", "mv_admin_boundaries_centroids_z16_20"],
    "osm_buildings": ["mv_buildings_areas_z14_15", "mv_buildings_areas_z16_20"],
    "osm_buildings_points": ["mv_buildings_points", "mv_buildings_points_centroids_z14_15", "mv_buildings_points_centroids_z16_20"],
    "osm_communication_lines": ["mv_communication_z10_12", "mv_communication_z16_20"],
    "osm_communication_multilines": [],
    "osm_landuse_areas": ["mv_landuse_areas_z6_7", "mv_landuse_areas_z16_20"],
    "osm_landuse_lines": ["mv_landuse_lines_z14_15", "mv_landuse_lines_z16_20"],
    "osm_landuse_points": ["mv_landuse_points", "mv_landuse_points_centroids_z6_7", "mv_landuse_points_centroids_z16_20"],
    "osm_water_areas": ["mv_water_areas_z0_2", "mv_water_areas_z16_20", "mv_water_areas_centroids_z8_9", "mv_water_areas_centroids_z16_20"],
    "osm_water_lines": ["mv_water_lines_z8_9", "mv_water_lines_z16_20"],
    "osm_other_areas": ["mv_other_areas_z8_9", "mv_other_areas_z16_20"],
    "osm_other_lines": ["mv_other_lines_z14_15", "mv_other_lines_z16_20"],
    "osm_other_points": ["mv_other_points", "mv_other_points_centroids_z8_9", "mv_other_points_centroids_z16_20"],
    "osm_place_areas": ["mv_place_areas_z14_20"],
    "osm_place_points": ["mv_place_points_centroids_z0_2", "mv_place_points_centroids_z11_20"],
    "osm_route_lines": [],
    "osm_route_multilines": ["mv_routes_indexed_z16_20"],
    "osm_street_multilines": ["mv_transport_lines_z5", "mv_transport_lines_z16_20"],
}

# Special view config for route tables (views use member way IDs, not relation IDs)
_ROUTE_VIEW_CONFIG = {
    "view_column": "osm_id",
    "view_id_mode": "members",
}


def _download_imposm_config():
    """Download the compiled imposm3.json from S3."""
    url = Config.IMPOSM_CONFIG_URL
    if not url:
        return None
    try:
        resp = requests.get(url, timeout=30)
        resp.raise_for_status()
        return resp.json()
    except Exception as e:
        logger.warning("Failed to download imposm config from %s: %s", url, e)
        return None


def _extract_tag_mappings(table_name, table_config):
    """Extract tag→values mappings from a single table config.

    Handles both formats:
    - "mapping": {"tag": ["value1", ...]}  (direct)
    - "mappings": {"group": {"mapping": {"tag": [...]}, "exclude": [...]}}  (grouped)

    Returns list of dicts: [{"tag": str, "values": list, "excludes": list}]
    """
    results = []

    # Format 1: direct "mapping"
    if "mapping" in table_config and not isinstance(table_config["mapping"], dict):
        return results
    if "mapping" in table_config and "mappings" not in table_config:
        for tag_key, values in table_config["mapping"].items():
            results.append({"tag": tag_key, "values": values, "excludes": []})

    # Format 2: grouped "mappings"
    if "mappings" in table_config:
        for group_name, group_config in table_config["mappings"].items():
            mapping = group_config.get("mapping", {})
            excludes = group_config.get("exclude", [])
            for tag_key, values in mapping.items():
                results.append({"tag": tag_key, "values": values, "excludes": excludes})

    return results


def _parse_imposm_config(imposm_config):
    """Parse imposm3.json into the structures needed by the monitor.

    Returns a dict with:
    - tag_to_check: tag-to-table mapping
    - table_details: precise per-table info (geometry, values, rejects, excludes)
    - importable_relation_types: set of relation types that imposm imports
    """
    tables = imposm_config.get("tables", {})

    # tag_key → {tables: set, views: set, view_config: dict}
    tag_entries = {}
    # (table_name, tag_key) → {geometry, values, rejects, excludes}
    table_details = {}
    # Track which relation types are imported
    importable_relation_types = set()

    for raw_table_name, tconfig in tables.items():
        table_name = f"osm_{raw_table_name}"
        geom_type = tconfig.get("type", "")

        # Extract reject filters for this table
        rejects = {}
        filters = tconfig.get("filters", {})
        if "reject" in filters:
            rejects = filters["reject"]

        # Extract tag mappings
        tag_mappings = _extract_tag_mappings(raw_table_name, tconfig)

        for mapping in tag_mappings:
            tag_key = mapping["tag"]
            values = mapping["values"]
            excludes = mapping["excludes"]

            # Track importable relation types
            if geom_type == "relation_member":
                # For relation_member tables, the mapping keys represent
                # what the relation's tags must match. E.g. route: [__any__]
                # means relations with type=route are imported.
                # Special case: "type": ["street"] means type=street relations
                if tag_key == "type":
                    importable_relation_types.update(v for v in values if v != "__any__")
                else:
                    importable_relation_types.add(tag_key)

            # Build the tag_key for tag_to_check
            # Special case: mapping on "type" key with specific values (e.g. type=street)
            if tag_key == "type" and values != ["__any__"]:
                for v in values:
                    check_key = f"type={v}"
                    if check_key not in tag_entries:
                        tag_entries[check_key] = {"tables": set(), "views": set(), "view_config": {}}
                    tag_entries[check_key]["tables"].add(table_name)
                    tag_entries[check_key]["views"].update(_TABLE_TO_VIEWS.get(table_name, []))
                    if table_name in ("osm_route_multilines",):
                        tag_entries[check_key]["view_config"].update(_ROUTE_VIEW_CONFIG)
                    table_details[(table_name, check_key)] = {
                        "geometry": geom_type,
                        "values": values,
                        "rejects": rejects,
                        "excludes": excludes,
                    }
            else:
                if tag_key not in tag_entries:
                    tag_entries[tag_key] = {"tables": set(), "views": set(), "view_config": {}}
                tag_entries[tag_key]["tables"].add(table_name)
                tag_entries[tag_key]["views"].update(_TABLE_TO_VIEWS.get(table_name, []))
                if table_name in ("osm_route_multilines",):
                    tag_entries[tag_key]["view_config"].update(_ROUTE_VIEW_CONFIG)

                table_details[(table_name, tag_key)] = {
                    "geometry": geom_type,
                    "values": values,
                    "rejects": rejects,
                    "excludes": excludes,
                }

    # Build tag_to_check in the legacy format
    tag_to_check = {}
    for tag_key, entry in tag_entries.items():
        result = {
            "tables": sorted(entry["tables"]),
            "views": sorted(entry["views"]),
        }
        if entry["view_config"]:
            result.update(entry["view_config"])
        tag_to_check[tag_key] = result

    # Also add multipolygon and boundary to importable_relation_types
    # These are always imported by imposm for polygon tables
    importable_relation_types.add("multipolygon")
    importable_relation_types.add("boundary")

    return {
        "tag_to_check": tag_to_check,
        "table_details": table_details,
        "importable_relation_types": importable_relation_types,
    }


def load_config():
    """Load imposm config from S3 and parse it.

    Returns dict with tag_to_check, table_details, and importable_relation_types.
    """
    imposm_config = _download_imposm_config()
    if not imposm_config:
        raise RuntimeError("Failed to download imposm config from S3")

    result = _parse_imposm_config(imposm_config)
    logger.info(
        "Loaded imposm config from S3: %d tags, %d table mappings, relation types: %s",
        len(result["tag_to_check"]),
        len(result["table_details"]),
        sorted(result["importable_relation_types"]),
    )
    return result


def get_skip_reason(elem, tag_to_check, table_details, importable_relation_types):
    """Return a dict describing why imposm would skip this element, or None if importable.

    Returns None if the element should be imported by imposm.
    Returns a dict with:
      - reason (str): human-readable explanation
      - commentable (bool): True if the mapper should be notified (element has
        tiler-relevant tags but imposm can't import it due to geometry, filters, etc.)
        False if the element simply has no tags relevant to the tiler.
    """
    tags = elem.get("tags", {})
    elem_type = elem.get("type", "")

    if not tags:
        return {"reason": "Element has no tags", "commentable": False}

    # Check geometry validity
    if elem_type == "way":
        node_count = elem.get("node_count", 0)
        if node_count > 0:
            if tags.get("area") == "yes" and node_count < 4:
                return {
                    "reason": f"Way has area=yes but only {node_count} nodes (minimum 4 needed for a valid polygon)",
                    "commentable": True,
                }
            if tags.get("area") != "yes" and node_count < 2:
                return {
                    "reason": f"Way has only {node_count} node(s) (minimum 2 needed for a line)",
                    "commentable": True,
                }

    # Check if any tag is mappable
    matched_any_tag = False
    rejection_reasons = []

    for tag_key, tag_value in tags.items():
        # Check simple tag keys
        if tag_key in tag_to_check:
            matched_any_tag = True
            entry = tag_to_check[tag_key]

            # Check per-table details for precise matching
            if table_details:
                compatible_tables = []
                for table_name in entry.get("tables", []):
                    detail = table_details.get((table_name, tag_key))
                    if not detail:
                        continue

                    # Check geometry compatibility
                    compatible_elem_types = _GEOM_TO_ELEM_TYPES.get(detail["geometry"], set())
                    if elem_type not in compatible_elem_types:
                        rejection_reasons.append(
                            f"{table_name} requires {detail['geometry']} geometry (not compatible with {elem_type})"
                        )
                        continue

                    # Check reject filters
                    rejected = False
                    for reject_key, reject_values in detail["rejects"].items():
                        if tags.get(reject_key) in reject_values:
                            rejection_reasons.append(
                                f"{table_name}: rejected because {reject_key}={tags[reject_key]}"
                            )
                            rejected = True
                            break
                    if rejected:
                        continue

                    # Check if value is accepted
                    if "__any__" not in detail["values"]:
                        if tag_value not in detail["values"]:
                            rejection_reasons.append(
                                f"{table_name}: {tag_key}={tag_value} not in accepted values {detail['values']}"
                            )
                            continue

                    # Check excludes
                    if tag_value in detail["excludes"]:
                        rejection_reasons.append(
                            f"{table_name}: {tag_key}={tag_value} is excluded"
                        )
                        continue

                    compatible_tables.append(table_name)

                if compatible_tables:
                    return None  # At least one table accepts this element

        # Check key=value tags (e.g. type=street)
        check_key = f"{tag_key}={tag_value}"
        if check_key in tag_to_check:
            matched_any_tag = True
            if not table_details:
                return None  # No precise details, assume it's importable
            entry = tag_to_check[check_key]
            for table_name in entry.get("tables", []):
                detail = table_details.get((table_name, check_key))
                if not detail:
                    continue
                compatible_elem_types = _GEOM_TO_ELEM_TYPES.get(detail["geometry"], set())
                if elem_type in compatible_elem_types:
                    return None

    if not matched_any_tag:
        # For relations: check if the relation type itself is not importable
        # (only check here, after confirming no other tags matched any table)
        if elem_type == "relation":
            rel_type = tags.get("type", "")
            if rel_type and rel_type not in importable_relation_types:
                return {
                    "reason": (
                        f"Relation type '{rel_type}' is not imported by the tiler. "
                        f"Only these relation types are supported: {', '.join(sorted(importable_relation_types))}"
                    ),
                    "commentable": False,
                }

        return {
            "reason": "No tags match the tiler's import configuration",
            "commentable": False,
        }

    # Tags matched but all tables rejected it — mapper should know
    if rejection_reasons:
        # For relations with non-standard type: mention the relation type in the reason
        if elem_type == "relation":
            rel_type = tags.get("type", "")
            if rel_type and rel_type not in importable_relation_types:
                rejection_reasons.append(
                    f"relation type '{rel_type}' is not directly importable "
                    f"(supported: {', '.join(sorted(importable_relation_types))})"
                )
        return {
            "reason": "Element has mappable tags but was rejected by all tables: " + "; ".join(rejection_reasons),
            "commentable": True,
        }

    # Fallback: matched tag but no table_details to verify precisely
    return None
