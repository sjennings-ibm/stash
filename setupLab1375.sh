#!/bin/bash
# get login information
#printf "Region: 1. US-South 2. Europe \n AP does not support Container\n"
#read choice
printf "IBMid:"
read userid
printf "Password:" 
stty -echo
read password
stty echo
starttime=`date`

domreg=""
#if [ $choice -eq 1 ]; then 
  region="ng"
  apicreg="us"
#else 
#  if [ $choice -eq 2 ]; then 
#    region="eu-gb"
#    apicreg="eu"
#    domreg="eu-gb."
#  else 
#    region="ng"
#    apicreg="us"
#  fi
#fi
dom="mybluemix.net"

IFS="@"
set -- $userid
if [ "${#@}" -ne 2 ];then
    echo "#####################################################"
    echo "Your IBMid is not in the format of an email"
    echo "This lab cannot be performed with this email address"
    echo "Ask a lab proctor for more information"
    echo "#####################################################"
    exit
fi
unset IFS
echo
echo "#######################################################################"
echo "# 1. Logging in to Bluemix "
# Run cf login
# cf login -a api.$region.bluemix.net -u "$userid" -p "$password" -o "$userid" -s dev | tee login.out
cf login -a api.$region.bluemix.net -u "$userid" -p "$password" | tee login.out
logerr=`grep FAILED login.out | wc -l`
rm login.out
if [ $logerr -eq 1 ]; then
  echo "#    Login failed... Exiting"
  exit
fi
# get space and org info
orgtxt=`cf target | grep "Org:" | awk '{print $2}'`
spctxt=`cf target | grep "Space:" | awk '{print $2}'`
echo "#    Logged in to Bluemix ...  "
echo "#######################################################################"

# Run cf ic init
echo "#######################################################################"
echo "# 2. Initialize IBM Container Plugin "
initResult=`cf ic init`
err=`echo initResult | grep IC5076E | wc -l`
if [ $err -eq 1 ]; then
  echo "IBM Container namespace"
  echo "This namespace cannot be changed later"
  echo "Enter your namespace"
  read namespace
  cf ic namespace set $namespace > /dev/null
  cf ic init > /dev/null
fi
ns=`cf ic namespace get`
suffix=`echo -e $userid | tr -d '@_.-' | tr -d '[:space:]'` 
echo "#    IBM Container initialized ... "
echo "#######################################################################"
echo "### Your suffix is: $suffix                       ###"
echo "#######################################################################"

ans=""
until [ "$ans" == "OSS" ]; do
  printf "To continue type \"OSS\" and press Enter..."
  read ans
done

echo 
echo "#######################################################################"
echo "# 3. Create eureka and zuul"
cf ic cpi vbudi/refarch-eureka  registry.$region.bluemix.net/$ns/eureka-$suffix
cf ic cpi vbudi/refarch-zuul  registry.$region.bluemix.net/$ns/zuul-$suffix
cf ic group create --name eureka_cluster --publish 8761 --memory 256 --auto --min 1 --max 3 --desired 1 -n netflix-eureka-$suffix -d $domreg$dom -e eureka.client.fetchRegistry=true -e eureka.client.registerWithEureka=true -e eureka.client.serviceUrl.defaultZone=http://netflix-eureka-$suffix.$domreg$dom/eureka/ -e eureka.instance.hostname=eureka-$suffix.$domreg$dom -e eureka.instance.nonSecurePort=80 -e eureka.port=80 registry.$region.bluemix.net/$ns/eureka-$suffix
cf ic group create --name zuul_cluster --publish 8080 --memory 256 --auto --min 1 --max 3 --desired 1 -n netflix-zuul-$suffix -d $domreg$dom -e eureka.client.serviceUrl.defaultZone="http://netflix-eureka-$suffix.$domreg$dom/eureka" -e eureka.instance.hostname=netflix-zuul-$suffix.$domreg$dom -e eureka.instance.nonSecurePort=80 -e eureka.instance.preferIpAddress=false -e spring.cloud.client.hostname=zuul-$suffix.$domreg$dom registry.$region.bluemix.net/$ns/zuul-$suffix

