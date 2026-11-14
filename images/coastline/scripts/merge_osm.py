"""Fill the land that OHM does not have yet with the OSM land polygons.

Usage: python3 -I merge_osm.py OHM_DB OSM_SHP OUT_GPKG BUFFER

- Every OHM land polygon is kept.
- OSM pieces that touch no OHM polygon are copied as they are.
- OSM pieces that touch OHM land are cut by it, grown by BUFFER (EPSG:3857
  units), so the OHM coast wins there and the small gaps between both coasts
  do not leave thin OSM slivers around OHM land.

OSM is read in chunks, so memory stays close to the size of the OHM land.
"""
import sys
import time

import numpy as np
import shapely
import pyogrio
from pyogrio import raw

CHUNK = 50000
POLYGONS = (shapely.GeometryType.POLYGON, shapely.GeometryType.MULTIPOLYGON)


def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} [merge_osm.py] {msg}", flush=True)


def read(path, layer=None, skip=0, max_features=None):
    out = raw.read(path, layer=layer, columns=[], skip_features=skip, max_features=max_features)
    return shapely.from_wkb(out[2])


def write(path, geoms, append):
    raw.write(path, shapely.to_wkb(geoms), field_data=[], fields=[], layer="land_polygons",
              driver="GPKG", geometry_type="MultiPolygon", crs="EPSG:3857",
              promote_to_multi=True, append=append)


def cut(piece, near):
    try:
        return shapely.difference(piece, shapely.union_all(near))
    except shapely.errors.GEOSException:
        return shapely.difference(shapely.make_valid(piece), shapely.make_valid(shapely.union_all(near)))


def main():
    ohm_db, osm_shp, out, buffer = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])

    ohm = read(ohm_db, layer="land_polygons")
    log(f"ohm land polygons: {len(ohm)}")
    write(out, ohm, append=False)

    ohm_buf = shapely.buffer(ohm, buffer, quad_segs=2)
    del ohm
    tree = shapely.STRtree(ohm_buf)

    total = pyogrio.read_info(osm_shp)["features"]
    copied = cut_count = dropped = 0
    for skip in range(0, total, CHUNK):
        osm = read(osm_shp, skip=skip, max_features=CHUNK)
        idx_osm, idx_ohm = tree.query(osm, predicate="intersects")
        touched = np.zeros(len(osm), dtype=bool)
        touched[idx_osm] = True

        keep = list(osm[~touched])
        copied += len(keep)

        # idx_osm is sorted, so each OSM piece has one run of OHM hits
        starts = np.flatnonzero(np.r_[True, idx_osm[1:] != idx_osm[:-1]])
        for i, hits in zip(idx_osm[starts], np.split(idx_ohm, starts[1:])):
            rest = cut(osm[i], ohm_buf[hits])
            if shapely.is_empty(rest):
                dropped += 1
                continue
            if shapely.get_type_id(rest) not in POLYGONS:
                rest = shapely.union_all([g for g in shapely.get_parts(rest) if shapely.get_type_id(g) in POLYGONS])
                if shapely.is_empty(rest):
                    dropped += 1
                    continue
            keep.append(rest)
            cut_count += 1

        if keep:
            write(out, np.array(keep, dtype=object), append=True)
        log(f"osm {min(skip + CHUNK, total)}/{total}: copied={copied} cut={cut_count} dropped={dropped}")


if __name__ == "__main__":
    main()
