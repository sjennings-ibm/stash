#!/bin/bash

printf "IBMid:"
read userid
ns=`cf ic namespace get`
suffix=`echo -e $userid | tr -d '@_.-' | tr -d '[:space:]'` 


cf delete-service-key socialreviewdb-$suffix cred -f
cf delete-service socialreviewdb-$suffix       -f
cf ic rmi registry.ng.bluemix.net/chackosu/socialreviewservice-$suffix   