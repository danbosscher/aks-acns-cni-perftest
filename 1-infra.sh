#!/bin/bash
set -euo pipefail

SUBSCRIPTION_ID="${AZ_SUBSCRIPTION_ID:-}" # optional env var to force subscription (Azure Network Agent Test sub)

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

if [[ -n "$SUBSCRIPTION_ID" ]]; then
    echo "Setting Azure subscription to $SUBSCRIPTION_ID";
    az account set --subscription "$SUBSCRIPTION_ID"
fi

echo "Using Azure Subscription: $(az account show --query name -o tsv) ($(az account show --query id -o tsv))"

APPLY_FLAGS=${TERRAFORM_APPLY_FLAGS:--auto-approve}
echo "Running terraform apply $APPLY_FLAGS"
if ! terraform apply $APPLY_FLAGS; then
    echo "Error detected during deployment. Exiting..."
    exit 1
fi

echo "Deployment completed successfully!"

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
BASE_ENABLED_NAME=$(terraform output -raw automatic_aks_name 2>/dev/null || true)
BASE_DISABLED_NAME=$(terraform output -raw automatic_basic_aks_name 2>/dev/null || true)

# Retrieve actual deployed cluster resource names (with random suffix) from state via az (list filtered by startswith)
echo "Discovering actual cluster names (with random suffix)..."
ENABLED_FULL=$(az aks list -g "$RESOURCE_GROUP" --query "[?starts_with(name, '$BASE_ENABLED_NAME')].name | [0]" -o tsv || true)
DISABLED_FULL=$(az aks list -g "$RESOURCE_GROUP" --query "[?starts_with(name, '$BASE_DISABLED_NAME')].name | [0]" -o tsv || true)

echo "Fetching kubeconfigs..."
if [[ -n "$ENABLED_FULL" ]]; then
    az aks get-credentials -g "$RESOURCE_GROUP" -n "$ENABLED_FULL" --overwrite-existing --context acnsenabled
fi
if [[ -n "$DISABLED_FULL" ]]; then
    az aks get-credentials -g "$RESOURCE_GROUP" -n "$DISABLED_FULL" --overwrite-existing --context acnsdisabled
fi

echo "Converting kubeconfigs for Azure CLI auth with kubelogin..."
if command -v kubelogin >/dev/null 2>&1; then
    kubelogin convert-kubeconfig -l azurecli
else
    echo "kubelogin not found in PATH. Install via: az aks install-cli (if available) or https://github.com/Azure/kubelogin" >&2
fi

echo "Contexts available:"
kubectl config get-contexts |
    awk 'NR==1 || /acnsenabled/ || /acnsdisabled/'

echo "Use contexts: acnsenabled (with ACNS) and acnsdisabled (baseline)."
echo "Next: ./2-latency-test.sh to run latency measurements."