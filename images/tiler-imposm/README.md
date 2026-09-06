# Tiler imposm

This container is responsible to import the replication PBF files from osm-seed or OSM planet dump into the `tiler-db`

If we are running the container for the first time the container will import the [OSM Land](http://data.openstreetmapdata.com/land-polygons-split-3857.zip) and [Natural Earth dataset](http://nacis.org/initiatives/natural-earth) and [osm-land] files into the data bases. [Check more here](https://github.com/go-spatial/tegola-osm#import-the-osm-land-and-natural-earth-dataset-requires-gdal-natural-earth-can-be-skipped-if-youre-only-interested-in-osm).


### Layers

The imposm mapping and the SQL of the materialized views live together per layer in
[`layers/`](./layers/README.md). `layers.yaml` fixes the build order. `scripts/layers.py` generates the
imposm config, the SQL order and the refresh groups from them.

On start, `start.sh` imports the layers whose tables are missing in the database (new layers), builds
their views and then runs the minute diffs. To reimport a single layer by hand, see the layers README.

### Configuration

In order to run this container we need environment variables, these can be found in the following files👇:

- [.env.tiler-db.example](./../../envs/.env.tiler-db.example)
- [.env.tiler-imposm.example](./../../envs/.env.tiler-imposm.example)

**Note**: Rename the above files as `.env.tiler-db` and `.env.tiler-imposm`

#### Running tiler-imposm container

```sh
    # Docker compose
    docker-compose run tiler-imposm

    # Docker
    docker run \
      --env-file ./envs/.env.tiler-db \
      --env-file ./envs/.env.tiler-imposm \
      -v ${PWD}/data/tiler-imposm-data:/mnt/data \
      --network osm-seed_default \
      -it osmseed-tiler-imposm:v1
```

