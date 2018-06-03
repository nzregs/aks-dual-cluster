# Azure Kubernetes Service (AKS) Dual Cluster Deployment
This azure cli script and ARM template deploys two AKS clusters, each in a different region.  Each cluster has a private VNET attached, and VNET peering is established.
Containers running in Site1 can talk to containers running in Site2 across the VNET 

## Prerequisites

1. As the azure cli does not yet allow for OMS Workspace creation, you will need to create that manually (or via powershell) and update the script with the corresponding values before deployment

2. install docker client on local host:

```bash
sudo apt-get install docker
```

3. install the json query tool on local host:

```bash
sudo apt-get install jq
```

4. install the azure cli on local host:

```bash
sudo apt-get install azure-cli
```

5. install kubectl on local host:

```bash
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && chmod +x kubectl && sudo mv kubectl /usr/local/bin/
```


## Deployment

1. Amend the script to use a unique name for your deployment:

```bash
declare uniqueName="sunday"
```

2. Amend the script and add a kubernetes admin password:

```bash
declare secret="YOUR_PASSWORD_HERE"
```

3. Amend the script and provide your OMS workspace parameters:

```bash
declare workspaceName="YOUR_WORKSPACE_HERE"
declare omsWorkspaceId="YOUR_WORKSPACE_ID_HERE"
declare workspaceRegion="YOUR_WORKSPACE_REGION_HERE"
```

4. Run the script:

```bash
./aks-dual-clusher.sh
```
