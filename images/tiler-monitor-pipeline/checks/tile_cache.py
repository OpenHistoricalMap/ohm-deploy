"""Pipeline check: verify tile cache in S3 is up-to-date.

For a sampled element, check if the cached tile in S3 was modified
after the changeset closed_at. If the tile is stale, the cache purge
(SQS → tiler-cache) may have failed.
"""

import mercantile
import psycopg2.extensions
from datetime import datetime, timezone

from config import Config


def _get_element_centroid(conn, elem):
    """Get the centroid (lon, lat) of an element from the tiler DB."""
    osm_id = elem["osm_id"]
    search_id = -osm_id if elem["type"] == "relation" else osm_id

    # Search in the tables where it was found
    found_tables = elem.get("found_in_tables", [])
    if not found_tables:
        return None

    cur = conn.cursor()
    for table in found_tables:
        try:
            quoted = psycopg2.extensions.quote_ident(table, cur)
            cur.execute(
                f"SELECT ST_X(ST_Centroid(ST_Transform(geometry, 4326))), "
                f"ST_Y(ST_Centroid(ST_Transform(geometry, 4326))) "
                f"FROM {quoted} WHERE osm_id = %s LIMIT 1",
                (search_id,),
            )
            row = cur.fetchone()
            if row and row[0] is not None:
                cur.close()
                return {"lon": row[0], "lat": row[1]}
        except Exception:
            conn.rollback()

    cur.close()
    return None


def _get_tile_for_point(lon, lat, zoom):
    """Convert lon/lat to tile z/x/y."""
    tile = mercantile.tile(lon, lat, zoom)
    return {"z": tile.z, "x": tile.x, "y": tile.y}


def _check_tile_in_s3(tile, changeset_closed_at):
    """Check if a cached tile in S3 is stale (older than changeset).

    Returns dict with status and details for each S3 path.
    """
    if not Config.S3_BUCKET_CACHE_TILER:
        return {
            "status": "skipped",
            "message": "S3_BUCKET_CACHE_TILER not configured",
        }

    s3 = Config.get_s3_client()
    bucket = Config.S3_BUCKET_CACHE_TILER
    z, x, y = tile["z"], tile["x"], tile["y"]

    results = []
    stale_paths = []

    for path_prefix in Config.S3_BUCKET_PATH_FILES:
        key = f"{path_prefix}/{z}/{x}/{y}.pbf"
        try:
            resp = s3.head_object(Bucket=bucket, Key=key)
            last_modified = resp["LastModified"]

            # Parse changeset closed_at
            closed_dt = datetime.fromisoformat(
                changeset_closed_at.replace("Z", "+00:00")
            )

            is_stale = last_modified < closed_dt
            result = {
                "path": key,
                "last_modified": last_modified.isoformat(),
                "is_stale": is_stale,
            }
            results.append(result)
            if is_stale:
                stale_paths.append(key)

        except s3.exceptions.ClientError as e:
            if e.response["Error"]["Code"] == "404":
                # Tile not in cache — not stale, tegola will generate on demand
                results.append({
                    "path": key,
                    "last_modified": None,
                    "is_stale": False,
                    "note": "not cached (tegola generates on demand)",
                })
            else:
                results.append({
                    "path": key,
                    "error": str(e),
                })

    if stale_paths:
        return {
            "status": "stale",
            "message": f"Tile cache is stale for: {', '.join(stale_paths)}",
            "tile": tile,
            "details": results,
        }
    else:
        return {
            "status": "ok",
            "message": "Tile cache is up-to-date or not cached",
            "tile": tile,
            "details": results,
        }


def check_tile_cache_for_element(conn, elem_check, changeset_closed_at):
    """Full tile cache verification for a single element.

    Args:
        conn: DB connection
        elem_check: result dict from _check_element_in_db (with found_in_tables)
        changeset_closed_at: ISO timestamp string

    Returns:
        dict with tile cache check results
    """
    osm_id = elem_check["osm_id"]
    elem_type = elem_check["type"]
    zoom = Config.TILE_CHECK_ZOOM

    # Step 1: get geometry from DB
    centroid = _get_element_centroid(conn, elem_check)
    if not centroid:
        return {
            "osm_id": osm_id,
            "type": elem_type,
            "status": "skipped",
            "message": "Could not get geometry from DB",
        }

    # Step 2: calculate tile
    tile = _get_tile_for_point(centroid["lon"], centroid["lat"], zoom)

    # Step 3: check S3 cache
    cache_result = _check_tile_in_s3(tile, changeset_closed_at)

    return {
        "osm_id": osm_id,
        "type": elem_type,
        "centroid": centroid,
        "tile": tile,
        "cache": cache_result,
    }
