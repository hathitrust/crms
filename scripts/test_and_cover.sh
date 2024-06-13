#!/bin/bash

cover -test -ignore_re '^t/' +ignore_re '^post' -report Coveralls -make 'prove -r t/; exit $?'
