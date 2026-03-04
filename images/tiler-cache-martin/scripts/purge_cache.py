#!/usr/bin/env python3
"""
Purge nginx tile cache selectively using imposm's expired tile lists.

Nginx stores cache files with MD5-hashed filenames based on the cache key (URI).
This script reads expired tile coordinates (z/x/y), constructs the matching URIs,
computes their MD5 hashes, and deletes the corresponding cache files.

Usage:
  Full purge:           python3 purge_cache.py --full
  From expired file:    python3 purge_cache.py --file /path/to/expired.tiles
  From expired dir:     python3 purge_cache.py --dir /mnt/data/imposm3_expire_dir
  Single tile:          python3 purge_cache.py --tile 14/8192/5461

The expired tile file format (from imposm -expiretiles-dir):
  14/8192/5461
  14/8193/5461
  15/16384/10922

Environment:
  CACHE_DIR             nginx cache path (default: /var/cache/nginx/tiles)
  CACHE_LEVELS          nginx cache levels (default: 1:2)
  NGINX_GROUPS          comma-separated group names (default: ohm,ohm_admin)
  PURGE_PARENT_ZOOMS    also purge parent tiles up to z0 (default: true)
"""

import hashlib
import json
import os
import sys
import glob as glob_module
from pathlib import Path

CACHE_DIR = os.environ.get("CACHE_DIR", "/var/cache/nginx/tiles")
CACHE_LEVELS = os.environ.get("CACHE_LEVELS", "1:2")
NGINX_GROUPS = os.environ.get("NGINX_GROUPS", "ohm,ohm_admin").split(",")
PURGE_PARENT_ZOOMS = os.environ.get("PURGE_PARENT_ZOOMS", "true").lower() == "true"
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "config", "functions.json")


def load_group_functions():
    """Load function names per group from functions.json."""
    try:
        with open(CONFIG_PATH) as f:
            config = json.load(f)
        groups = {}
        for g in config.get("groups", []):
            groups[g["name"]] = [fn["function_name"] for fn in g["functions"]]
        return groups
    except Exception:
        return {name: [] for name in NGINX_GROUPS}


def cache_file_path(uri):
    """
    Compute the nginx cache file path for a given URI.

    nginx uses MD5(key) and stores files using the 'levels' directory structure.
    For levels=1:2, the file path is:
      {cache_dir}/{last_1_char}/{next_2_chars}/{full_md5_hash}

    Example:
      URI: /maps/ohm/5/10/12.pbf
      MD5: d41d8cd98f00b204e9800998ecf8427e
      Path: /var/cache/nginx/tiles/e/27/d41d8cd98f00b204e9800998ecf8427e
    """
    md5 = hashlib.md5(uri.encode()).hexdigest()
    levels = CACHE_LEVELS.split(":")
    parts = []
    pos = len(md5)
    for level in reversed(levels):
        n = int(level)
        pos -= n
        parts.insert(0, md5[pos:pos + n])
    return os.path.join(CACHE_DIR, *parts, md5)


def get_parent_tiles(z, x, y):
    """Get all parent tiles from z down to z0."""
    parents = []
    while z > 0:
        z -= 1
        x //= 2
        y //= 2
        parents.append((z, x, y))
    return parents


def uris_for_tile(z, x, y, groups):
    """
    Generate all nginx cache URIs for a given tile coordinate.

    For each group, generates:
      - Composite: /maps/{group}/{z}/{x}/{y}.pbf
      - Per-layer: /maps/{group}/{layer}/{z}/{x}/{y}.pbf (for each function)
    """
    uris = []
    for group_name, functions in groups.items():
        # Composite route
        uris.append(f"/maps/{group_name}/{z}/{x}/{y}.pbf")
        # Per-layer routes
        for fn in functions:
            uris.append(f"/maps/{group_name}/{fn}/{z}/{x}/{y}.pbf")
    return uris


def parse_tile_line(line):
    """Parse a tile line in format z/x/y."""
    line = line.strip()
    if not line or line.startswith("#"):
        return None
    parts = line.split("/")
    if len(parts) != 3:
        return None
    try:
        return int(parts[0]), int(parts[1]), int(parts[2])
    except ValueError:
        return None


def read_expired_files(path):
    """Read tile coordinates from a file or directory of expired tile files."""
    tiles = set()
    if os.path.isdir(path):
        for fpath in sorted(glob_module.glob(os.path.join(path, "**", "*"), recursive=True)):
            if os.path.isfile(fpath):
                with open(fpath) as f:
                    for line in f:
                        tile = parse_tile_line(line)
                        if tile:
                            tiles.add(tile)
    elif os.path.isfile(path):
        with open(path) as f:
            for line in f:
                tile = parse_tile_line(line)
                if tile:
                    tiles.add(tile)
    return tiles


def purge_tiles(tiles, groups):
    """Delete nginx cache files for the given tiles."""
    deleted = 0
    not_found = 0
    all_tiles = set(tiles)

    # Add parent tiles if enabled
    if PURGE_PARENT_ZOOMS:
        for z, x, y in list(tiles):
            for pz, px, py in get_parent_tiles(z, x, y):
                all_tiles.add((pz, px, py))

    for z, x, y in all_tiles:
        for uri in uris_for_tile(z, x, y, groups):
            fpath = cache_file_path(uri)
            if os.path.exists(fpath):
                try:
                    os.remove(fpath)
                    deleted += 1
                except OSError:
                    pass
            else:
                not_found += 1

    return deleted, not_found, len(all_tiles)


def purge_full():
    """Delete all cache files."""
    deleted = 0
    cache_path = Path(CACHE_DIR)
    if not cache_path.exists():
        return 0
    for fpath in cache_path.rglob("*"):
        if fpath.is_file():
            try:
                fpath.unlink()
                deleted += 1
            except OSError:
                pass
    return deleted


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"error": "usage: purge_cache.py --full | --file PATH | --dir PATH | --tile z/x/y"}))
        sys.exit(1)

    mode = sys.argv[1]

    if mode == "--full":
        deleted = purge_full()
        print(json.dumps({"status": "purged", "mode": "full", "files_deleted": deleted}))

    elif mode in ("--file", "--dir"):
        if len(sys.argv) < 3:
            print(json.dumps({"error": f"missing path for {mode}"}))
            sys.exit(1)
        path = sys.argv[2]
        tiles = read_expired_files(path)
        if not tiles:
            print(json.dumps({"status": "skip", "reason": "no expired tiles found", "path": path}))
            return
        groups = load_group_functions()
        deleted, not_found, total_tiles = purge_tiles(tiles, groups)
        print(json.dumps({
            "status": "purged",
            "mode": "selective",
            "expired_tiles": len(tiles),
            "total_tiles_with_parents": total_tiles,
            "cache_files_deleted": deleted,
            "cache_files_not_cached": not_found,
        }))

    elif mode == "--tile":
        if len(sys.argv) < 3:
            print(json.dumps({"error": "missing tile z/x/y"}))
            sys.exit(1)
        tile = parse_tile_line(sys.argv[2])
        if not tile:
            print(json.dumps({"error": f"invalid tile format: {sys.argv[2]}"}))
            sys.exit(1)
        groups = load_group_functions()
        deleted, not_found, total_tiles = purge_tiles({tile}, groups)
        print(json.dumps({
            "status": "purged",
            "mode": "single",
            "tile": sys.argv[2],
            "total_tiles_with_parents": total_tiles,
            "cache_files_deleted": deleted,
        }))

    else:
        print(json.dumps({"error": f"unknown mode: {mode}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
