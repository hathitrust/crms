#!/bin/bash

bin/wait-for --timeout=300 mariadb:3306
cover -test -report Coveralls -make 'prove; exit $?'
