#!/usr/bin/env bash

BINPATH=`dirname $0`
cd $BINPATH/..
docker compose run --rm test /bin/bash -c "npm install && npm run build"

errVal=$?
if [ $errVal -ne 0 ]
then
  exit $errVal
fi

echo "crms build done"
