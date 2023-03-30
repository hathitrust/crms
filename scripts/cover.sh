#!/bin/bash

docker-compose run --rm test cover -test -make 'prove -r t/; exit $?'
