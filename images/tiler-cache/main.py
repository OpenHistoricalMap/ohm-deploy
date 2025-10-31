"""Endpoint to clean tile cache in S3 based on OpenHistoricalMap changeset or point with buffer."""

import os
import requests
import xml.etree.ElementTree as ET
import mercantile
import math
from typing import List, Optional
from fastapi import FastAPI, HTTPException, Query
from config import Config
from utils.utils import get_logger

app = FastAPI()
logger = get_logger()


def fetch_changeset(changeset_id: int, api_base_url: str = "https://www.openhistoricalmap.org") -> dict:
    """Fetches the changeset from the API and extracts the bbox."""
    url = f"{api_base_url}/api/0.6/changeset/{changeset_id}"
    
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        
        root = ET.fromstring(response.content)
        changeset_elem = root.find('changeset')
        
        if changeset_elem is None:
            raise HTTPException(status_code=404, detail=f"Changeset {changeset_id} not found")
        
        bbox_str = (
            changeset_elem.get('min_lon'),
            changeset_elem.get('min_lat'),
            changeset_elem.get('max_lon'),
            changeset_elem.get('max_lat')
        )
        
        if None in bbox_str:
            raise HTTPException(status_code=400, detail=f"Changeset {changeset_id} does not have a valid bbox")
        
        bbox = {
            'min_lon': float(bbox_str[0]),
            'min_lat': float(bbox_str[1]),
            'max_lon': float(bbox_str[2]),
            'max_lat': float(bbox_str[3])
        }
        
        logger.info(f"Changeset {changeset_id} bbox: {bbox}")
        return bbox
        
    except requests.RequestException as e:
        raise HTTPException(status_code=500, detail=f"Error fetching changeset: {str(e)}")
    except (ET.ParseError, ValueError) as e:
        raise HTTPException(status_code=500, detail=f"Error parsing changeset: {str(e)}")


def calculate_bbox_from_point(lat: float, lon: float, buffer_meters: float) -> dict:
    """
    Calculates a bbox from a point with a buffer in meters.
    
    Args:
        lat: Point latitude
        lon: Point longitude
        buffer_meters: Buffer in meters
        
    Returns:
        Dict with 'min_lon', 'min_lat', 'max_lon', 'max_lat'
    """
    EARTH_RADIUS_M = 6371000.0
    lat_rad = math.radians(lat)
    lon_rad = math.radians(lon)
    # Calculate displacement in degrees for latitude (approximately constant)
    lat_delta = math.degrees(buffer_meters / EARTH_RADIUS_M)
    # Calculate displacement in degrees for longitude (depends on latitude)
    lon_delta = math.degrees(buffer_meters / (EARTH_RADIUS_M * math.cos(lat_rad)))
    
    bbox = {
        'min_lon': lon - lon_delta,
        'min_lat': lat - lat_delta,
        'max_lon': lon + lon_delta,
        'max_lat': lat + lat_delta
    }
    
    logger.info(f"Bbox from point ({lat}, {lon}) with {buffer_meters}m buffer: {bbox}")
    return bbox


def get_tiles_in_bbox(bbox: dict, zoom_levels: List[int]) -> List[mercantile.Tile]:
    """Calculates all tiles that intersect with the bbox for the specified zoom levels."""
    tiles = []
    for zoom in zoom_levels:
        bbox_tiles = mercantile.tiles(
            bbox['min_lon'], bbox['min_lat'],
            bbox['max_lon'], bbox['max_lat'],
            zooms=zoom
        )
        tiles.extend(list(bbox_tiles))
    
    logger.info(f"Found {len(tiles)} tiles in bbox for zoom levels {zoom_levels}")
    return tiles


def delete_tiles_from_s3(tiles: List[mercantile.Tile], path_files: List[str]) -> dict:
    """Deletes tiles from S3 in batches of 1000 objects."""
    s3_client = Config.get_s3_client()
    bucket_name = Config.S3_BUCKET_CACHE_TILER
    
    tile_extensions = ['.pbf', '']
    keys_to_delete = []
    
    for tile in tiles:
        for path_file in path_files:
            for ext in tile_extensions:
                keys_to_delete.append(f"{path_file}/{tile.z}/{tile.x}/{tile.y}{ext}")
    
    if not keys_to_delete:
        return {'deleted': 0, 'errors': 0, 'total_tiles_processed': 0}
    
    logger.info(f"Prepared {len(keys_to_delete)} tile keys to delete from S3")
    
    batch_size = 1000
    total_deleted = 0
    total_errors = 0
    
    for i in range(0, len(keys_to_delete), batch_size):
        batch = keys_to_delete[i:i + batch_size]
        delete_objects = [{'Key': key} for key in batch]
        
        try:
            response = s3_client.delete_objects(
                Bucket=bucket_name,
                Delete={'Objects': delete_objects, 'Quiet': False}
            )
            
            deleted = response.get('Deleted', [])
            errors = response.get('Errors', [])
            
            total_deleted += len(deleted)
            total_errors += len(errors)
            
            if errors:
                for error in errors:
                    logger.warning(f"Error deleting {error.get('Key')}: {error.get('Message')}")
            
            logger.info(f"Batch {i // batch_size + 1}: Deleted {len(deleted)}, Errors {len(errors)}")
            
        except Exception as e:
            logger.error(f"Error deleting batch {i // batch_size + 1}: {e}")
            total_errors += len(batch)
    
    return {
        'deleted': total_deleted,
        'errors': total_errors,
        'total_tiles_processed': len(keys_to_delete)
    }


