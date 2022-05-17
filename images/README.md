# Deploy locally docker images for development

Here is simple instruction to test the containers.

- Build and start the containers
```sh
cd images/
docker-compose build
```

-  Access to the containers

```sh
docker-compose exec web bash
# root@de6edd6603d7:/var/www#
```


