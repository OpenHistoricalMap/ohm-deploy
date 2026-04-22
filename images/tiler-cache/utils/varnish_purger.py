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
VARNISH_TILE_URL_PREFIX = os.getenv(
    "VARNISH_TILE_URL_PREFIX",
    "/maps/ohm,/maps/ohm_admin,/maps/ohm_other_boundaries",
)
VARNISH_MAX_TILES_PER_REQUEST = int(os.getenv("VARNISH_MAX_TILES_PER_REQUEST", "200"))

_TILE_URL_PREFIXES = [p.strip() for p in VARNISH_TILE_URL_PREFIX.split(",") if p.strip()]
_TILE_URL_PREFIX_GROUP = "(?:" + "|".join(re.escape(p) for p in _TILE_URL_PREFIXES) + ")"

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


def _prefixes_for_x_range(z: int, x_lo: int, x_hi: int) -> Set[str]:
    """Unique z/x_prefix strings for x in [x_lo, x_hi].

    Walks x by jumping to the next x that would change the truncated prefix,
    so the work scales with the number of prefixes, not the width of the range.
    """
    out: Set[str] = set()
    x = x_lo
    while x <= x_hi:
        out.add(_tile_to_prefix(z, x))
        s = str(x)
        if len(s) <= 2:
            x += 1
        elif len(s) == 3:
            x = (x // 10 + 1) * 10
        else:
            x = (x // 100 + 1) * 100
    return out


def _expand_tile_prefixes(z: int, x: int, zoom_levels: Iterable[int]) -> Set[str]:
    """Expand a tile to z/x_prefix strings for parents + same zoom + children.

    Children expansion is bounded by max(zoom_levels) — the caller-supplied
    list is the authoritative range. Prefixes at each child zoom are generated
    directly from the x-range instead of iterating every child tile.
    """
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

    for cz in range(z + 1, zmax + 1):
        if cz not in zooms:
            continue
        factor = 2 ** (cz - z)
        x_lo = x * factor
        x_hi = x_lo + factor - 1
        out.update(_prefixes_for_x_range(cz, x_lo, x_hi))

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
        regex = f"^{_TILE_URL_PREFIX_GROUP}/({patterns})(\\.pbf)?$"
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
        regex = f"^{_TILE_URL_PREFIX_GROUP}/({'|'.join(chunk)})[0-9]*/[0-9]+(\\.pbf)?$"
        if not _send_ban(regex, len(chunk)):
            all_ok = False
    return all_ok
