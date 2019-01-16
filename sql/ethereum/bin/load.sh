#!/bin/bash

if [ ! -x $(which mysql) ]; then
  echo No mysql client available. Exiting.
  exit 1
fi

echo Enter your mysql root user password to load data
(cd ../data && mysql --local-infile --database=mettle_ethereum -u root -p < load.mysql)

