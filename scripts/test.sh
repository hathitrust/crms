#!/bin/bash

cover -test -ignore_re '^t/' +ignore_re '^post' -report html -make 'prove -r t/; exit $?'
