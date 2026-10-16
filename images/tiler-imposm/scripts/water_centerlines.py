#!/usr/bin/env python3
"""
Generate centerlines for elongated named water bodies (#1374).

Reads candidate polygons from osm_water_areas, builds a centerline from the
Voronoi skeleton of the polygon outline (same idea as openmaptiles/osm-lakelines)
and stores it in the water_areas_centerlines table. Only geometry is stored
here; names and dates are joined from osm_water_areas by osm_id in the mviews.

Runs incrementally: polygons whose geometry hash did not change are skipped,
and rows for polygons that are no longer candidates are removed.

Usage:
  python3 scripts/water_centerlines.py            # update the table
  python3 scripts/water_centerlines.py --dry-run  # write GeoJSON to stdout, no DB writes
"""
import argparse
import json
import logging
import os
import sys

import networkx as nx
import numpy as np
import psycopg2
import shapely
from scipy.ndimage import gaussian_filter1d
from scipy.spatial import Voronoi
from shapely import wkb
from shapely.geometry import LineString, MultiLineString, mapping

TABLE = "water_areas_centerlines"

# Minimum polygon area in m2 and minimum elongation ratio, defined as
# polygon area / area of the maximum inscribed circle. A circle is 1,
# Lake Tahoe ~2.4, Lake Mead ~11.8.
MIN_AREA = float(os.getenv("CENTERLINE_MIN_AREA", "10000000"))
MIN_RATIO = float(os.getenv("CENTERLINE_MIN_RATIO", "5"))
# Number of outline points per polygon used to build the Voronoi diagram.
OUTLINE_POINTS = int(os.getenv("CENTERLINE_OUTLINE_POINTS", "5000"))
# Ignore MultiPolygon parts smaller than this share of the total area.
MIN_PART_SHARE = float(os.getenv("CENTERLINE_MIN_PART_SHARE", "0.1"))
# Gaussian smoothing of the output line, in number of vertices.
SMOOTH_SIGMA = float(os.getenv("CENTERLINE_SMOOTH_SIGMA", "3"))

# Rivers already get labels along waterway lines, so skip them.
CANDIDATES_SQL = """
SELECT DISTINCT ON (osm_id)
    osm_id,
    md5(ST_AsBinary(geometry)) AS geom_hash,
    ST_AsBinary(geometry) AS geom
FROM osm_water_areas
WHERE name <> ''
  AND area > %(min_area)s
  AND type NOT IN ('river', 'riverbank')
  AND COALESCE(tags->'water', '') NOT IN
      ('river', 'riverbank', 'canal', 'stream', 'ditch', 'drain', 'moat', 'wastewater')
  AND ST_GeometryType(geometry) IN ('ST_Polygon', 'ST_MultiPolygon')
  AND ST_Area(geometry) / NULLIF(
        pi() * power((ST_MaximumInscribedCircle(
            ST_SimplifyPreserveTopology(geometry, 100))).radius, 2), 0
      ) >= %(min_ratio)s
ORDER BY osm_id, area DESC
"""

CREATE_SQL = f"""
CREATE TABLE IF NOT EXISTS {TABLE} (
    osm_id BIGINT PRIMARY KEY,
    geom_hash TEXT NOT NULL,
    geometry geometry(Geometry, 3857) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS {TABLE}_geom_idx ON {TABLE} USING GIST (geometry);
"""

UPSERT_SQL = f"""
INSERT INTO {TABLE} (osm_id, geom_hash, geometry, updated_at)
VALUES (%s, %s, ST_SetSRID(ST_GeomFromWKB(%s), 3857), now())
ON CONFLICT (osm_id) DO UPDATE
SET geom_hash = EXCLUDED.geom_hash,
    geometry = EXCLUDED.geometry,
    updated_at = now()
"""

log = logging.getLogger("water_centerlines")


def connect():
    return psycopg2.connect(
        host=os.environ["POSTGRES_HOST"],
        port=os.getenv("POSTGRES_PORT", "5432"),
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        options="-c statement_timeout=0",
    )


