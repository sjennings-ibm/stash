#!/bin/bash

printf "IBMid:"
read userid
ns=`cf ic namespace get`
suffix=`echo -e $userid | tr -d '@_.-' | tr -d '[:space:]'` 

cf ic group rm micro-inventory-group-chackosuusibmcom
cf ic rm -f mysql-$suffix

cf ic rmi registry.ng.bluemix.net/chackosu/inventoryservice-$suffix
cf ic rmi registry.ng.bluemix.net/chackosu/mysql-$suffix