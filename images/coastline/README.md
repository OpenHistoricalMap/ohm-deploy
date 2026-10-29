# coastline

Builds `land-polygons-split-3857.zip` from the OHM `natural=coastline` ways with [osmcoastline](https://osmcode.org/osmcoastline/). Same format as the [osmdata](https://osmdata.openstreetmap.de/data/land-polygons.html) file the tiler uses today, so edits to coastlines in OHM show up in the map. Issue OpenHistoricalMap/issues#339.

osmcoastline does not read `start_date`/`end_date`, and coastlines from different periods overlap. So `filter_by_date.py` keeps only the ways that exist on `COASTLINE_DATE` (default: today) before running it.

- `scripts/build.sh` planet -> coastline ways -> date filter -> osmcoastline -> checks -> zip. Publishes to `$AWS_S3_BUCKET/$S3_PREFIX/`:
  - `land-polygons-split-3857.zip` land polygons in EPSG:3857, split at `MAX_POINTS`
  - `coastline-errors.zip` `error_points` and `error_lines` as GeoJSON, to fix in the editor
  - `land-polygons-split-3857.json` date, planet, polygon and error counts
- `scripts/load.sh [zip]` loads the zip into `land_polygons_new`, then copies it into `land_polygons` and refreshes the `mview_land_*` views in one transaction.
- `scripts/run.sh` CronJob entry: `build.sh`, then `load.sh` when `LOAD_TILER_DB=true`.

Checks before publishing: osmcoastline exit code 3 fails the run (2 means errors, output is still usable). The run also fails if there are fewer than `MIN_LAND_POLYGONS` polygons, or if the count drops more than `MAX_DROP_PCT` from the last published json. `FORCE=true` skips the drop check.

Manifests: `ohm/templates/coastline/`. Values: `ohmCoastline` in `values.*.template.yaml`. For a new tiler import, set `LAND_POLYGONS_URL` in `tilerImposm.env` to use this zip in `osm_land.sh`.

Run locally:

```bash
docker build -t ohm-coastline .
docker run --rm -v $PWD/data:/data ohm-coastline /app/scripts/build.sh
```

Tile cache is not purged after a load. Low zooms keep old land until their cache expires.
