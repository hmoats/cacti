#!/bin/bash
#set -x
# Urban-Software.de
# Database Backup Script
#############################################################
# Note! This assumes you have already installed cacti and
# dependencies. Please note you must update %DBPASSWORD% to
# match your environment.
# 
# hmoats 20191224
#############################################################

# Set the backup filename and directory
DATE=`date +%u` # e.g 1-7 day of week
FILENAME="cacti_database_$DATE.sql"
TGZFILENAME="cacti_files_$DATE.tgz"
WORKINGDIR="/opt/cacti"
BACKUPDIR="/opt/cacti/backup"

# Database Credentials
DBUSER="cactiuser"
DBPWD="%DBPASSWORD%"
DBNAME="cacti"

echo "Creating Cacti backup for DOW [$DATE]"

# Where is our gzip tool for compression?
# The -f parameter will make sure that gzip will
# overwrite existing files
GZIP="/bin/gzip -f";

# What files do we want to include?
# Change the directories accordingly!
TARINCLUDE="./var/www/html
./etc/logrotate.d/cacti
./etc/cron.d/cacti
./etc/php.ini
./etc/php.d
./etc/httpd/conf
./etc/httpd/conf.d
./usr/local/spine/etc/spine.conf
./usr/local/spine"

# Which files/directories do we want to EXCLUDE?
TAREXCLUDE="./var/www/html/log"

echo "Delete old database backups older than 30 days"
find $BACKUPDIR/cacti_database*.sql.gz* -mtime +30 -exec rm {} \;
find $BACKUPDIR/cacti_files*.tgz* -mtime +30 -exec rm {} \;

echo "Change to the root directory"
cd /

echo "execute the database dump"
mysqldump --user=$DBUSER --password=$DBPWD --add-drop-table --databases $DBNAME > $BACKUPDIR/$FILENAME

echo "compress the database backup"
$GZIP $BACKUPDIR/$FILENAME

echo "Create the Cacti files backup"
tar -czpf $BACKUPDIR/$TGZFILENAME $TARINCLUDE

echo "Generate MD5 crc"
md5sum $BACKUPDIR/$TGZFILENAME > $BACKUPDIR/$TGZFILENAME.md5
md5sum $BACKUPDIR/$FILENAME.gz > $BACKUPDIR/$FILENAME.gz.md5

echo "Create a install package for new host"
cd $WORKINGDIR
pwd
tar -czvf cacti-backup-package.tgz --exclude=cacti-backup-package.tgz *
