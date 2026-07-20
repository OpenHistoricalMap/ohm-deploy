# Nominatim (OHM custom image)

Based on `mediagis/nominatim:4.5` and the osm-seed Nominatim image, with OHM
customizations:

- `ohm-import.lua`: custom import style that extends the standard `extratags`
  style. It indexes `type=street` relations
  ([#1308](https://github.com/OpenHistoricalMap/issues/issues/1308)),
  `type=collection` relations
  ([#452](https://github.com/OpenHistoricalMap/issues/issues/452)) and
  `type=route` + `route=railway` relations by name.
- `address-levels.json`: OHM search and address ranks, baked into the image.
  This directory is the source of truth for the file; changing it requires an
  image rebuild.

The import style only applies at import time and during replication updates.
Street and collection relations that already exist in the database are not
indexed until they are edited or the database is reimported from a planet
file.

### Log outputs in the container

```
/var/log/replication.log
/var/log/cron.log
```
