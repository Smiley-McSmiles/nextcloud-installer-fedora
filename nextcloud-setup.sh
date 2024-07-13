#!/bin/bash

dependencies="fastlz liblzf libmemcached-awesome httpd php php-fpm php-cli php-mysqlnd php-gd php-xml php-mbstring php-json php-curl php-zip php-bcmath php-gmp php-intl php-ldap php-pecl-apcu php-pecl-igbinary php-pecl-imagick php-pecl-memcached php-pecl-msgpack php-pecl-redis5 php-smbclient php-process php-imagick php-redis php-opcache redis mariadb maraidb-server unzip curl wget bash-completion policycoreutils-python-utils mlocate bzip2 httpd"

zipFileLink="https://download.nextcloud.com/server/releases/latest.zip"

apacheNcConf="<VirtualHost *:8090>
  DocumentRoot /var/www/html/nextcloud/

  <Directory /var/www/html/nextcloud/>
    Require all granted
    AllowOverride All
    Options FollowSymLinks MultiViews

    <IfModule mod_dav.c>
      Dav off
    </IfModule>

  </Directory>
</VirtualHost>"

echo "Please enter the desired MariaDB user for Nextcloud"
read -p "Example: nextclouduser : " mariadbUser
echo
read -p "Please enter the desired MariaDB password : " mariadbPass
echo
read -p "Please enter the desired admin account name for Nextcloud : " ncAdmin
echo
read -p "Please enter the desired admin account password for Nextcloud : " ncPass
echo

# Install Dependencies
dnf upgrade -y
dnf install "$dependencies" -y

# Install Nextcloud
wget $zipFileLink
unzip latest.zip -d /var/www/html/
mkdir -p /var/www/html/nextcloud/data
chown -Rf apache:apache /var/www/html/nextcloud
chmod -Rf 770 /var/www/html/nextcloud

# Firewall Rules
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-port=8090/tcp
firewall-cmd --permanent --add-port=3306/tcp
firewall-cmd --reload

## Create /etc/httpd/conf.d/nextcloud.conf
ehco "$apacheNcConf" > /etc/httpd/conf.d/nextcloud.conf

## Edit Configs
# /etc/php.ini
sed -ri "s|memory_limit =.*|memory_limit = 512M|g" /etc/php.ini

# /etc/php-fpm.d/www.conf
sed -ri "s|user =.*|user = apache|g" /etc/php-fpm.d/www.conf
sed -ri "s|group =.*|group = apache|g" /etc/php-fpm.d/www.conf
sed -ri "s|listen =.*|listem = /run/php-fpm/www.sock|g" /etc/php-fpm.d/www.conf
sed -ri "s|listen.owner =.*|listen.owner = apache|g" /etc/php-fpm.d/www.conf
sed -ri "s|listen.group =.*|listen.group = apache|g" /etc/php-fpm.d/www.conf

# /etc/httpd/conf/httpd.conf
sed -ri "s|Listen.*|Listen 8090|g" /etc/httpd/conf/httpd.conf
sed -ri "s|ServerName.*|ServerName localhost|g" /etc/httpd/conf/httpd.conf

####### SELinux #######
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/config(/.*)?'
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/apps(/.*)?'
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.htaccess'
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/.user.ini'
semanage fcontext -a -t httpd_sys_rw_content_t '/var/www/html/nextcloud/3rdparty/aws/aws-sdk-php/src/data/logs(/.*)?'

restorecon -R '/var/www/html/nextcloud/'

setsebool -P httpd_can_network_connect on

chcon -Rt httpd_sys_rw_content_t /var/www/html/nextcloud/data
semanage fcontext -a -t httpd_sys_rw_content_t  "/var/www/html/nextcloud/data(/.*)?"
semanage fcontext -m -t httpd_sys_rw_content_t  "/var/www/html/nextcloud/data(/.*)?"
####### SELinux END #######

## Enable Services
systemctl enable --now httpd mariadb redis

## MariaDB Setup
mysql_secure_installation

mysql -e "CREATE USER '${mariadbUser}'@'localhost' IDENTIFIED BY '${mariadbPass}';"
mysql -e "CREATE DATABASE IF NOT EXISTS nextcloud CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "GRANT ALL PRIVILEGES on nextcloud.* to '${mariadbUser}'@'localhost';"

# Install Nextcloud via occ
chmod -Rf 777 /var/www/html/nextcloud
cd /var/www/html/nextcloud
sudo -u apache php occ maintenance:install --database='mysql' --database-name='nextcloud' --database-user='${mariadbUser}' --database-pass='${mariadbPass}' --admin-user='${ncAdmin}' --admin-pass='${ncPass}'
cd ~; chmod -Rf 770 /var/www/html/nextcloud

# Edit /var/www/html/nextcloud/config/config.php
echo "We must edit the variable 'trusted_domains' in the Nextcloud config.php."
echo "If we don't then Nextcloud will not allow us access."
echo "Please enter your desired editor"
read -p "example 'vi', 'nano', 'micro' : " editor
echo "Great! now here is an example for the 'trusted_domains' variable in the config.php :"
echo
echo "  'trusted_domains' => 
  array (
    0 => 'localhost',
    1 => '127.0.0.1',
    2 => 'cloud.YourDomain.com',
    3 => '192.168.1.11:8090',
  ),"
echo
read -p "Press ENTER to start editing. It is recommended that you copy the above code before pressing ENTER" null

$editor /var/www/html/nextcloud/config/config.php

## Restart Services
systemctl restart httpd mariadb

echo
echo
echo "All done. Please navigate to http://yourdomain:8090"
echo "It is recommended to use caddy to make a reverse proxy to host Nextcloud with https (secure)"
