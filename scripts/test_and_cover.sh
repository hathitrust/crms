#!/bin/bash

/usr/local/bin/wait-for --timeout=300 mariadb:3306
/usr/local/bin/wait-for --timeout=30 mariadb_ht:3306
cover -test -report Coveralls -make 'prove; exit $?'
