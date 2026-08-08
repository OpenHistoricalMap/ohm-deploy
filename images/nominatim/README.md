# Nominatim (OHM custom image)

Built on `mediagis/nominatim:5.3.2`, which brings PostgreSQL, osm2pgsql and the
import scripts (`config.sh`, `init.sh`, `start.sh`). On top of that base the
image replaces the released `nominatim-db` and `nominatim-api` packages with the
OHM fork:

- Fork: https://github.com/OpenHistoricalMap/Nominatim
- Pinned by `OPENHISTORICALMAP_NOMINATIM_GITSHA` in the `Dockerfile`. Bump that
  sha every time new changes land on the fork, the same way the web image pins
  `OPENHISTORICALMAP_WEBSITE_GITSHA`.

The fork is where OHM changes to Nominatim itself go, for example the date-aware
address calculation from
[#1402](https://github.com/OpenHistoricalMap/issues/issues/1402).

The source is downloaded as a `tar.gz`, not a `zip`: the packages under
`packaging/` are symlinks into the repo root and a zip does not keep them. The
country grid is downloaded as well, because it is a build artifact that the repo
does not carry.

The image also adds the OHM date functions
([DateFunctions-plpgsql](https://github.com/OpenHistoricalMap/DateFunctions-plpgsql))
to the SQL that Nominatim loads with `refresh --functions`, which `start.sh` runs
on every boot. `pad_date` and `isodatetodecimaldate` end up in the Nominatim
database, so a query can turn `extratags->'start_date'` into a decimal date the
same way the tiler does. `DATEFUNCTIONS_GITSHA` in the `Dockerfile` is pinned to
the same commit as `images/tiler-imposm/Dockerfile`; keep both in sync or the
tiler and Nominatim will disagree about the same feature.

OHM customizations that stay in this directory:

- `ohm-import.lua`: custom import style that extends the standard `extratags`
  style. It indexes `type=street` relations
  ([#1308](https://github.com/OpenHistoricalMap/issues/issues/1308)),
  `type=collection` relations
  ([#452](https://github.com/OpenHistoricalMap/issues/issues/452)),
  `type=chronology` relations
  ([#640](https://github.com/OpenHistoricalMap/issues/issues/640)) and
  `type=route` + `route=road` relations by name.
- `address-levels.json`: OHM search and address ranks, baked into the image.
  This directory is the source of truth for the file; changing it requires an
  image rebuild.

The import style only applies at import time and during replication updates.
Street and collection relations that already exist in the database are not
indexed until they are edited or the database is reimported from a planet
file.

### Upgrading an existing database

Nominatim 5 can migrate a database imported with 4.5, so the schema alone does
not force a reimport:

```
nominatim admin --migrate
nominatim refresh --functions
```

That is enough for changes that only affect query time, such as the date-aware
address calculation. It is not enough for changes to `ohm-import.lua` or
`address-levels.json`, which only take effect on import. Plan a full reimport
from a planet file when the import style changes.


### Log outputs in the container

```
/var/log/replication.log
/var/log/cron.log
```
