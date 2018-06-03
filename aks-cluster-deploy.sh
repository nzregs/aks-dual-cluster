#!/bin/bash -v

# prerequisite packages to run this script on windows wsl ubuntu
# will not run if 1 == 0 ;)
if [ 1 == 0 ];
then
    #get package updates
	sudo apt-get update

    #install docker client and point to docker on windows
    sudo apt-get install docker  
    export DOCKER_HOST=localhost:2375

    #install json query tool
    sudo apt-get install jq

    #install azure cli
    sudo apt-get install azure-cli

    #install kubectl
    curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/   
fi

# should log in to azure first, but we'll check and initiate
az account show 1> /dev/null

if [ $? != 0 ];
then
	az login
fi

# unique deployment name
declare uniqueName="sunday"

# kubernetes admin
declare admin="aksadmin"
declare secret="YOUR_PASSWORD_HERE"

#oms workspace - no azure cli support yet!
# THIS IS MANUALLY CODED.  CAN BE FETCHED USING POWERSHELL.
declare workspaceName="YOUR_WORKSPACE_HERE" 
declare omsWorkspaceId="YOUR_WORKSPACE_ID_HERE"
declare workspaceRegion="YOUR_WORKSPACE_REGION_HERE"

declare deploymentName="aks-${uniqueName}"
declare acrName="${deploymentName}acr"
declare site1cidr="192.168.200.0/24"
declare site1location="eastus"
declare site2cidr="192.168.201.0/24"
declare site2location="centralus"
declare site1serviceCidr="10.0.0.0/16"
declare site1dnsServiceIP="10.0.0.10"
declare site1dockerBridgeCidr="172.17.0.1/16"
declare site2serviceCidr="10.0.0.0/16"
declare site2dnsServiceIP="10.0.0.10"
declare site2dockerBridgeCidr="172.17.0.1/16"
declare kubernetesVersion="1.9.6"

#create resource groups
az group create -n $deploymentName-shared-rg -l $site1location
az group create -n $deploymentName-site1-rg -l $site1location
az group create -n $deploymentName-site2-rg -l $site2location

#create a keyvault
az keyvault create -n $deploymentName-secrets -g $deploymentName-shared-rg --enabled-for-template-deployment

#create a secret and return to file
az keyvault secret set --vault-name $deploymentName-secrets --name $admin --value $secret

#create a service principal and configure for access to azure resources
az ad sp create-for-rbac > $deploymentName-sp.json
declare servicePrincipalClientId=$(cat $deploymentName-sp.json | jq -r .appId)
declare servicePrincipalClientSecret=$(cat $deploymentName-sp.json | jq -r .password)

echo Service Principal Client = $servicePrincipalClientId
echo Service Principal Secret = $servicePrincipalClientSecret

#create an azure container registry for private images, and log in
az acr create --resource-group $deploymentName-shared-rg --name $acrName --sku Basic --admin-enabled true
az acr login --name $acrName

#grab nginx from docker hub and send to container registry
docker pull nginx:stable-alpine
docker tag nginx:stable-alpine $acrName.azurecr.io/samples/nginx
docker push $acrName.azurecr.io/samples/nginx

#create site1 and site2 VNETs
az network vnet create --name $deploymentName-site1-vnet --location eastus --resource-group $deploymentName-site1-rg \
                         --address-prefix $site1cidr --subnet-name $deploymentName-site1-subnet --subnet-prefix $site1cidr

az network vnet show --name $deploymentName-site1-vnet --resource-group $deploymentName-site1-rg > $deploymentName-site1vnet.json 

az network vnet create --name $deploymentName-site2-vnet --location centralus --resource-group $deploymentName-site2-rg \
                         --address-prefix $site2cidr --subnet-name $deploymentName-site2-subnet --subnet-prefix $site2cidr

az network vnet show --name $deploymentName-site2-vnet --resource-group $deploymentName-site2-rg > $deploymentName-site2vnet.json

declare site1VNetId=$(cat $deploymentName-site1vnet.json | jq -r .id)
declare site1VNetSubnetId=$(cat $deploymentName-site1vnet.json | jq -r .subnets[0].id)
declare site2VNetId=$(cat $deploymentName-site2vnet.json | jq -r .id)
declare site2VNetSubnetId=$(cat $deploymentName-site2vnet.json | jq -r .subnets[0].id)

#create peering between site1 and site2 VNETs
az network vnet peering create --resource-group $deploymentName-site1-rg \
                                --name site1vnetTOsite2vnet \
                                --vnet-name $deploymentName-site1-vnet \
                                --remote-vnet-id $site2VNetId \
                                --allow-vnet-access

# create peering between site2 and site1 VNETs
az network vnet peering create --resource-group $deploymentName-site2-rg \
                                --name site2vnetTOsite1vnet \
                                --vnet-name $deploymentName-site2-vnet \
                                --remote-vnet-id $site1VNetId \
                                --allow-vnet-access

#create the aks cluster in site1
#no current option to use azure cli for advanced networking, must use portal or arm
templatepath="kube-managed.json"
#Start deployment
echo "Starting site1 deployment..."
(
	set -x
	az group deployment create --name $deploymentName-site1-deployment \
                                --resource-group $deploymentName-site1-rg \
                                --template-file kube-managed.json \
                                --parameters resourceName=$deploymentName-site1 \
                                                servicePrincipalClientId=$servicePrincipalClientId \
                                                servicePrincipalClientSecret=$servicePrincipalClientSecret \
                                                resourceName=$deploymentName-site1 \
                                                dnsPrefix=$deploymentName-site1 \
                                                location=$site1location \
                                                vnetSubnetID=$site1VNetSubnetId \
                                                networkPlugin=azure \
                                                serviceCidr=$site1serviceCidr \
                                                dnsServiceIP=$site1dnsServiceIP \
                                                dockerBridgeCidr=$site1dockerBridgeCidr  \
                                                workspaceName=$workspaceName \
                                                omsWorkspaceId=$omsWorkspaceId \
                                                workspaceRegion=$workspaceRegion \
                                                kubernetesVersion=$kubernetesVersion
)

if [ $?  == 0 ];
 then
	echo "site1 has been successfully deployed"
fi

echo "Starting site2 deployment..."
(
	set -x
	az group deployment create --name $deploymentName-site2-deployment \
                                --resource-group $deploymentName-site2-rg \
                                --template-file kube-managed.json  \
                                --parameters resourceName=$deploymentName-site2 \
                                                servicePrincipalClientId=$servicePrincipalClientId \
                                                servicePrincipalClientSecret=$servicePrincipalClientSecret \
                                                resourceName=$deploymentName-site2 \
                                                dnsPrefix=$deploymentName-site2 \
                                                location=$site2location \
                                                vnetSubnetID=$site2VNetSubnetId \
                                                networkPlugin=azure \
                                                serviceCidr=$site2serviceCidr \
                                                dnsServiceIP=$site2dnsServiceIP \
                                                dockerBridgeCidr=$site2dockerBridgeCidr  \
                                                workspaceName=$workspaceName \
                                                omsWorkspaceId=$omsWorkspaceId \
                                                workspaceRegion=$workspaceRegion  \
                                                kubernetesVersion=$kubernetesVersion  

)

if [ $?  == 0 ];
 then
	echo "site2 has been successfully deployed"
fi

