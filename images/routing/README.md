# routing

GraphHopper with an OHM plugin that stores `start_date`/`end_date` of each way, so routes only use ways that existed on the requested date. Issues #506 and #695.

- `src/` the plugin: `OhmDate` (date conversion, same as the tiler), `OhmDateParser` (stores `ohm_start`/`ohm_end`), `OhmImportRegistry` (registers them).
- `test/` checks `OhmDate` against the tiler conversion. It runs in the Docker build.
- `config/` GraphHopper config and the `car`, `foot`, `horse` and `carriage` profiles.
- `scripts/start.sh` starts the server from the current graph, or builds one first if there is none for this image version.
- `scripts/update.sh` runs from a CronJob: applies replication diffs to the planet, builds a new graph and does a rolling restart of the server.

The volume keeps the planet and the graphs:

```
/data/planet.osm.pbf
/data/graphs/<version>-<timestamp>/
/data/graphs/current -> <version>-<timestamp>
```

`<version>` is a hash of `config/`, `src/` and the GraphHopper version. A graph only loads with the same profiles and encoded values, so after a change the server builds a new graph on start.

Manifests: `ohm/templates/routing/`. Values: `ohmRouting` in `values.*.template.yaml`.

Request:

```bash
curl https://routing.ohmstaging.org/route -H 'Content-Type: application/json' -d '{
  "points": [[2.3222, 48.8366], [2.3822, 48.8766]],
  "profile": "car",
  "custom_model": {"priority": [{"if": "ohm_start > 1900.5 || ohm_end < 1900.5", "multiply_by": "0"}]}
}'
```
