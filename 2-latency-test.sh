#!/usr/bin/env bash
set -euo pipefail
# Latency measurement script for Node Auto Provisioning (NAP) with and without ACNS
# Measures time from unschedulable pod creation until pod Ready (triggering NAP) for 1 node and burst (10 nodes) scenarios.
# Requirements: az, kubelogin, helm, jq, GNU date, two kubeconfigs contexts: acnsenabled, acnsdisabled

CLUSTER1_CONTEXT="acnsenabled"
CLUSTER2_CONTEXT="acnsdisabled"
NAMESPACE="pets"
CHART_NAME="aks-store-demo/aks-store-demo-chart"
CHART_RELEASE="pets"
REPLICA_BASE=30
SCALE_TARGET=31       # +1 pod scenario triggers 1 node
SCALE_TARGET_BURST=330 # approximate to add ~10 nodes (depends on pod density)
METRICS_FILE="latency-results.csv"

header() { printf "%s\n" "$*" >&2; }
now_ms() { date +%s%3N; }

ensure_repo() {
  if ! helm repo list | grep -q aks-store-demo; then
    helm repo add aks-store-demo https://pauldotyu.github.io/aks-store-demo >/dev/null
  fi
  helm repo update >/dev/null
}

install_or_upgrade() {
  local ctx=$1
  KUBECONFIG_CONTEXT=$ctx
  kubectl --context "$ctx" get ns "$NAMESPACE" >/dev/null 2>&1 || kubectl --context "$ctx" create ns "$NAMESPACE"
  if helm --kube-context "$ctx" -n "$NAMESPACE" list | grep -q "${CHART_RELEASE}"; then
    helm --kube-context "$ctx" -n "$NAMESPACE" upgrade "$CHART_RELEASE" $CHART_NAME --set replicaCount=$REPLICA_BASE >/dev/null
  else
    helm --kube-context "$ctx" -n "$NAMESPACE" install "$CHART_RELEASE" $CHART_NAME --set replicaCount=$REPLICA_BASE --create-namespace >/dev/null
  fi
  # Wait for baseline readiness
  kubectl --context "$ctx" -n "$NAMESPACE" rollout status deploy/${CHART_RELEASE} --timeout=5m >/dev/null
}

wait_ready_count() {
  local ctx=$1 desired=$2
  local ready=0
  local start=$(now_ms)
  while true; do
    ready=$(kubectl --context "$ctx" -n "$NAMESPACE" get pods -l app=${CHART_RELEASE} -o json | jq '[.items[] | select(.status.phase=="Running") | select([.status.containerStatuses[]? | select(.ready==true)] | length>0)] | length')
    if [[ $ready -ge $desired ]]; then
      break
    fi
    sleep 2
  done
  local end=$(now_ms)
  echo $((end-start))
}

scale_and_measure() {
  local ctx=$1 target=$2 label=$3
  local start=$(now_ms)
  kubectl --context "$ctx" -n "$NAMESPACE" scale deploy/${CHART_RELEASE} --replicas=$target >/dev/null
  # Wait for all replicas observed
  kubectl --context "$ctx" -n "$NAMESPACE" wait --for=jsonpath='{.status.replicas}'=$target deploy/${CHART_RELEASE} --timeout=10m >/dev/null 2>&1 || true
  local latency=$(wait_ready_count "$ctx" $target)
  local end=$(now_ms)
  local total=$((end-start))
  printf "%s,%s,%s,%s,%s\n" "$(date -Iseconds)" "$ctx" "$label" "$latency" "$total" >> "$METRICS_FILE"
  header "Context=$ctx scenario=$label pod_ready_latency_ms=$latency total_elapsed_ms=$total"
}

main() {
  echo "timestamp,cluster,scenario,pod_ready_latency_ms,total_elapsed_ms" > "$METRICS_FILE"
  ensure_repo
  for ctx in "$CLUSTER1_CONTEXT" "$CLUSTER2_CONTEXT"; do
    install_or_upgrade "$ctx"
    scale_and_measure "$ctx" "$SCALE_TARGET" "add_1_node"
    scale_and_measure "$ctx" "$SCALE_TARGET_BURST" "add_approx_10_nodes"
  done
  header "Results written to $METRICS_FILE"
}

main "$@"
