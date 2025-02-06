# Development Mode


## Web Api

Make a coppy of the enviroment files `envs/.env.web.example` file and name it `envs/.env.web`.

```sh
docker compose -f compose/web.yml build
docker compose -f compose/web.yml up db -d
docker compose -f compose/web.yml up memcached -d
docker compose -f compose/web.yml run --service-ports web bash
```

## Tiler server
Make a coppy of the enviroment files `envs/.env.tiler.example` file and name it `envs/.env.tiler`.

```sh
docker compose -f compose/tiler.yml build
docker compose -f compose/tiler.yml run --service-ports tiler bash
```


## Tasking manager
Make a coppy of the enviroment files `envs/.env.tiler.example` file and name it `envs/.env.tiler`.

```sh
docker compose -f compose/tm.yml run --service-ports tm-web bash
```