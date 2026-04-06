"""
Purge nginx proxy cache by deleting MD5-hashed cache files from the volume.

Used when CACHE_BACKEND=nginx (Martin tile server).
Nginx stores cached responses as files named by MD5(cache_key), organized
in subdirectories based on the configured levels (e.g., 1:2).

This module provides the same tile purging capability as the S3 backend,
but operates on local filesystem (Docker volume shared with nginx).
"""

import hashlib
import json
import os
from config import Config
from utils.utils import get_logger

logger = get_logger()


def load_group_functions():
    """Load function names per group from functions.json.

    Filters by NGINX_GROUPS and skips static groups (osm_land, ne)
    since their tiles never change.
    """
    try:
        with open(Config.NGINX_FUNCTIONS_JSON) as f:
            config = json.load(f)
        groups = {}
        for g in config.get("groups", []):
            if g.get("static", False):
                continue
            if g["name"] in Config.NGINX_GROUPS:
                groups[g["name"]] = [fn["function_name"] for fn in g["functions"]]
        return groups
    except Exception as e:
        logger.error(f"Failed to load functions.json: {e}")
        return {name: [] for name in Config.NGINX_GROUPS}


def cache_file_path(uri):
    """
    Compute the nginx cache file path for a given URI.

    Nginx uses MD5(key) and stores files using the 'levels' directory structure.
    For levels=1:2, the path is built from the END of the hash:
      - level 1: last 1 char
      - level 2: next 2 chars before that
      Result: {cache_dir}/{last1}/{prev2}/{full_md5}

    Example:
      URI: /maps/ohm/0/0/0.pbf
      MD5: 8a291ba8e040cfc0456c2dde27a72654
      Path: /var/cache/nginx/tiles/4/65/8a291ba8e040cfc0456c2dde27a72654
    """
    md5 = hashlib.md5(uri.encode()).hexdigest()
    levels = Config.NGINX_CACHE_LEVELS.split(":")
    parts = []
    pos = len(md5)
    for level in levels:
        n = int(level)
        pos -= n
        parts.append(md5[pos:pos + n])
    return os.path.join(Config.NGINX_CACHE_DIR, *parts, md5)


def get_parent_tiles(z, x, y, min_zoom=0):
    """Get parent tiles from z down to min_zoom."""
    parents = []
    while z > min_zoom:
        z -= 1
        x //= 2
        y //= 2
        parents.append((z, x, y))
    return parents


def get_child_tiles(z, x, y, max_zoom):
    """Get all child tiles from z down to max_zoom."""
    if z >= max_zoom:
        return []
    children = []
    stack = [(z + 1, x * 2, y * 2), (z + 1, x * 2 + 1, y * 2),
             (z + 1, x * 2, y * 2 + 1), (z + 1, x * 2 + 1, y * 2 + 1)]
    while stack:
        cz, cx, cy = stack.pop()
        children.append((cz, cx, cy))
        if cz < max_zoom:
            stack.append((cz + 1, cx * 2, cy * 2))
            stack.append((cz + 1, cx * 2 + 1, cy * 2))
            stack.append((cz + 1, cx * 2, cy * 2 + 1))
            stack.append((cz + 1, cx * 2 + 1, cy * 2 + 1))
    return children


def uris_for_tile(z, x, y, groups):
    """
    Generate all nginx cache URIs for a given tile coordinate.

    For each group, generates:
      - Composite: /maps/{group}/{z}/{x}/{y}.pbf
      - Per-layer: /maps/{group}/{layer}/{z}/{x}/{y}.pbf
    """
    uris = []
    for group_name, functions in groups.items():
        uris.append(f"/maps/{group_name}/{z}/{x}/{y}.pbf")
        for fn in functions:
            uris.append(f"/maps/{group_name}/{fn}/{z}/{x}/{y}.pbf")
    return uris


def purge_tiles_from_nginx(tiles):
    """
    Delete nginx cache files for the given tile coordinates.

    Args:
        tiles: set of (z, x, y) tuples

    Returns:
        dict with deleted, not_found, total_tiles counts
    """
    groups = load_group_functions()
    all_tiles = set(tiles)

    # Add parent tiles (down to NGINX_PURGE_PARENT_MIN_ZOOM)
    if Config.NGINX_PURGE_PARENT_ZOOMS:
        for z, x, y in list(tiles):
            for pz, px, py in get_parent_tiles(z, x, y, Config.NGINX_PURGE_PARENT_MIN_ZOOM):
                all_tiles.add((pz, px, py))

    # Add child tiles (up to NGINX_PURGE_CHILD_MAX_ZOOM)
    for z, x, y in list(tiles):
        for cz, cx, cy in get_child_tiles(z, x, y, Config.NGINX_PURGE_CHILD_MAX_ZOOM):
            all_tiles.add((cz, cx, cy))

    deleted = 0
    not_found = 0

    for z, x, y in all_tiles:
        for uri in uris_for_tile(z, x, y, groups):
            fpath = cache_file_path(uri)
            try:
                os.remove(fpath)
                deleted += 1
            except FileNotFoundError:
                not_found += 1
            except OSError as e:
                logger.warning(f"Error removing {fpath}: {e}")

    return {
        "deleted": deleted,
        "not_found": not_found,
        "total_tiles": len(all_tiles),
    }


def purge_tiles_from_nginx_by_bbox(tiles_list, path_files=None):
    """
    Purge nginx cache for a list of mercantile.Tile objects (from /clean-cache endpoint).

    Args:
        tiles_list: list of mercantile.Tile (z, x, y)
        path_files: ignored for nginx backend (kept for API compatibility with S3)

    Returns:
        dict with deleted, errors, total_tiles_processed counts
    """
    tile_set = {(t.z, t.x, t.y) for t in tiles_list}
    result = purge_tiles_from_nginx(tile_set)
    return {
        "deleted": result["deleted"],
        "errors": 0,
        "total_tiles_processed": result["total_tiles"],
    }


def purge_full_nginx():
    """Delete all files from the nginx cache directory."""
    deleted = 0
    cache_dir = Config.NGINX_CACHE_DIR
    if not os.path.exists(cache_dir):
        return 0
    for root, dirs, files in os.walk(cache_dir):
        for fname in files:
            try:
                os.remove(os.path.join(root, fname))
                deleted += 1
            except OSError:
                pass
    logger.info(f"[FULL PURGE] Deleted {deleted} files from {cache_dir}")
    return deleted
