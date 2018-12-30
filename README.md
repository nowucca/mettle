# Table of Contents
- [METTLE](#mettle)
- [Ethereum](#ethereum)
	- [Aws Setup](#aws-setup)
		- [Database Instance](#database-instance)
		- [Chain Node Instance](#chain-node-instance)
	- [Running Mettle/Ethereum](#running-mettle/ethereum)
- [Reference Links](#reference-links)


# METTLE
<a name="mettle"></a>

Mettle is short for Multi-chain Text Transform And Load Engine.

This project extracts multiple blockchains’ blocks, states, transactions, receipts, token details into a relational database for further use by analytic engines.

This document describes the project, it’s architecture and engineering requirements.

We will be running one or more nodes for each chain we are interested in, along with an extraction process dumping files into a storage area.  The stored files will then be made available for importing into a mysql relational database.

The process will be incremental, using MySQL partitions so that we can import objects of interest from the chains (blocks, transactions, states, tokens etc) as they arrive, or process in larger batches to backfill information.  

# Ethereum
<a name="ethereum"></a>

Let’s describe how to set up and run METTLE for the Ethereum blockchain.

## Aws Setup
<a name="aws-setup"></a>

Create an AWS account.
Create an IAM user with administrative role (for using s3 on the command line).
Create an s3 bucket.

Create two instances using Ubuntu 18.04.
For all instances, I keep the first disk volume to be a basic 8 GiB volume for the OS and scratch data.  

Create two volumes of EBS storage.

The first volume is to temporarily store Ethereum chain data.
Blocks alone require 4.8GiB of storage, I used 500GiB as a guess.
Let’s call this the **extraction** volume.

The second volume is to serve as the data directory for MySQL, and for temporarily holding copies of data files to load into MySQL.  The data requirements here are more interesting, I would use a Terabyte to start with.
Let’s call the **database** volume.


METTLE uses two instances for extracting Ethereum chain data. The first is chain node instance that runs a Ethereum node and mounts the extraction volume, and the second is a database instance on which the MySQL database runs and mounts the database volume.
 
The following setup steps need to be done for each instance.
Perhaps we should make an AMI so we don’t have to do this all the time.

For each instance: follow the [instructions about installing Python on Ubuntu 18.04](https://www.digitalocean.com/community/tutorials/how-to-install-python-3-and-set-up-a-programming-environment-on-ubuntu-18-04-quickstart) but do not worry about virtualized issues, because this is a specific virtual machine already.  Then install awscli using pip3 install awscli --upgrade --user and/or follow the [instructions for installing the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-linux.html) .  You will need an IAM administrative user with an access key and a secret access token to use the awscli command line.  

### Database Instance
<a name="database-instance"></a>

This node is an Ubuntu 18.04 node.
I have tried this with a t2.xlarge image size.
4 million blocks imported in 2 minutes, so that seems about right.

Let’s use the standard ubuntu user.

Mount the **database** volume under /apps.  This will hold the database directory and temporary copies of extracted text for importing.

Install a copy of the latest MySQL database (8.0.13 at time of writing).
This seems to start with getting the latest APT repository config deb package from [this official MySQL page](https://www.tecmint.com/install-mysql-8-in-ubuntu/).  Once that is done, I highly recommend following [the instructions on this TecMint site](https://www.tecmint.com/install-mysql-8-in-ubuntu/), substituting the name of the latest deb config package for their first step. 

What you will then have is a mysql database with a data directory running in /var/lib/mysql/.  We would like the data (and the error log directory) to instead be on the database volume at /apps/mettle/database/mysql/.  To arrange for that on mysql is not hard but a little involved and the details are clearly laid out in [this wonderful guide to moving a MySQL data folder](https://www.digitalocean.com/community/tutorials/how-to-move-a-mysql-data-directory-to-a-new-location-on-ubuntu-16-04).  I’d say while you are editing /etc/mysql/mysql.conf.d/mysqld.conf consider:
- Add local-infile=1 to allow local file imports.  Critical.
- Add disable-log-bin=1 to stop binary logging.  Saves space unless you need replication it is not needed.
- Consider setting the error log to /apps/mettle/database/log/error.log to make diagnosis easier / in the same folder.

Let’s set up permissions so that the default ubuntu group can read/write /apps/mettle and all files underneath.

### Chain Node Instance
<a name="chain-node-instance"></a>

This node is an Ubuntu 18.04 node.
I have tried this with a t2.large image size.
This instance could benefit from more CPU and RAM as it maxed out while exporting blocks and transactions. 

Let’s use the standard ubuntu user.
Mount the **extraction** volume under /apps.
Create ~/.ethereum as a soft link to /apps/mettle/ethereum/geth.ethereum/.
The extracted files can live in /apps/mettle/ethereum/extracted/.

We then install a Go-Ethereum “geth” node - [see Geth installation](https://github.com/ethereum/go-ethereum/wiki/Installation-Instructions-for-Ubuntu "Go-Ethereum (Geth) installation Guide for Ubuntu").  
It will put all it’s data into ~.ethereum which will be on the extraction volume.

We then make sure the geth instance is operating correctly.
We are now roughly following the guidelines shown on [Evgeny Medvedev’s “Exporting and Analyzing Ethereum Blockchain”.](https://medium.com/@medvedev1088/exporting-and-analyzing-ethereum-blockchain-f5353414a94e)


Finally let’s clone  git clone https://github.com/medvedev1088/ethereum-etl into /apps/mettle/ethereum/ethereum-etl so we can store our extraction scripts next to our chain data and our extracted data.  Use pip3 install ethereum-etl to install the Ethereum scripts into the python system on this instance.

## Running Mettle/Ethereum
<a name="running-mettle/ethereum"></a>

On the chain node, we are going to run geth, wait for data to sync for a while, then run extraction scripts from the ethereumetl project to extract data.

To run geth, go to the ubuntu user home directory and run
```bash
> nohup geth --cache=1024 &
```
Data will start syncing to  /apps/mettle/ethereum/geth.ethereum/.
Monitor ~/nohup.out for geth output.

You can attach to the geth process and see the syncing state:
```bash
geth attach

> eth.syncing
```

It takes a while to sync blocks I waited for 4 million for a few hours, and then started to export the CSV files using ethereumetl python scripts.  You can export everything or hack the export-all script in  ethereumetl/jobs/export\_all\_common.py to just do blocks to test things.  You may have to reinstall using pip if you do that, I don’t know.

To run the extraction scripts once data has synced, go to  /apps/mettle/ethereum/ethereum-etl.
```bash
nohup bash export_all.sh -s 0 -e 3999999 -b 100000 -p file://$HOME/.ethereum/geth.ipc -o output &
```

This is soon going to change to :
```bash
nohup ethereumetl export_all --start-block 0 --end-block 3999999 --batch-size 100000 \
--provider-uri file://$HOME/.ethereum/geth.ipc -o /apps/mettle/ethereum/extracted
```
Monitor /apps/mettle/ethereum/ethereum-etl/nohup.out for script output.

You should now have files in  /apps/mettle/ethereum/extracted.
We are going to bounce them onto S3 storage to transfer them to the database volume. 

Ensure you have a bucket established with a mettle/ethereum folder in it.  Then change directory to the  /apps/mettle/ethereum folder on your node instance and run
```bash
aws s3 sync extracted s3://your-bucket-name/mettle/ethereum
```

That should send all the files to your S3 bucket.

On the database node, make a folder /apps/mettle/ethereum copy the s3 bucket files to your local EBS volume under there.

```bash
sudo aws s3 cp s3://your-bucket-name/mettle/ethereum/extracted /apps/mettle.ethereum/extracted/ --recursive
```

Now on this database node we are going to slurp the files in locally into mysql.
This will involve using the sql files provided in this repository.

Test that you can access your mysql database locally.
```bash
  mysql -u root -p
```

Let’s create a user etl/etl…
```bash
  mysql -u root -p < etl-user.mysql
```

Then create the blocks table for example using the new etl user:
```bash
  mysql -u etl -p < etl-blocks.mysql
```
  
Now we can start loading in data from all the files.

We can generate a script to load all the files of a certain table into partitions.
Assuming we focus on blocks we can generate a file using a Bash script:
```bash
# Run in /apps/mettle/ethereum
<a name="run-in-/apps/mettle/ethereum"></a>
for f in $(find extracted/blocks -name '*.csv' | sort ); do echo "LOAD DATA LOCAL INFILE '$f' REPLACE INTO TABLE \`blocks\` COLUMNS TERMINATED BY ',' LINES TERMINATED BY '\\n' IGNORE 1 LINES;" ; done > etl-blocks-data.mysql
```

The command will look like:
```bash
 mysql --local-infile -u etl -p < etl-blocks-data.mysql
```

We can repeat the process for  transactions and other objects.



# Reference Links
<a name="reference-links"></a>

## AWS
<a name="aws"></a>
* [Amazon Web Services Sign-In](https://signin.aws.amazon.com/signin?redirect_uri=https://console.aws.amazon.com/ec2/v2/home?state=hashArgs%23&isauthcode=true&client_id=arn:aws:iam::015428540659:user/ec2&forceMobileApp=0) 
* [EC2 Management Console](https://us-west-1.console.aws.amazon.com/ec2/v2/home?region=us-west-1#Instances:sort=instanceState) 
* [Creating an IAM User in Your AWS Account - AWS Identity and Access Management](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html) 
* [Making an Amazon EBS Volume Available for Use on Linux - Amazon Elastic Compute Cloud](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-using-volumes.html) 
* [How to Attach and Mount an EBS volume to EC2 Linux Instance](https://devopscube.com/mount-ebs-volume-ec2-instance/) 
* [AWS Command Line Interface](https://aws.amazon.com/cli/) 
* [Configuring the AWS CLI - AWS Command Line Interface](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html) 
* [amazon web services - AWS CLI S3: copying file locally using the terminal : fatal error: An error occurred (404) when calling the HeadObject operation - Stack Overflow](https://stackoverflow.com/questions/45109533/aws-cli-s3-copying-file-locally-using-the-terminal-fatal-error-an-error-occu)

## Ethereum ETL
<a name="ethereum-etl"></a>
* [Ethereum ETL Github](https://github.com/blockchain-etl/ethereum-etl)
* [Evegeny’s article on Extracting CSVs](https://medium.com/@medvedev1088/exporting-and-analyzing-ethereum-blockchain-f5353414a94e)
* [Geth Instructions for Ubuntu](https://github.com/ethereum/go-ethereum/wiki/Installation-Instructions-for-Ubuntu%0A)
* [How to make a pipeline in AWS for Ethereum-ETL](https://medium.com/@medvedev1088/how-to-export-the-entire-ethereum-blockchain-to-csv-in-2-hours-for-10-69fef511e9a2)
* [Exposing Ethereum Data using BigQuery](%0Ahttps://cloud.google.com/blog/products/data-analytics/ethereum-bigquery-how-we-built-dataset)
	* [Another Big Query Ethereum article](https://medium.com/google-cloud/how-to-query-balances-for-all-ethereum-addresses-in-bigquery-fb594e4034a7)
* [Converting CSV files to Parquet format to save money in the cloud ](%0Ahttps://medium.com/@medvedev1088/converting-ethereum-etl-files-to-parquet-399e048ddd30%20)

## MySql
<a name="mysql"></a>

* [How to import CSV file to MySQL table - Stack Overflow](https://stackoverflow.com/questions/3635166/how-to-import-csv-file-to-mysql-table) 
* [Install MySQL 8.0 On Ubuntu 16.04](https://websiteforstudents.com/install-mysql-8-0-on-ubuntu-16-04-17-10-18-04/) 
* [How To Move a MySQL Data Directory to a New Location on Ubuntu 16.04 | DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-move-a-mysql-data-directory-to-a-new-location-on-ubuntu-16-04) 
* [How to import CSV file to MySQL table - Stack Overflow](https://stackoverflow.com/questions/3635166/how-to-import-csv-file-to-mysql-table)
*  [MySQL :: MySQL 8.0 Reference Manual :: 13.2.7 LOAD DATA INFILE Syntax](https://dev.mysql.com/doc/refman/8.0/en/load-data.html) 
* [MySQL :: MySQL 8.0 Reference Manual :: 23.2.1 RANGE Partitioning](https://dev.mysql.com/doc/refman/8.0/en/partitioning-range.html) 
* [MySQL :: MySQL 8.0 Reference Manual :: 5.4.4 The Binary Log](https://dev.mysql.com/doc/refman/8.0/en/binary-log.html) 
* [MySQL :: MySQL 8.0 Reference Manual :: 13.4.1.1 PURGE BINARY LOGS Syntax](https://dev.mysql.com/doc/refman/8.0/en/purge-binary-logs.html) 
* [database - How should I tackle --secure-file-priv in MySQL? - Stack Overflow](https://stackoverflow.com/questions/32737478/how-should-i-tackle-secure-file-priv-in-mysql) 

## Python
<a name="python"></a>

* [How To Install Python 3 and Set Up a Programming Environment on Ubuntu 18.04 [Quickstart] | DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-install-python-3-and-set-up-a-programming-environment-on-ubuntu-18-04-quickstart) 
* [import - ModuleNotFoundError: Python 3.6 does not find modules while Python 3.5 does - Stack Overflow](https://stackoverflow.com/questions/42263962/modulenotfounderror-python-3-6-does-not-find-modules-while-python-3-5-does) 
* [How to Install Python 3.6.1 in Ubuntu 16.04 LTS | UbuntuHandbook](http://ubuntuhandbook.org/index.php/2017/07/install-python-3-6-1-in-ubuntu-16-04-lts/)