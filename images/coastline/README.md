# coastline

Builds the land polygons for the map from the OHM coastlines. Issue OpenHistoricalMap/issues#339.

How it works:

1. Download the OHM planet and keep the `natural=coastline` ways. Dates (`start_date`/`end_date`) are not used yet.
2. Run [osmcoastline](https://osmcode.org/osmcoastline/) to make land polygons. Only closed rings make land.
3. Fill the missing land with the [osmdata](https://osmdata.openstreetmap.de/data/land-polygons.html) polygons. OHM land always wins. OSM fills only where OHM has no land yet. Turn off with `OSM_FILL=false`.
4. Upload to `$AWS_S3_BUCKET/coastline/`:
   - `land-polygons-split-3857.zip` the land polygons
   - `coastline-errors.zip` gaps and errors in the OHM coastlines, to fix in the editor
   - `land-polygons-split-3857.json` counts of the run
5. With `LOAD_TILER_DB=true`, load the zip into `land_polygons` in the tiler DB.

The run stops without publishing if the OHM land drops more than `MAX_DROP_PCT` (default 20%) from the last run. `FORCE=true` skips this check.

Config: `ohmCoastline` in `values.*.template.yaml`. To use this zip in a new tiler import, set `LAND_POLYGONS_URL` in `tilerImposm.env`.

Run locally:

```bash
docker build -t ohm-coastline .
docker run --rm -v $PWD/data:/data ohm-coastline /app/scripts/build.sh
```
