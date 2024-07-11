#!/bin/bash

DEST_PREFIX=$1
shift

DEPLOY_DEST=${DEST_PREFIX}babel
DEPLOY_SRC=/htapps/test.babel

INCLUDE=$(cat <<EOT
  $DEPLOY_SRC/bib_rights
  $DEPLOY_SRC/bin
  $DEPLOY_SRC/cgi
  $DEPLOY_SRC/config
  $DEPLOY_SRC/lib
  $DEPLOY_SRC/post_zephir_processing
  $DEPLOY_SRC/prep
  $DEPLOY_SRC/web
EOT
)

EXCLUDE=$(cat <<EOT
  --exclude .github
  --exclude .git
  --exclude .gitignore
  --exclude .gitmodules
  --exclude docker-compose.yml
  --exclude Dockerfile
  --exclude rsync.timestamp
EOT
)

/usr/bin/rsync "$@" $EXCLUDE $INCLUDE $DEPLOY_DEST
