# AKS Advanced Networking & Node Auto Provisioning Performance Test

This repository provisions two **AKS Automatic** SKU clusters (Kubernetes version via variable) to measure Node Auto Provisioning (NAP / Karpenter-managed) scale latency **with and without Advanced Container Networking Services (ACNS)** enabled.

| Cluster | Dataplane | ACNS | Purpose |
|---------|-----------|------|---------|
| `acnsenabled-<rand>`  | Cilium | Enabled  | Test latency with advancedNetworking (observability + security) |
| `acnsdisabled-<rand>` | Cilium | Disabled | Baseline latency without advancedNetworking |

Only a single explicit **system** node pool is defined. Additional capacity is provided automatically by Node Auto Provisioning (`nodeProvisioningProfile.mode=Auto`). No user (static) node pools are specified. The system pool count is controlled by `system_node_count`.

## Quick Start

```bash
az extension add --name aks-preview || az extension update --name aks-preview
az account set -s "<subscription-id>"
git clone https://github.com/danbosscher/aks-acns-cni-perftest
cd aks-acns-cni-perftest
chmod +x *.sh
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