def polygon_centerline(polygon):
    """Longest path through the Voronoi skeleton of a polygon."""
    # Sample the outline (islands included) every `seg` meters.
    seg = polygon.exterior.length / OUTLINE_POINTS
    polygon = polygon.simplify(seg / 2)
    boundary_len = polygon.exterior.length + sum(r.length for r in polygon.interiors)
    seg = max(boundary_len / OUTLINE_POINTS, 1.0)
    points = np.unique(
        shapely.get_coordinates(shapely.segmentize(polygon.boundary, seg)), axis=0
    )
    if len(points) < 4:
        raise ValueError("too few outline points")

    # Keep only Voronoi edges fully inside the polygon: that is the skeleton.
    vor = Voronoi(points)
    ridges = np.array([r for r in vor.ridge_vertices if r[0] >= 0 and r[1] >= 0])
    shapely.prepare(polygon)
    ridges = ridges[shapely.contains(polygon, shapely.linestrings(vor.vertices[ridges]))]
    if len(ridges) == 0:
        raise ValueError("empty skeleton")

    graph = nx.Graph()
    lengths = np.linalg.norm(vor.vertices[ridges[:, 0]] - vor.vertices[ridges[:, 1]], axis=1)
    graph.add_weighted_edges_from(zip(ridges[:, 0], ridges[:, 1], lengths))
    largest = max(nx.connected_components(graph),
                  key=lambda c: graph.subgraph(c).size(weight="weight"))
    graph = graph.subgraph(largest)

    # The skeleton is close to a tree, so its longest path is found with two
    # Dijkstra runs: farthest node from any node, then farthest from that one.
    dist = nx.single_source_dijkstra_path_length(graph, next(iter(graph.nodes)))
    start = max(dist, key=dist.get)
    dist, paths = nx.single_source_dijkstra(graph, start)
    end = max(dist, key=dist.get)

    xy = vor.vertices[paths[end]]
    if SMOOTH_SIGMA and len(xy) > 3:
        xy = np.column_stack([
            gaussian_filter1d(xy[:, 0], SMOOTH_SIGMA, mode="nearest"),
            gaussian_filter1d(xy[:, 1], SMOOTH_SIGMA, mode="nearest"),
        ])
    return LineString(xy).simplify(seg / 2)


def build_centerline(geom):
    if geom.geom_type == "Polygon":
        return polygon_centerline(geom)

    # Process each large part on its own and keep the ones that succeed.
    lines = []
    for part in geom.geoms:
        if part.area < geom.area * MIN_PART_SHARE:
            continue
        try:
            lines.append(polygon_centerline(part))
        except ValueError as e:
            log.debug("part skipped: %s", e)
    if not lines:
        raise ValueError("all parts failed")
    return lines[0] if len(lines) == 1 else MultiLineString(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true",
                        help="print GeoJSON (EPSG:3857) to stdout, do not write to the DB")
    parser.add_argument("--osm-id", type=int, action="append",
                        help="only process these osm_ids (repeatable)")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s - %(message)s",
        stream=sys.stderr,
    )

    conn = connect()
    cur = conn.cursor()

    if not args.dry_run:
        cur.execute(CREATE_SQL)
        conn.commit()

    log.info("Fetching candidates (min_area=%s, min_ratio=%s)", MIN_AREA, MIN_RATIO)
    cur.execute(CANDIDATES_SQL, {"min_area": MIN_AREA, "min_ratio": MIN_RATIO})
    candidates = cur.fetchall()
    if args.osm_id:
        candidates = [c for c in candidates if c[0] in args.osm_id]
    log.info("Candidates: %s", len(candidates))

    existing = {}
    if not args.dry_run:
        cur.execute(f"SELECT osm_id, geom_hash FROM {TABLE}")
        existing = dict(cur.fetchall())

    features = []
    done = skipped = failed = 0
    for osm_id, geom_hash, geom_wkb in candidates:
        if existing.get(osm_id) == geom_hash:
            skipped += 1
            continue
        try:
            line = build_centerline(wkb.loads(bytes(geom_wkb)))
        except Exception as e:
            failed += 1
            log.warning("osm_id %s failed: %s", osm_id, e)
            continue

        if args.dry_run:
            features.append({"type": "Feature",
                             "properties": {"osm_id": osm_id},
                             "geometry": mapping(line)})
        else:
            cur.execute(UPSERT_SQL, (osm_id, geom_hash, psycopg2.Binary(line.wkb)))
            conn.commit()
        done += 1

    if args.dry_run:
        json.dump({"type": "FeatureCollection", "features": features}, sys.stdout)
    elif not args.osm_id:
        # Drop centerlines of polygons that were deleted or are no longer candidates.
        keep = [c[0] for c in candidates]
        cur.execute(f"DELETE FROM {TABLE} WHERE NOT (osm_id = ANY(%s))", (keep,))
        log.info("Removed: %s", cur.rowcount)
        conn.commit()

    log.info("Generated: %s, unchanged: %s, failed: %s", done, skipped, failed)
    conn.close()


if __name__ == "__main__":
    main()
