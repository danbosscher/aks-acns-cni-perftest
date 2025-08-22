# AKS Advanced Networking & Node Auto Provisioning Performance Test

This repository provisions two **AKS Automatic** SKU clusters (Kubernetes version via variable) to measure Node Auto Provisioning (NAP / Karpenter-managed) scale latency **with and without Advanced Container Networking Services (ACNS)** enabled.

| Cluster | Dataplane | ACNS | Purpose |
|---------|-----------|------|---------|
| `acnsenabled-<rand>`  | Cilium | Enabled  | Test latency with advancedNetworking (observability + security) |
| `acnsdisabled-<rand>` | Cilium | Disabled | Baseline latency without advancedNetworking |

Only a single explicit **system** node pool is defined. Additional capacity is provided automatically by Node Auto Provisioning (`nodeProvisioningProfile.mode=Auto`). No user (static) node pools are specified. The system pool count is controlled by `system_node_count`.

Managed Grafana is **not** explicitly enabled.

## What Gets Deployed

Terraform (via `azapi_resource`) deploys:
* Two Automatic SKU AKS clusters (SystemAssigned identity)
* Advanced Networking (observability + security) on the primary cluster (requires Cilium dataplane)
* Cilium dataplane on both clusters (baseline parity; ACNS block omitted on second)
* Log Analytics Workspace + Azure Monitor (OMS agent) + Azure Policy addon
* ACR (optional, per existing Terraform files) and supporting resource group
* Random suffix for cluster uniqueness

Scripts:
* `0-test-prereqs.sh` – (Prerequisite validation)
* `1-infra.sh` – Auth validation, subscription selection (via `AZ_SUBSCRIPTION_ID`), Terraform init/apply, kubeconfig retrieval, `kubelogin` conversion
* `2-latency-test.sh` – Deploys the aks-store-demo Pets app and measures pod readiness latency for +1 node and ~+10 node provisioning scenarios recording to `latency-results.csv`

## Prerequisites

You need:
* Azure CLI (`az`) with `aks-preview` extension (for latest API behaviors)
* `kubectl`
* `kubelogin` (Azure authentication for kubectl)
* `helm`
* `jq`
* Bash, GNU coreutils

## Authentication & Subscription

Use the target subscription (e.g. Azure Network Agent Test sub) that bypasses SFI policy for this test.

You can export an env var for automation:
```bash
export AZ_SUBSCRIPTION_ID="<subscription-id>"
```

`1-infra.sh` will set the subscription if `AZ_SUBSCRIPTION_ID` is defined. Otherwise run manually:
```bash
az account set -s "<subscription-id>"
```

Azure login with Graph scope (script also enforces):
```bash
az login --use-device-code --scope https://graph.microsoft.com/.default
```

## Quick Start

```bash
az extension add --name aks-preview || az extension update --name aks-preview
az account set -s "<subscription-id>"
git clone https://github.com/danbosscher/aks-acns-cni-perftest
cd aks-acns-cni-perftest
chmod +x *.sh 4a-latency-test.sh
./0-test-prereqs.sh   # optional if present
./1-infra.sh          # deploy both clusters & fetch kubeconfigs
```

After deployment the script creates kubeconfig contexts:
* `acnsenabled` – cluster with advancedNetworking
* `acnsdisabled` – baseline cluster

If you need to (re)convert kubeconfig for Azure CLI auth:
```bash
kubelogin convert-kubeconfig -l azurecli
```

Verify contexts:
```bash
kubectl config get-contexts | grep acns
```

## Step 2: Deploy Pets Store & Measure Latency

Run the automated latency test script (installs chart if missing):
```bash
./4a-latency-test.sh
```

This performs for each cluster:
1. Installs / upgrades `aks-store-demo` chart (`replicaCount=30`) into namespace `pets`
2. Scales to 31 replicas to trigger a single node provision event (if capacity insufficient)
3. Measures time until all pods Ready (writes scenario `add_1_node`)
4. Scales to 330 replicas to approximate a ~10 node burst (density dependent)
5. Measures readiness latency (scenario `add_approx_10_nodes`)

Outputs CSV:
`latency-results.csv` columns:
```
timestamp,cluster,scenario,pod_ready_latency_ms,total_elapsed_ms
```

Interpretation:
* `pod_ready_latency_ms` – measured time from scale request to all pods in Running/Ready
* Goal: P99.5 < 120s for +1 node and similar for ACNS vs baseline; repeated runs recommended for real percentile

### Manual Chart Deployment (Optional)
```bash
helm repo add aks-store-demo https://pauldotyu.github.io/aks-store-demo
helm repo update
helm install pets aks-store-demo/aks-store-demo-chart \
	--namespace pets --create-namespace --set replicaCount=30 --kube-context acnsenabled
```

### Repeated / Statistical Runs
To gather distribution:
```bash
for i in {1..20}; do ./4a-latency-test.sh; sleep 30; done
```
Then aggregate latencies (example):
```bash
awk -F, 'NR>1 {k[$3]++; s[$3]+=$4; if($4>m[$3]) m[$3]=$4} END{for(i in k) printf "%s avg=%.1fms max=%sms n=%d\n", i, s[i]/k[i], m[i], k[i]}' latency-results.csv
```

## Variables (Selected)
Define in `terraform.tfvars` or via `-var` flags:
| Variable | Purpose | Default |
|----------|---------|---------|
| `aks_api_version` | Managed Cluster API version | 2025-07-01 |
| `aks_automatic_name` | Base name ACNS cluster | aks-automatic-acnsenabled |
| `aks_automatic_basic_name` | Base name baseline cluster | aks-automatic-acnsdisabled |
| `system_node_count` | Initial system pool size | 3 |
| `enable_advanced_networking` | Always true for ACNS cluster | true |

Random suffix is appended automatically in resource creation.

## Disabling Managed Grafana
No explicit `azureMonitorProfile` enabling Managed Grafana is present. If portal shows Grafana workspace linkage, capture the cluster properties (`az aks show`) and open an issue to add an explicit disabling block when schema fields are available.

## Cleanup
```bash
cd terraform
terraform destroy -auto-approve
```

Or use provided cleanup scripts (`5-cleanup.sh`) if tailored.

## Troubleshooting
| Issue | Action |
|-------|--------|
| `kubectl` auth errors | Re-run `kubelogin convert-kubeconfig -l azurecli` |
| Cluster not found for credentials | Confirm random suffix names with `az aks list -g <rg> -o table` |
| Latency file empty | Ensure `jq` installed and pods are scaling beyond existing capacity |
| Scale didn’t add nodes | Increase target replicas (adjust density) |

## Future Enhancements
* Add looping & percentile calculation inside script
* Explicit managed Grafana disable once GA schema published
* Custom Karpenter NodePool CRDs for tailored instance mixes

---
Generated as part of performance test automation enablement.
