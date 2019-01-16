# METTLE: Ethereum Schema Files

This project houses the ddl and some sample data from the Ethereum chain for a MYSQL database.

These DDL scripts add the following objects:
SCHEMA: mettle\_ethereum
USER: eth/eth
TABLES: blocks, contracts, logs, receipts, token\_transfers, tokens, traces, transactions

## Creating a Database 

* Ensure you have established your my.cnf file (/usr/local/etc on mac osx) with local-infile=1 and disable-log-bin=1
```
[mysqld]
# Only allow connections from localhost
bind-address = 127.0.0.1
local-infile=1
disable-log-bin=1
```

* To create the database, be in a shell having access to a mysql client and run:
```
$ cd bin
$ ./create.sh
# enter your mysql root password
```

* To load data into the database:
```
$ cd bin
$ ./load.sh
# enter your mysql root password
```

# Other Errata

## Generate partitions and load commands for lots of files:

``` for f in $(find extracted/blocks -name '*.csv' | sort ); 
do 
    echo "LOAD DATA LOCAL INFILE '$f' REPLACE INTO TABLE \`blocks\` COLUMNS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\\n' IGNORE 1 LINES;"
done
```

## Example Load Data Command

```
 LOAD DATA LOCAL INFILE 'output/blocks/start_block=00000000/end_block=00099999/blocks_00000000_00099999.csv' 
 REPLACE INTO TABLE `blocks` 
 COLUMNS TERMINATED BY ',' 
 LINES TERMINATED BY '\n' 
 IGNORE 1 LINES;
```

## Shell command

```
$ mysql --database=mettle_ethereum --local-infile -u eth -p < load.mysql
```
