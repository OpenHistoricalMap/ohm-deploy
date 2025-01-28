## Development Mode

- Web Api

```sh
docker compose -f compose/web.yml up memcached
docker compose -f compose/web.yml build
docker compose -f compose/web.yml run --service-ports web bash
```

- Tiler server

```sh
docker compose -f compose/tiler.yml run --service-ports tiler bash
```
