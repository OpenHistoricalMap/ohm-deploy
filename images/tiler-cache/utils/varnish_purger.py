"""Varnish cache invalidation via BAN requests.

Sends BAN requests to Varnish to invalidate cached tiles when imposm
expire files arrive.
"""
import os
import re
from typing import Iterable, List, Set

import mercantile
import requests

from utils.utils import get_logger

logger = get_logger()

VARNISH_URL = os.getenv("VARNISH_URL", "http://varnish:6081")
VARNISH_BAN_TIMEOUT = int(os.getenv("VARNISH_BAN_TIMEOUT", "5"))
VARNISH_TILE_URL_PREFIX = os.getenv("VARNISH_TILE_URL_PREFIX", "/maps/ohm")
VARNISH_MAX_TILES_PER_REQUEST = int(os.getenv("VARNISH_MAX_TILES_PER_REQUEST", "200"))
# Limit child-zoom expansion depth to avoid CPU blowup for low-zoom tiles.
# factor = 2^depth, so 6 => up to 64 iterations per tile per zoom level.
VARNISH_MAX_ZOOM_EXPANSION = int(os.getenv("VARNISH_MAX_ZOOM_EXPANSION", "6"))

_TILE_RE = re.compile(r"^(\d+)/(\d+)/(\d+)")


def _chunks(items, size):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def _tile_to_prefix(z: int, x: int) -> str:
    """Return a z/x_prefix truncated like the S3 cleaner does.

    x_str <= 2 chars: keep as-is ; 3 chars: drop last ; 4+ chars: drop last 2.
    """
    x_str = str(x)
    if len(x_str) <= 2:
        return f"{z}/{x_str}"
    if len(x_str) == 3:
        return f"{z}/{x_str[:-1]}"
    return f"{z}/{x_str[:-2]}"


def _expand_tile_prefixes(z: int, x: int, zoom_levels: Iterable[int]) -> Set[str]:
    """Expand a tile to z/x_prefix strings for parents + same zoom + children."""
    zooms = set(zoom_levels)
    if not zooms:
        return set()
    zmin, zmax = min(zooms), max(zooms)
    out: Set[str] = set()

    if z in zooms:
        out.add(_tile_to_prefix(z, x))

    px = x
    for pz in range(z - 1, zmin - 1, -1):
        px //= 2
        if pz in zooms:
            out.add(_tile_to_prefix(pz, px))

    effective_zmax = min(zmax, z + VARNISH_MAX_ZOOM_EXPANSION)
    for cz in range(z + 1, effective_zmax + 1):
        if cz not in zooms:
            continue
        factor = 2 ** (cz - z)
        for dx in range(factor):
            out.add(_tile_to_prefix(cz, x * factor + dx))

    return out


def _send_ban(regex: str, n_patterns: int) -> bool:
    try:
        r = requests.request(
            "BAN",
            f"{VARNISH_URL}/",
            headers={"X-Ban-Regex": regex},
            timeout=VARNISH_BAN_TIMEOUT,
        )
        if r.status_code == 200:
            logger.info(f"Varnish BAN ok: {n_patterns} patterns")
            return True
        logger.warning(f"Varnish BAN status={r.status_code}: {r.text[:200]}")
        return False
    except Exception as e:
        logger.warning(f"Varnish BAN failed (TTL is fallback): {e}")
        return False


def ban_tiles(tiles: List[mercantile.Tile]) -> bool:
    """Send BAN request(s) to Varnish for the exact tiles given (no zoom expansion)."""
    if not tiles:
        return True
    all_ok = True
    for chunk in _chunks(list(tiles), VARNISH_MAX_TILES_PER_REQUEST):
        patterns = "|".join(f"{t.z}/{t.x}/{t.y}" for t in chunk)
        regex = f"^{VARNISH_TILE_URL_PREFIX}/({patterns})\\.pbf$"
        if not _send_ban(regex, len(chunk)):
            all_ok = False
    return all_ok


def ban_tile_strings(tile_strings: Iterable[str], zoom_levels: Iterable[int]) -> bool:
    """Send BAN request(s) to Varnish for tiles from an imposm expire file.

    Uses prefix-based regex matching (same strategy as the S3 cleaner):
    each tile z/x/y becomes z/x_prefix where x_prefix drops the last 1-2 digits.
    Parents + same zoom + children are expanded and deduplicated.
    This over-invalidates a bit but the regex stays compact.
    """
    prefixes: Set[str] = set()
    for tile_str in tile_strings:
        m = _TILE_RE.match(tile_str)
        if not m:
            logger.warning(f"Skipping invalid tile format: {tile_str}")
            continue
        z, x, _y = (int(g) for g in m.groups())
        prefixes.update(_expand_tile_prefixes(z, x, zoom_levels))

    if not prefixes:
        return True

    logger.info(
        f"Varnish BAN: {len(prefixes)} prefixes across zooms "
        f"{min(zoom_levels)}-{max(zoom_levels)}"
    )

    all_ok = True
    sorted_prefixes = sorted(prefixes)
    for chunk in _chunks(sorted_prefixes, VARNISH_MAX_TILES_PER_REQUEST):
        regex = f"^{VARNISH_TILE_URL_PREFIX}/({'|'.join(chunk)})[0-9]*/[0-9]+\\.pbf$"
        if not _send_ban(regex, len(chunk)):
            all_ok = False
    return all_ok
