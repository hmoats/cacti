#!/bin/bash
#set -x
#############################################################
# Cacti install on Centos (3.10.0-862.3.2.el7.x86_64). This
# install script is particular to my environment. Some steps
# here may not work in your install. 
#
# hmoats 20191224
#
#############################################################
# The files you'll need here are:
#
# 1. cacti-0.8.8h.tar.gz
# 2. cacti-spine-0.8.8h.tar.gz
# 3. network-weathermap-version-0.98a.tar.gz
# 4. thold-v0.5.0.tgz
# 5. superlinks-v1.4-2.tgz
#
# All of these files should be placed in this directory on your
# Centos host. 
FILES=/opt/cacti

# First, let's get your database password
echo -n "Please enter your cacti database password: " 
read -s DBPASS

# Let's fail on any error
set -e

# Let's check for those files
if [[ -f "$FILES/cacti-0.8.8h.tar.gz" && \
  -f "$FILES/network-weathermap-version-0.98a.tar.gz" && \
  -f "$FILES/cacti-spine-0.8.8h.tar.gz" && \
  -f "$FILES/thold-v0.5.0.tgz" && \
  -f "$FILES/superlinks-v1.4-2.tgz" ]]
then
  echo "Files check done."
else 
  echo "Can't find required files. Exiting."
  exit 1
fi

#############################################################
echo "Install mariadb and start service."
#
/bin/yum -y install mariadb-server
/bin/systemctl start mariadb

#############################################################
echo "Execute mysql secure install sql."
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
cp $FILES/cacti-0.8.8h.tar.gz /var/www/html/
cd /var/www/html/
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
echo "Add user cactiuser"
#
adduser --groups apache cactiuser
chown -R cactiuser.apache /var/www/html/cacti/ 
chmod -R 775 /var/www/html/cacti/rra/
chmod -R 775 /var/www/html/cacti/log/
chmod -R 775 /var/www/html/cacti/resource/
chmod -R 775 /var/www/html/cacti/scripts/
setfacl -d -m group:apache:rw /var/www/html/cacti/rra 
setfacl -d -m group:apache:rw /var/www/html/cacti/log

#############################################################
echo "Add crontab for cactiuser"
#
echo '*/5 * * * * cactiuser /usr/bin/php /var/www/html/cacti/poller.php > /dev/null 2>&1' > /etc/cron.d/cacti
echo '0 1 * * * cactiuser /opt/cacti/cacti-backup.sh > /dev/null 2>&1' >> /etc/cron.d/cacti
echo '0 2 * * * cactiuser /bin/php -q /var/www/html/cacti/cli/poller_graphs_reapply_names.php -id=All -d > /dev/null 2>&1' >> /etc/cron.d/cacti

############################################################
echo "Install the spine poller"
#
cd $FILES
tar -xzvf cacti-spine-0.8.8h.tar.gz
cd cacti-spine-0.8.8h
./bootstrap
./configure
make
make install
chown root:root /usr/local/spine/bin/spine
chmod +s /usr/local/spine/bin/spine
cp /usr/local/spine/etc/spine.conf.dist /usr/local/spine/etc/spine.conf
sed -i "s/DB_Pass         cactiuser/DB_Pass         $DBPASS/g" /usr/local/spine/etc/spine.conf
cp /usr/local/spine/etc/spine.conf /etc/spine.conf

###########################################################
echo "Install plugins"
#
cp $FILES/network-weathermap-version-0.98a.tar.gz /var/www/html/cacti/plugins/
cp $FILES/settings-v0.71-1.tgz /var/www/html/cacti/plugins/
cp $FILES/thold-v0.5.0.tgz /var/www/html/cacti/plugins/
cp $FILES/superlinks-v1.4-2.tgz /var/www/html/cacti/plugins/
cd /var/www/html/cacti/plugins/
tar -xzvf network-weathermap-version-0.98a.tar.gz
ln -s network-weathermap-version-0.98a weathermap
tar -xzvf settings-v0.71-1.tgz
tar -xzvf thold-v0.5.0.tgz
tar -xzvf superlinks-v1.4-2.tgz

###########################################################
echo "Restarting services"
#
systemctl restart mariadb.service
systemctl restart httpd.service

echo "You're not done yet. You need to now login to cacti."
echo "Then you need to intall the plugins using the plugin"
echo "management module in the webUI. Then you need to specify"
echo "the path to spine (/usr/local/spine/bin/spine) and then"
echo "switch the poller to spine using the drop down option."
echo "Then configure cacti to monitor your environment."
