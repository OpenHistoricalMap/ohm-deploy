# Layers

Each directory here is one layer of the tileset. It holds everything imposm needs for the layer:

```
layers/others/
  layer.yaml      what the layer is: tables, SQL files, refresh groups
  mapping.json    the imposm tables of the layer (same format as the imposm3 mapping "tables")
  others.sql      the SQL that builds the materialized views
```

`layers.yaml` (one level up) lists the layers in build order. `scripts/layers.py` reads these files and
produces the imposm mapping, the SQL order and the refresh groups. `tiler-server-martin` and
`tiler-monitor-pipeline` keep their own config and refer to the views by name.

## layer.yaml

```yaml
name: others
description: "Barrier, historic, man_made, power and military features."
tables: [other_areas, other_lines, other_points, other_multilines]   # keys of mapping.json "tables"
sql:                          # runs on every build of the layer, in this order
  - others.sql
sql_init:                     # runs only on the initial import (create_mviews.sh --all=true)
  - admin_boundaries_lines.sql
refresh:                      # groups for refresh_mviews.sh, one background loop each
  - name: OTHERS
    profile: light            # light | heavy (work_mem / maintenance_work_mem)
    interval: 180             # seconds between cycles
    mviews:
      - mv_other_areas_z8_9
```

Tables are prefixed with `osm_` in the database (`other_lines` -> `osm_other_lines`).

## Commands

Run them from `images/tiler-imposm`.

```sh
python3 scripts/layers.py check          # validate the manifests
python3 scripts/layers.py imposm         # config/imposm3.json (start.sh does this on every start)
python3 scripts/layers.py sql others     # SQL files of a layer, in order
python3 scripts/layers.py refresh        # refresh groups
```

## Add a layer

1. Create `layers/<name>/` with `layer.yaml`, `mapping.json` and the SQL files.
2. Add `<name>` to `layers.yaml` in the position where its SQL must run.
3. `python3 scripts/layers.py check`.
4. If the layer has new views for the map, add the tile function to
   `images/tiler-server-martin/config/functions.json`.
5. Deploy. On start, `start.sh` sees that the tables of the layer are missing, imports only
   that layer from the PBF and builds its views. No full reimport is needed.

## Update one layer

Set one of these env vars on the imposm container and restart it. `start.sh` does the work before
starting the minute diffs, and remembers the value in `/mnt/data/*.done` so a later restart does not
repeat it. Change or clear the value to run it again.

| change | env var | what runs on start |
|---|---|---|
| `mapping.json` (new column or tag) | `REIMPORT_LAYERS: "others"` | reimport of the layer tables from the PBF, then its views |
| SQL only (view columns, filters, zooms) | `REBUILD_MVIEWS: "others,routes"` | the views of those layers |
| every view | `REBUILD_MVIEWS: "all"` (or `RECREATE_MVIEWS_ON_UPDATE: "true"`) | all views, like the initial import |

Restart tiler-server-martin afterwards if a view got new columns.

The same by hand inside the container:

```sh
./scripts/reimport_layer.sh others        # tables of the layer, from /mnt/data/osm.pbf
./scripts/create_mviews.sh others routes  # views of the given layers
```

After a manual reimport, always rebuild the views of that layer before reimporting it again: the old
views still point at the previous tables (moved to the `backup` schema) and imposm cannot drop those
tables while views depend on them. Then restart the container so `imposm run` starts clean.
