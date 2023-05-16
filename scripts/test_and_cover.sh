#!/bin/bash

/usr/local/bin/wait-for --timeout=300 mariadb:3306
/usr/local/bin/wait-for --timeout=30 mariadb_ht:3306
cover -test -ignore_re '^t/' +ignore_re '^post' -report Coveralls -make 'prove -r t/; exit $?'
