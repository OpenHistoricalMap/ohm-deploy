"""Varnish cache invalidation via BAN requests.

Sends BAN requests to Varnish to invalidate cached tiles when imposm
expire files arrive. One BAN per batch of tiles, regardless of size.
"""
import os
from typing import List

import mercantile
import requests

from utils.utils import get_logger

logger = get_logger()

VARNISH_URL = os.getenv("VARNISH_URL", "http://varnish:6081")
ENABLE_VARNISH_PURGE = os.getenv("ENABLE_VARNISH_PURGE", "true").lower() == "true"
VARNISH_BAN_TIMEOUT = int(os.getenv("VARNISH_BAN_TIMEOUT", "5"))
VARNISH_TILE_URL_PREFIX = os.getenv("VARNISH_TILE_URL_PREFIX", "/maps/ohm")
VARNISH_MAX_TILES_PER_REQUEST = int(os.getenv("VARNISH_MAX_TILES_PER_REQUEST", "500"))


def _chunks(items, size):
    for i in range(0, len(items), size):
        yield items[i : i + size]


def ban_tiles(tiles: List[mercantile.Tile]) -> bool:
    """Send BAN request(s) to Varnish invalidating the given tiles.

    Returns True if all BAN requests succeeded, False otherwise. Failures
    are non-fatal: Varnish's TTL acts as a safety net.
    """
    if not ENABLE_VARNISH_PURGE:
        return True
    if not tiles:
        return True

    all_ok = True
    for chunk in _chunks(tiles, VARNISH_MAX_TILES_PER_REQUEST):
        tile_patterns = "|".join(f"{t.z}/{t.x}/{t.y}" for t in chunk)
        regex = f"^{VARNISH_TILE_URL_PREFIX}/({tile_patterns})\\.pbf$"
        try:
            r = requests.request(
                "BAN",
                f"{VARNISH_URL}/",
                headers={"X-Ban-Regex": regex},
                timeout=VARNISH_BAN_TIMEOUT,
            )
            if r.status_code == 200:
                logger.info(f"Varnish BAN ok: {len(chunk)} tiles")
            else:
                logger.warning(f"Varnish BAN status={r.status_code}: {r.text[:200]}")
                all_ok = False
        except Exception as e:
            logger.warning(f"Varnish BAN failed (TTL is fallback): {e}")
            all_ok = False

    return all_ok