echo "Waiting for OSS to start ..."    
ossdone=`cf ic group list | grep "_cluster" | grep "ATE_COMPLETE" | wc -l`
until [  $ossdone -eq 2 ]; do
    sleep 10         
    ossdone=`cf ic group list | grep "_cluster" | grep "ATE_COMPLETE" | wc -l`
done

ans=""
until [ "$ans" == "microservices" ]; do
  printf "To continue type \"microservices\" and press Enter..."
  read ans
done

# deploy social review - eureka - zuul - bff - apic 
echo "#######################################################################"
echo "# 4a. Setup mysql container  "
cf ic cpi vbudi/refarch-mysql registry.$region.bluemix.net/$ns/mysql-$suffix
sleep 20
cf ic run -m 256 --name mysql-$suffix -p 3306:3306 -e MYSQL_ROOT_PASSWORD=Pass4Admin123 -e MYSQL_USER=dbuser -e MYSQL_PASSWORD=Pass4dbUs3R -e MYSQL_DATABASE=inventorydb registry.$region.bluemix.net/$ns/mysql-$suffix
echo "Waiting for mysql container to start ..."  
sleep 20
sqlok=`cf ic ps | grep mysql | grep unning | wc -l`
until [  $sqlok -ne 0 ]; do
    sleep 10         
    sqlok=`cf ic ps | grep mysql | grep unning | wc -l`
    sqlerr=`cf ic ps | grep mysql | wc -l`
    if [ $sqlerr -eq 0 ]; then 
        echo "Cannot run the MySQL container. Exiting ..."
        exit
    fi
done

sleep 20

echo "cf ic exec -it mysql-$suffix sh load-data.sh"
cf ic exec -it mysql-$suffix sh load-data.sh

sleep 20

mysqlIP=`cf ic inspect mysql-$suffix | grep -i ipaddr | head -n 1 | grep -Po '(?<="IPAddress": ")[^"]*' `

echo "# 4b. Create Cloudant database "
cf create-service cloudantNoSQLDB Lite socialreviewdb-$suffix
sleep 20
cf create-service-key socialreviewdb-$suffix cred
sleep 20
cloudantCred=`cf service-key socialreviewdb-$suffix cred`
cldurl=`echo -e $cloudantCred | grep url |  grep -Po '(?<=\"url\": \")[^"]*'`
cldhost=`echo -e $cloudantCred | grep host |  grep -Po '(?<=\"host\": \")[^"]*'`
cldusername=`echo -e $cloudantCred | grep username |  grep -Po '(?<=\"username\": \")[^"]*'`
cldpassword=`echo -e $cloudantCred | grep password |  grep -Po '(?<=\"password\": \")[^"]*'`

if [ $cldurl -eq "" ]; then
    echo "Cannot instantiate cloudant. Exiting ..."
    exit
else
    echo "Cloudant url: $cldurl"
fi
# get cred
echo "curl -X PUT https://$cldusername:$cldpassword@$cldhost/socialreviewdb"
curl -X PUT https://$cldusername:$cldpassword@$cldhost/socialreviewdb
# insert a record 
curl -X POST -H "Content-Type: application/json" -d '{ "comment": "I love this product!", "rating": 5, "reviewer_name": "Pam Geiger", "review_date": "01/19/2016", "reviewer_email": "pgeiger@us.ibm.com", "itemId": 13401 }' https://$cldusername:$cldpassword@$cldhost/socialreviewdb
  
