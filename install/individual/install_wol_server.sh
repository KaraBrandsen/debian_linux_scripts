#!/bin/bash

LIBREST_PORT=8079                                       #Port used by Wake on LAN server


echo "-----------------------------Installing Wake on LAN Server-----------------------------"

echo "Installing Nginx"
apt install nginx mariadb-server php-fpm php-mysql php-image-text php-gd php-sqlite3 -y

rm -rf /etc/nginx/sites-available/wol-server

echo "Configuring Nginx"
echo "server {" > /etc/nginx/sites-available/wol-server
echo "    listen $LIBREST_PORT;" >> /etc/nginx/sites-available/wol-server
echo "    server_name wol-server www.wol-server;" >> /etc/nginx/sites-available/wol-server
echo "    root /var/www/html/wol-server;" >> /etc/nginx/sites-available/wol-server
echo "" >> /etc/nginx/sites-available/wol-server
echo "    index index.html index.htm index.php;" >> /etc/nginx/sites-available/wol-server
echo "" >> /etc/nginx/sites-available/wol-server
echo "    location / {" >> /etc/nginx/sites-available/wol-server
echo '        try_files $uri $uri/ =404;' >> /etc/nginx/sites-available/wol-server
echo "    }" >> /etc/nginx/sites-available/wol-server
echo "" >> /etc/nginx/sites-available/wol-server
echo "    location ~ \.php$ {" >> /etc/nginx/sites-available/wol-server
echo "        include snippets/fastcgi-php.conf;" >> /etc/nginx/sites-available/wol-server
echo "        fastcgi_pass unix:/var/run/php/php-fpm.sock;" >> /etc/nginx/sites-available/wol-server
echo "    }" >> /etc/nginx/sites-available/wol-server
echo "" >> /etc/nginx/sites-available/wol-server
echo "    location ~ /\.ht {" >> /etc/nginx/sites-available/wol-server
echo "        deny all;" >> /etc/nginx/sites-available/wol-server
echo "    }" >> /etc/nginx/sites-available/wol-server
echo "" >> /etc/nginx/sites-available/wol-server
echo "}" >> /etc/nginx/sites-available/wol-server

ln -s /etc/nginx/sites-available/wol-server /etc/nginx/sites-enabled/
unlink /etc/nginx/sites-enabled/default

systemctl reload nginx

FPM_VERSION=$(ls /var/run/php | grep "php8.*fpm.sock") 
INI_LOCATION="/etc/php/${FPM_VERSION:3:3}/fpm/php.ini"

echo "Configuring PHP"
sed -i 's/;extension=sockets/extension=sockets/' $INI_LOCATION

echo "Cloning Wake on LAN Server"

rm -rf /var/www/html/wol-server/
mkdir -p /var/www/html/wol-server
chown -R $SUDO_USER:$SUDO_USER /var/www/html/wol-server

git clone https://github.com/AndiSHFR/wake-on-lan.php.git

sleep 3

cp -f ./wake-on-lan.php/wake-on-lan.php /var/www/html/wol-server/index.php
rm -rf ./wake-on-lan.php

echo "Installled Wake on LAN Server"