@app.get("/health")
def health():
    """Health check that validates both HTTP server and SQS processor."""
    import time
    import os
    
    heartbeat_file = "/tmp/sqs_processor_heartbeat"
    heartbeat_timeout = 60
    # Check if SQS processor is alive
    sqs_healthy = False
    sqs_last_heartbeat = None
    
    try:
        if os.path.exists(heartbeat_file):
            with open(heartbeat_file, 'r') as f:
                last_heartbeat_time = float(f.read().strip())
                current_time = time.time()
                time_since_heartbeat = current_time - last_heartbeat_time
                
                if time_since_heartbeat <= heartbeat_timeout:
                    sqs_healthy = True
                    sqs_last_heartbeat = time_since_heartbeat
                else:
                    logger.warning(f"SQS processor heartbeat too old: {time_since_heartbeat:.1f} seconds")
        else:
            logger.warning("SQS processor heartbeat file not found")
    except Exception as e:
        logger.error(f"Error checking SQS processor heartbeat: {e}")
    
    # If SQS processor is not healthy, return error
    if not sqs_healthy:
        raise HTTPException(
            status_code=503,
            detail=f"SQS processor not responding (last heartbeat: {sqs_last_heartbeat:.1f}s ago)" if sqs_last_heartbeat else "SQS processor heartbeat not found"
        )
    
    return {
        "status": "healthy",
        "sqs_processor": "alive",
        "sqs_last_heartbeat_seconds_ago": round(sqs_last_heartbeat, 1) if sqs_last_heartbeat else None
    }


@app.get("/clean-cache")
def clean_cache_by_changeset(
    changeset_id: Optional[int] = Query(None, description="OpenHistoricalMap changeset ID"),
    lat: Optional[float] = Query(None, description="Point latitude"),
    lon: Optional[float] = Query(None, description="Point longitude"),
    buffer_meters: Optional[float] = Query(None, description="Buffer in meters around the point"),
    zoom_levels: Optional[str] = Query(None, description="Zoom levels separated by comma (e.g., 18,19,20)"),
    api_base_url: str = Query("https://www.openhistoricalmap.org", description="OpenHistoricalMap API base URL")
):
    """
    Cleans tile cache in S3.
    
    Can use:
    1. changeset_id: Gets the bbox from the changeset
    2. lat/lon/buffer_meters: Calculates a bbox from a point with buffer
    """
    try:
        # Validate parameters
        if not changeset_id and not (lat is not None and lon is not None):
            raise HTTPException(
                status_code=400,
                detail="Must provide 'changeset_id' or 'lat' and 'lon'"
            )
        
        if changeset_id and (lat is not None or lon is not None):
            raise HTTPException(
                status_code=400,
                detail="Must provide 'changeset_id' OR 'lat/lon', not both"
            )
        
        if lat is not None and lon is not None and buffer_meters is None:
            raise HTTPException(
                status_code=400,
                detail="When using 'lat' and 'lon', must provide 'buffer_meters'"
            )
        
        # Determine zoom levels
        if zoom_levels:
            zoom_list = [int(z.strip()) for z in zoom_levels.split(',')]
        else:
            zoom_list = Config.ZOOM_LEVELS_TO_DELETE
        
        # Get bbox based on method used
        if changeset_id:
            logger.info(f"Processing changeset {changeset_id} with zoom levels {zoom_list}")
            bbox = fetch_changeset(changeset_id, api_base_url)
            source_info = {"type": "changeset", "changeset_id": changeset_id}
        else:
            logger.info(f"Processing point ({lat}, {lon}) with {buffer_meters}m buffer, zoom levels {zoom_list}")
            bbox = calculate_bbox_from_point(lat, lon, buffer_meters)
            source_info = {"type": "point", "lat": lat, "lon": lon, "buffer_meters": buffer_meters}
        
        # Calculate tiles and delete
        tiles = get_tiles_in_bbox(bbox, zoom_list)
        
        if not tiles:
            return {
                "success": True,
                "source": source_info,
                "bbox": bbox,
                "tiles_count": 0,
                "deleted": 0
            }
        
        delete_stats = delete_tiles_from_s3(tiles, Config.S3_BUCKET_PATH_FILES)
        
        return {
            "success": True,
            "source": source_info,
            "bbox": bbox,
            "tiles_count": len(tiles),
            "delete_stats": delete_stats
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

