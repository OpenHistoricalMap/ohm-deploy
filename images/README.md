# Deploy locally docker images for development

Here is simple instruction to test the containers.

### Build web containers

`docker-compose .yaml` Contains Api database and website

```sh
cd images/
docker-compose up --build
```

### Access to the web containers

```sh
docker-compose exec web bash
# root@de6edd6603d7:/var/www#
```

- Wait couple of minutes and open http://localhost, Follow the [documentation](CONFIGURE.md) for interact with the page in local mode.
