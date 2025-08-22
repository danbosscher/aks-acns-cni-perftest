#!/bin/bash
set -e

cd "$(dirname "$0")/terraform"

# Initialize Terraform
echo "Initializing Terraform..."
terraform init
# Deploy infrastructure with automatic destroy on failure
clear
echo "Verifying Azure CLI authentication..."
if ! az account show >/dev/null 2>&1; then
    echo "No active Azure CLI session detected. Launching device login (includes Microsoft Graph scope)..."
    az login --use-device-code --scope https://graph.microsoft.com/.default
fi

# Ensure Graph scope token (some operations like AAD group resolution may require it)
if ! az account get-access-token --resource-type ms-graph >/dev/null 2>&1; then
    echo "Acquiring Microsoft Graph access token..."
    az login --scope https://graph.microsoft.com/.default --use-device-code
fi

echo "This will deploy to the following Azure Subscription:"
az account show --query name -o tsv
if ! terraform apply; then
    echo "Error detected during deployment. Exiting..."
    exit 1
fi

echo "Deployment completed successfully!"

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
AUTOMATIC_AKS_NAME=$(terraform output -raw automatic_aks_name 2>/dev/null || echo "")

echo "Done! Connect to your clusters using:"
echo "Automatic Cluster:"
echo "kubectl config use-context $AUTOMATIC_AKS_NAME"