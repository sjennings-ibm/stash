#!/bin/bash

printf "IBMid:"
read userid
ns=`cf ic namespace get`
suffix=`echo -e $userid | tr -d '@_.-' | tr -d '[:space:]'` 

# copy mysql container from docker hub
cf ic cpi vbudi/refarch-mysql registry.ng.bluemix.net/chackosu/mysql-$suffix

#run 
cf ic run -m 256 --name mysql-$suffix -p 3306:3306 -e MYSQL_ROOT_PASSWORD=Pass4Admin123 -e MYSQL_USER=dbuser -e MYSQL_PASSWORD=Pass4dbUs3R -e MYSQL_DATABASE=inventorydb registry.ng.bluemix.net/chackosu/mysql-$suffix

# copy inventory service from docker hub
cf ic cpi vbudi/refarch-inventory registry.ng.bluemix.net/chackosu/inventoryservice-chackosuusibmcom

# create container group
cf ic group create -p 8080 -m 256 --min 1 --desired 1 --auto --name micro-inventory-group-$suffix -e "spring.datasource.url=jdbc:mysql://172.29.0.100:3306/inventorydb" -n inventoryservice-$suffix -d mybluemix.net  -e "eureka.client.serviceUrl.defaultZone=http://netflix-eureka-chackosuusibmcom.mybluemix.net/eureka/"  -e "spring.datasource.username=dbuser" -e "spring.datasource.password=Pass4dbUs3R" registry.ng.bluemix.net/chackosu/inventoryservice-$suffix