echo "# 3c. Create inventory microservices"
cf ic cpi vbudi/refarch-inventory registry.$region.bluemix.net/$ns/inventoryservice-$suffix
sleep 20
cf ic group create -p 8080 -m 256 --min 1 --desired 1 --auto --name micro-inventory-group-$suffix -e "spring.datasource.url=jdbc:mysql://$mysqlIP:3306/inventorydb" -n inventoryservice-$suffix -d $domreg$dom  -e "eureka.client.serviceUrl.defaultZone=http://netflix-eureka-$suffix.$domreg$dom/eureka/"  -e "spring.datasource.username=dbuser" -e "spring.datasource.password=Pass4dbUs3R" registry.$region.bluemix.net/$ns/inventoryservice-$suffix

echo "# 3d. Create socialreview microservices"
cf ic cpi vbudi/refarch-socialreview registry.$region.bluemix.net/$ns/socialreviewservice-$suffix
sleep 20
cf ic group create -p 8080 -m 256 --min 1 --desired 1 --auto --name micro-socialreview-group-$suffix -e "eureka.client.serviceUrl.defaultZone=http://netflix-eureka-$suffix.$domreg$dom/eureka/" -e "cloudant.username=$cldusername" -e "cloudant.password=$cldpassword" -e "cloudant.host=https://$cldhost" -n socialreviewservice-$suffix -d $domreg$dom  registry.$region.bluemix.net/$ns/socialreviewservice-$suffix 

echo "Waiting for microservices to start ..."  
msdone=`cf ic group list | grep "micro-" | grep "ATE_COMPLETE" | wc -l`
until [  $msdone -eq 2 ]; do
    sleep 10         
    msdone=`cf ic group list | grep "micro-" | grep "ATE_COMPLETE" | wc -l`
done  

