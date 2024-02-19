#!/bin/bash

# This script doesn't do the wait-for song and dance so if there are sporadic database errors,
# try making sure the databases are fully up and running again.
docker compose run --rm test cover -ignore_re '^t/' +ignore_re '^post' -test -make 'prove -r t/; exit $?'
