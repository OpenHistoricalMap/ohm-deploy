"""Endpoint to invalidate tiles in Varnish based on OpenHistoricalMap changeset or point with buffer."""

import os
import sys
import threading
import requests
import xml.etree.ElementTree as ET
import mercantile
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import JSONResponse
from config import Config
from utils.utils import get_logger
from utils.varnish_purger import ban_tiles

app = FastAPI()
logger = get_logger()


def fetch_changeset(changeset_id: int, api_base_url: str = "https://www.openhistoricalmap.org") -> dict:
    """Fetches the changeset from the API and extracts the bbox."""
    try:
        response = requests.get(f"{api_base_url}/api/0.6/changeset/{changeset_id}", timeout=30)
        response.raise_for_status()
        cs = ET.fromstring(response.content).find('changeset')
        if cs is None:
            raise HTTPException(status_code=404, detail=f"Changeset {changeset_id} not found")
        bbox = {
            'min_lon': float(cs.get('min_lon')),
            'min_lat': float(cs.get('min_lat')),
            'max_lon': float(cs.get('max_lon')),
            'max_lat': float(cs.get('max_lat'))
        }
        if None in bbox.values():
            raise HTTPException(status_code=400, detail=f"Changeset {changeset_id} does not have a valid bbox")
        return bbox
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching changeset: {str(e)}")
    except (ET.ParseError, ValueError) as e:
        raise HTTPException(status_code=500, detail=f"Error parsing changeset: {str(e)}")


def get_tiles_in_bbox(bbox: dict, zoom_levels: List[int]) -> List[mercantile.Tile]:
    """Calculates all tiles that intersect with the bbox for the specified zoom levels."""
    tiles = []
    for zoom in zoom_levels:
        tiles.extend(mercantile.tiles(bbox['min_lon'], bbox['min_lat'], bbox['max_lon'], bbox['max_lat'], zooms=zoom))
    return tiles


def terminate_process_after_delay(delay=1):
    """Terminate the process after a short delay to allow HTTP response to be sent."""
    import time
    time.sleep(delay)
    logger.error("SQS processor is unhealthy. Terminating main.py process.")
    os._exit(0)


@app.get("/health")
def health():
    """Health check that validates both HTTP server and SQS processor."""
    import time

    hb_file = "/tmp/sqs_processor_heartbeat"
    sqs_status = "starting"
    sqs_last = None
    is_healthy = True

    try:
        if os.path.exists(hb_file):
            t = time.time() - float(open(hb_file).read().strip())
            if t <= 60:
                sqs_status = "alive"
                sqs_last = t
            else:
                sqs_status = f"stale ({t:.1f}s ago)"
                is_healthy = False
        else:
            sqs_status = "no heartbeat file"
            is_healthy = False
    except Exception as e:
        sqs_status = f"error: {str(e)}"
        is_healthy = False

    response_data = {
        "status": "healthy" if is_healthy else "unhealthy",
        "sqs_processor": sqs_status,
        "sqs_last_heartbeat_seconds_ago": round(sqs_last, 1) if sqs_last else None
    }

    if not is_healthy:
        threading.Thread(target=terminate_process_after_delay, daemon=True).start()
        return JSONResponse(status_code=503, content=response_data)

    return response_data


@app.get("/clean-cache")
def clean_cache_by_changeset(
    changeset_id: int = Query(..., description="OpenHistoricalMap changeset ID"),
    zoom_levels: Optional[str] = Query("16,17,18,19,20", description="Zoom levels separated by comma (e.g., 18,19,20)"),
    api_base_url: str = Query("https://www.openhistoricalmap.org", description="OpenHistoricalMap API base URL")
):
    """Invalidates tiles in Varnish for the bbox of the given changeset."""
    try:
        if zoom_levels:
            zoom_list = [int(z.strip()) for z in zoom_levels.split(',')]
            if max(zoom_list) > 20:
                raise HTTPException(status_code=400, detail="Zoom level cannot exceed 20")
            zoom_list = [z for z in zoom_list if z <= 20]
        else:
            zoom_list = [z for z in Config.ZOOM_LEVELS_TO_DELETE if z <= 20]

        bbox = fetch_changeset(changeset_id, api_base_url)
        tiles = get_tiles_in_bbox(bbox, zoom_list)

        if not tiles:
            return {"success": True, "tiles_count": 0}

        return {
            "success": True,
            "tiles_count": len(tiles),
            "varnish_ban_ok": ban_tiles(tiles),
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.exception(f"Error processing cache cleanup")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