ans=""
ans1="ANS1"
until [ "$ans" == "$ans1" ]; do
  printf "Client ID is in the form of UUID            : 12345678-1234-1234-1234-123456789012"
  printf "Enter Client ID for the BlueCompute-$suffix :"
  read ans
  printf "Confirm the client ID                       :"
  read ans1
  len1=${#ans}
  len2=${#ans1}
  if [[ ${ans//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
    echo "valid uuid retrieved"
  else
    ans=""
  fi
done
clientID=$ans

echo "# 3e Clone repositories"
cd /home/bmxuser
git clone -b r2base https://github.com/ibm-cloud-architecture/refarch-cloudnative-bff-inventory
git clone -b r2base https://github.com/ibm-cloud-architecture/refarch-cloudnative-bff-socialreview
git clone -b r2base https://github.com/ibm-cloud-architecture/refarch-cloudnative-api
git clone -b r2base https://github.com/ibm-cloud-architecture/refarch-cloudnative-bluecompute-web

#cd /home/bmxuser/refarch-cloudnative-api 
#git checkout 555d5cc380af08876b0aa65c22d357ee4806d645
#cd /home/bmxuser/refarch-cloudnative-bluecompute-web 
#git checkout 1c0d0bc8aee0bfdce8e0f3381acb39274c1e4ef3

apic login -s $apicreg.apiconnect.ibmcloud.com -u $userid -p $password
sleep 20
catexist=`apic catalogs -s $apicreg.apiconnect.ibmcloud.com -o $suffix-$spctxt | grep bluecompute-$suffix | wc -l`
until [ $catexist -eq 1 ]; do
   echo "Cannot get the unique catalog bluecompute-$suffix. Please create the catalog ..."
   read ans
   catexist=`apic catalogs -s $apicreg.apiconnect.ibmcloud.com -o $suffix-$spctxt | grep bluecompute-$suffix | wc -l`
done

echo "#######################################################################"
echo "# 4a Install BFFs"
cd /home/bmxuser/refarch-cloudnative-bff-inventory/inventory
/bin/bash set-zuul-proxy-url.sh -z netflix-zuul-$suffix.$domreg$dom
sleep 20
cf create-service Auto-Scaling free cloudnative-autoscale-$suffix
sleep 20
sed -i -e 's/autoscale/autoscale-'$suffix'/g' manifest.yml
# push
cf push inventory-bff-app-$suffix -d $domreg$dom -n inventory-bff-app-$suffix 

echo "#######################################################################"
echo "# 4b Install Social review BFFs"

cd /home/bmxuser/refarch-cloudnative-bff-socialreview/socialreview
/bin/bash set-zuul-proxy-url.sh -z netflix-zuul-$suffix.$domreg$dom

apic login -s $apicreg.apiconnect.ibmcloud.com -u $userid -p $password
sleep 20
apic config:set app=apic-app://$apicreg.apiconnect.ibmcloud.com/orgs/$suffix-$spctxt/apps/socialreview-bff-app-$suffix
sleep 20
apic apps:publish
# sleep 20
# cf bs socialreview-bff-app-$suffix cloudnative-autoscale-$suffix
# sleep 20
# cf restage socialreview-bff-app-$suffix
sleep 20

sochost=`cf apps | grep socialreview-bff | awk '{ print $6;}'`

echo "# Social review BFF host: $sochost #"
echo "#######################################################################"
ans=""
until [ "$ans" == "BlueCompute" ]; do
  printf "To continue type \"BlueCompute\" and press Enter..."
  read ans
done


echo "#######################################################################"
echo "# 5 Update API definitions and publish APIs"

sed -i -e 's/inventory-bff-app.mybluemix.net/inventory-bff-app-'$suffix.$domreg$dom'/g' /home/bmxuser/refarch-cloudnative-api/inventory/inventory.yaml
sed -i -e 's/api.us.apiconnect.ibmcloud.com\/centusibmcom-cloudnative-dev\/bluecompute/api.'$apicreg'.apiconnect.ibmcloud.com\/'$suffix'-'$spctxt'\/bluecompute-'$suffix'/g' /home/bmxuser/refarch-cloudnative-bff-socialreview/socialreview/definitions/socialreview.yaml
sed -i -e 's/apiconnect-243ab119-1c05-402c-a74c-6125122c9273.centusibmcom-cloudnative-dev.apic.mybluemix.net/'$sochost'/g' /home/bmxuser/refarch-cloudnative-bff-socialreview/socialreview/definitions/socialreview.yaml

cd /home/bmxuser/refarch-cloudnative-api/inventory/
apic config:set catalog=apic-catalog://$apicreg.apiconnect.ibmcloud.com/orgs/$suffix-$spctxt/catalogs/bluecompute-$suffix
sleep 10
apic publish inventory-product_0.0.1.yaml
sleep 20

cd /home/bmxuser/refarch-cloudnative-bff-socialreview/socialreview/definitions/
apic config:set catalog=apic-catalog://$apicreg`.apiconnect.ibmcloud.com/orgs/$suffix-$spctxt/catalogs/bluecompute-$suffix
sleep 10
apic publish socialreview-product.yaml
sleep 20

echo "#######################################################################"
echo "# 6 prepare Web application"

cd /home/bmxuser/refarch-cloudnative-bluecompute-web/StoreWebApp
sed -i -e 's/mybluemix.net/'$domreg$dom'/g' manifest.yml
sed -i -e 's/bluecompute-web-app/bluecompute-web-app-'$suffix'/g' manifest.yml

sed -i -e 's/api.us.apiconnect.ibmcloud.com/api.'$apicreg'.apiconnect.ibmcloud.com/g' config/default.json
sed -i -e 's/centusibmcom-cloudnative-dev/'$suffix'-'$spctxt'/g' config/default.json
sed -i -e 's/bluecompute/bluecompute-'$suffix'/g' config/default.json

sed -i -e 's/3f1b4cc8-78dc-450e-9461-edf377105c7a/'$clientID'/g' config/default.json

cf push 
echo "#######################################################################"
echo "#######################################################################"
echo "###         Blue Compute application successfully deployed          ###"
echo "#######################################################################"
echo "#######################################################################"
endtime=`date`
echo $starttime $endtime

