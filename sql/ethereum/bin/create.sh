#!/bin/bash

if [ ! -x $(which mysql) ]; then
  echo No mysql client available. Exiting.
  exit 1
fi

echo Enter your mysql root password for prompts below
(cd ../ddl && mysql -u root -p < ddl.mysql)

