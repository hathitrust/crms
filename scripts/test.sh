#!/bin/bash

perl /htapps/babel/crms/Makefile.PL
/usr/local/bin/wait-for --timeout=300 mariadb:3306
/usr/local/bin/wait-for --timeout=30 mariadb_ht:3306
make test TEST_VERBOSE=1
