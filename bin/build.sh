#!/usr/bin/env bash

BINPATH=`dirname $0`

if ! command -v npm &>/dev/null
then
  echo "npm could not be found in PATH"
  exit
fi

cd $BINPATH/..
lock_check='yes'
src_check='yes'
if [ -f ./public/scripts/main.js ]
then
  lock_check=`find package-lock.json -newer ./public/scripts/main.js`
  src_check=`find assets -newer ./public/scripts/main.js`
fi

if [ "$lock_check" == "" ]
then
  echo "crms: package-lock.json unchanged; skipping install"
else
  npm install
  errVal=$?
  if [ $errVal -ne 0 ]
  then
    exit $errVal
  fi
fi

if [ "$lock_check" == "" -a "$src_check" == "" ]
then
  echo "crms: app unchanged; skipping build"
else
  npm run build
  errVal=$?
  if [ $errVal -ne 0 ]
  then
    exit $errVal
  fi
fi

echo "crms build done"
