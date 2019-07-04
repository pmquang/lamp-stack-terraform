#!/bin/bash

amazon-linux-extras install docker -y

service docker restart

docker run --name wordpress-demo -it -d --network host -e WORDPRESS_DB_HOST=${WORDPRESS_DB_HOST} -e WORDPRESS_DB_USER=${WORDPRESS_DB_USER} -e WORDPRESS_DB_PASSWORD=${WORDPRESS_DB_PASSWORD} -e WORDPRESS_DB_NAME=${WORDPRESS_DB_NAME} wordpress:5.2.2-php7.1-apache