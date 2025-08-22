# AKS Advanced Networking & Node Auto Provisioning Performance Test

This repository provisions two **AKS Automatic** SKU clusters (Kubernetes version via variable) to measure Node Auto Provisioning (NAP / Karpenter-managed) scale latency **with and without Advanced Container Networking Services (ACNS)** enabled.

| Cluster | Dataplane | ACNS | Purpose |
|---------|-----------|------|---------|
| `acnsenabled-<rand>`  | Cilium | Enabled  | Test latency with advancedNetworking (observability + security) |
| `acnsdisabled-<rand>` | Cilium | Disabled | Baseline latency without advancedNetworking |

Only a single explicit **system** node pool is defined. Additional capacity is provided automatically by Node Auto Provisioning (`nodeProvisioningProfile.mode=Auto`). No user (static) node pools are specified. The system pool count is controlled by `system_node_count`.



## What Gets Deployed

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

You need to (re)convert kubeconfig for Azure CLI auth:
```bash
kubelogin convert-kubeconfig -l azurecli
```