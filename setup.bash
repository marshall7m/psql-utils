#!/bin/bash

yarn install

# chmod u+x ./docker-pgsql-entrypoint/entrypoint.sh
docker-compose up --detach

docker-compose run testing /bin/bash