#!/bin/bash
#set -x
#############################################################
# Cacti restore script. This script attempts to install a few
# packages needed to eventually restore cacti's files and DB. You
# must first create /opt/cacti and then untar the 
# cacti-backup-package.tgz
# 
# hmoats 20191224
#
#############################################################
FILES=/opt/cacti
RESTOREBACKUP=$FILES/backup

#############################################################
# You have to determine this by looking at RESTOREBACKUP and
# see which backup you want to restore. Likely you want the 
# prior day or whatever is in RESTOREBACKUP.
echo -n "Enter day number [1-7] to backup: "
read DOW

echo -n "Please enter your cacti database password: " 
read -s DBPASS

BACKUPFILES=cacti_files_${DOW}.tgz
BACKUPDB=cacti_database_${DOW}.sql.gz

# Let's check for those files
if [[ -f "$FILES/cacti-0.8.8h.tar.gz" && \
  -f "$RESTOREBACKUP/$BACKUPFILES" && \
  -f "$RESTOREBACKUP/$BACKUPDB" ]]
then
  echo "Files check done."
else
  echo "Can't find required files. Exiting."
  exit 1
fi

echo "We are attempting to install cacti and some other dependencies"
echo "and then restore $BACKUPFILES and $BACKUPDB"

#############################################################
echo "Install mariadb and start service."
#
/bin/yum -y install mariadb-server
/bin/systemctl start mariadb

#############################################################
echo "Execute mysql secure install sql"
#
/bin/mysql -u root << EOF
  UPDATE mysql.user SET Password=PASSWORD('$DBPASS') WHERE User='root';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
EOF

#############################################################
echo "Install httpd and start"
#
/bin/yum -y install httpd httpd-devel
/bin/systemctl start httpd

#############################################################
echo "Install various packages for cacti, spine, snmp, rrdtoo, php, etc."
#
/bin/yum -y install net-snmp net-snmp-utils net-snmp-libs rrdtool php php-ldap php-mysql php-pear php-common php-gd php-devel php-mbstring php-cli php-intl php-snmp gcc mysql-devel net-snmp-devel autoconf automake libtool dos2unix help2man smokeping

#############################################################
echo "Start snmpd"
#
/bin/systemctl start snmpd

#############################################################
echo "Create cacti table" 
#
/bin/mysql -u root -p$DBPASS << EOF
CREATE database cacti;
CREATE USER 'cactiuser'@'localhost' IDENTIFIED BY '$DBPASS';
GRANT ALL PRIVILEGES ON cacti.* to cactiuser@localhost;
FLUSH PRIVILEGES;
EOF

#############################################################
echo "Timezone info"
#
/bin/mysql -u root -p$DBPASS mysql < /usr/share/mysql/mysql_test_data_timezone.sql
/bin/mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root -p$DBPASS mysql

#############################################################
echo "Update timezone info"
# 
/bin/mysql -u root -p$DBPASS << 'EOF'
GRANT SELECT ON mysql.time_zone_name TO cactiuser@localhost;
FLUSH PRIVILEGES;
EOF

#############################################################
echo "Add timezone to mysqld section"
#
/bin/sed -i "/\[mysqld\]/ a default-time-zone='US/Pacific'" /etc/my.cnf

#############################################################
echo "Update timezone in php"
#
/bin/sed -i 's/;date.timezone =/date.timezone = US\/Pacific/g' /etc/php.ini

#############################################################
echo "Unpackage cacti-version and then link it to cacti"
#
cd /var/www/html/
cp $FILES/cacti-0.8.8h.tar.gz /var/www/html/
tar -xzvf cacti-0.8.8h.tar.gz
ln -s cacti-0.8.8h cacti

#############################################################
echo "Run cacti sql"
#
/bin/mysql -u root -p$DBPASS cacti < /var/www/html/cacti/cacti.sql

#############################################################
echo "Update cacti config msql password"
#
/bin/sed -i "s/\$database_password = \"cactiuser\";/\$database_password = \"$DBPASS\";/g" /var/www/html/cacti/include/config.php

#############################################################
echo "Add user cactiuser and set some permissions"
#
adduser --groups apache cactiuser
chown -R cactiuser.apache /var/www/html/cacti/ 
chmod -R 775 /var/www/html/cacti/rra/
chmod -R 775 /var/www/html/cacti/log/
chmod -R 775 /var/www/html/cacti/resource/
chmod -R 775 /var/www/html/cacti/scripts/
setfacl -d -m group:apache:rw /var/www/html/cacti/rra 
setfacl -d -m group:apache:rw /var/www/html/cacti/log
chown -R cactiuser:cactiuser /opt/cacti

#############################################################
echo "Add crontab for cactiuser"
#
echo '*/5 * * * * cactiuser /usr/bin/php /var/www/html/cacti/poller.php > /dev/null 2>&1' > /etc/cron.d/cacti
echo '0 1 * * * cactiuser /opt/cacti/cacti-backup.sh > /dev/null 2>&1' >> /etc/cron.d/cacti
echo '0 2 * * * cactiuser /bin/php -q /var/www/html/cacti/cli/poller_graphs_reapply_names.php -id=All -d > /dev/null 2>&1' >> /etc/cron.d/cacti

#############################################################
echo "Restoring backup"
cd /
tar -xzvf $RESTOREBACKUP/$BACKUPFILES
cd $RESTOREBACKUP
gunzip $BACKUPDB
mysql -u cactiuser -p$DBPASS cacti < $(echo $BACKUPDB | sed 's/\.gz//')

#############################################################
echo "Restarting services"
#
systemctl restart mariadb.service
systemctl restart httpd.service

