#! /bin/bash

# Apache gets grumpy about PID files pre-existing
if [ ! -d /tmp/apache2 ]
then
  mkdir -p /tmp/apache2/{run,lock,log}
fi

rm -f /tmp/apache2/apache2*.pid

export APACHE_PID_FILE=/tmp/apache2/run/apache2.pid
export APACHE_RUN_DIR=/tmp/apache2/run
export APACHE_LOCK_DIR=/tmp/apache2/lock
export APACHE_LOG_DIR=/tmp/apache2/log

# Won't be effective if we pass user from docker-compose; that's OK - hence
# shenanigans above
export APACHE_RUN_USER=www-data
export APACHE_RUN_GROUP=www-data

exec apache2 -DFOREGROUND
