#!/bin/bash

apicorglist=`apic orgs -s us.apiconnect.ibmcloud.com | grep chackosuusibmcom-dev`

for apicorg in $apicorglist; do
   catexist=`apic catalogs -s us.apiconnect.ibmcloud.com -o $apicorg | grep redcompute-chackosuusibmcom | wc -l`
   echo "$apicorg: $catexist"
   if [ $catexist -eq 1 ]; then
	break
   fi
done

if [ $catexist -eq 1 ]; then
   echo "Found redcompute-chackosuusibmcom"
fi

until [ $catexist -eq 1 ]; do
   echo "Cannot get the unique catalog redcompute-chackosuusibmcom. Please create the catalog, then hit ENTER ..."
   read ans
   for apicorg in $apicorglist; do
      catexist=`apic catalogs -s us.apiconnect.ibmcloud.com -o $apicorg | grep redcompute-chackosuusibmcom | wc -l`
      echo "$apicorg: $catexist"
      if [ $catexist -eq 1 ]; then
	break
      fi
   done
done

# test: multiple orgs, catalog found
#... single org, catalog found
#... multiple orgs, catalog NOT found
#... single org, catalog NOT found
