#!/bin/bash
set -euo pipefail

# Source common functions
source "$(dirname "$0")/common-functions.sh"

cd "$(dirname "$0")/terraform"
ACR_NAME=$(terraform output -raw acr_login_server 2>/dev/null || echo "")
RESOURCE_GROUP=$(terraform output -raw resource_group_name)
BASE_ENABLED_NAME=$(terraform output -raw automatic_aks_name 2>/dev/null || echo "")
BASE_DISABLED_NAME=$(terraform output -raw automatic_basic_aks_name 2>/dev/null || echo "")
cd - >/dev/null

if [[ -z "$ACR_NAME" ]]; then
  echo "⚠️  ACR output not found; continuing (image registry override may be required)." >&2
fi

echo "📦 Using Azure Container Registry: $ACR_NAME"

# Create values file with ACR configuration
update_acr_values "$ACR_NAME"

echo "🔑 Discovering deployed Automatic clusters in resource group $RESOURCE_GROUP..."
ENABLED_FULL=$(az aks list -g "$RESOURCE_GROUP" --query "[?starts_with(name, '$BASE_ENABLED_NAME')].name | [0]" -o tsv || true)
DISABLED_FULL=$(az aks list -g "$RESOURCE_GROUP" --query "[?starts_with(name, '$BASE_DISABLED_NAME')].name | [0]" -o tsv || true)

if [[ -z "$ENABLED_FULL" && -z "$DISABLED_FULL" ]]; then
  echo "❌ No Automatic clusters found. Run ./1-infra.sh first." >&2
  exit 1
fi

echo "Fetching kubeconfigs (contexts: acnsenabled / acnsdisabled)..."
[[ -n "$ENABLED_FULL" ]] && az aks get-credentials -g "$RESOURCE_GROUP" -n "$ENABLED_FULL" --overwrite-existing --context acnsenabled
[[ -n "$DISABLED_FULL" ]] && az aks get-credentials -g "$RESOURCE_GROUP" -n "$DISABLED_FULL" --overwrite-existing --context acnsdisabled

if command -v kubelogin >/dev/null 2>&1; then
  kubelogin convert-kubeconfig -l azurecli
fi

deploy_chart() {
  local context=$1
  local ns="aks-store"
  echo "🚀 Deploying to context $context"
  kubectl --context "$context" create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
  if [[ -n "$ACR_NAME" ]]; then
    create_acr_pull_secret "$ns" "$ACR_NAME"
  fi
  helm upgrade --install aks-store-demo charts/aks-store-demo \
    -n $ns -f acr-values.yaml --kube-context "$context"
  echo "✅ Deployment complete for $context"
}

[[ -n "$ENABLED_FULL" ]] && deploy_chart acnsenabled
[[ -n "$DISABLED_FULL" ]] && deploy_chart acnsdisabled

echo ""
echo "To access store front: kubectl --context acnsenabled  get svc store-front -n aks-store"
echo "Baseline front:        kubectl --context acnsdisabled get svc store-front -n aks-store"
echo "To view pods:          kubectl --context acnsenabled  get pods -n aks-store -w"
echo "Baseline pods:         kubectl --context acnsdisabled get pods -n aks-store -w"