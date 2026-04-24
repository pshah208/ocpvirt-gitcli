# Cluster Sizing Guide

This guide provides recommended resource allocations for OpenShift control-plane
and worker nodes across different workloads and platforms.

Reference: https://docs.openshift.com/container-platform/latest/scalability_and_performance/recommended-performance-scale-practices/

---

## Control-Plane Sizing

| Cluster scale | vCPU | RAM | Root disk | etcd disk |
|---|---|---|---|---|
| Lab / PoC (≤ 25 nodes) | 4 | 16 GiB | 120 GiB | SSD recommended |
| Production (≤ 100 nodes) | 8 | 32 GiB | 120 GiB | SSD required |
| Large (≤ 500 nodes) | 16 | 64 GiB | 120 GiB | NVMe recommended |

- Always use 3 control-plane nodes for HA (odd number required for etcd quorum).
- Control-plane nodes should not run application or VM workloads in production.
- etcd is latency-sensitive: use local SSD or NVMe, not network-attached storage.

---

## Worker Node Sizing

### General Application Workloads

| Profile | vCPU | RAM | Root disk |
|---|---|---|---|
| Minimum | 4 | 16 GiB | 120 GiB |
| Recommended | 8 | 32 GiB | 120 GiB |
| High-density (many pods) | 16 | 64 GiB | 120 GiB |

### OpenShift Virtualization (CNV) Workers

| Profile | vCPU | RAM | Root disk | Notes |
|---|---|---|---|---|
| Light (≤ 10 VMs/node) | 16 | 64 GiB | 120 GiB | CPU Manager recommended |
| Medium (≤ 30 VMs/node) | 32 | 128 GiB | 120 GiB | Dedicated workers, hugepages |
| High-density (≤ 80 VMs/node) | 64 | 256 GiB | 120 GiB + data disks | NVMe, hugepages, SR-IOV |

**CNV worker formula:**

```
required_vcpu  = (total VM vCPUs) × 1.10    # 10 % overhead
required_ram   = (total VM RAM)  + 12 GiB   # 12 GiB for OS + overhead
workers_needed = ceil(required_vcpu / per_worker_vcpu)
```

Always have at least 3 CNV workers for pod-scheduling redundancy during node
drain/maintenance.

### Infra Nodes (router, image registry, monitoring)

| Role | vCPU | RAM | Root disk |
|---|---|---|---|
| Infra (small) | 4 | 16 GiB | 120 GiB |
| Infra (prod) | 8 | 32 GiB | 120 GiB |

Taint infra nodes with `node-role.kubernetes.io/infra=:NoSchedule` to prevent
application workloads from scheduling there.

---

## Topology Profiles

### Standard (3 CP + N Workers)

- Minimum: 3 × CP + 3 × worker.
- Recommended for production.
- Separate control-plane from worker traffic.

### 3-Node Compact (Schedulable Masters)

- 3 nodes that act as both control-plane and workers.
- Each node: **minimum 8 vCPU / 32 GiB** (more is better).
- **Not recommended** for heavy CNV workloads — resource contention with etcd.
- Good for resource-constrained lab or edge use.

### SNO (Single-Node OpenShift)

- 1 node: **minimum 8 vCPU / 32 GiB / 120 GiB**.
- No high availability.
- CNV supported, but **live migration is not available** (cold migration only).
- Use for edge locations or developer laptops (via KVM).

### HA with Infra Nodes

- 3 CP + N workers + M infra nodes (M ≥ 2 for HA router/ingress).
- Best for large production clusters.

---

## Platform-Specific Instance Recommendations

### AWS

| Role | Instance Type | vCPU | RAM | Notes |
|---|---|---|---|---|
| Control plane | m6i.xlarge | 4 | 16 GiB | Min; use m6i.2xlarge for prod |
| Control plane (prod) | m6i.2xlarge | 8 | 32 GiB | |
| Worker (general) | m6i.2xlarge | 8 | 32 GiB | |
| Worker (CNV) | m6i.metal | 128 | 512 GiB | Required for VMX; expensive |
| Infra | m6i.xlarge | 4 | 16 GiB | |

### Azure

| Role | VM SKU | vCPU | RAM | Notes |
|---|---|---|---|---|
| Control plane | Standard_D8s_v5 | 8 | 32 GiB | |
| Worker (general) | Standard_D8s_v5 | 8 | 32 GiB | |
| Worker (CNV) | Standard_D16s_v5 | 16 | 64 GiB | Dsv5 supports nested virt |
| Worker (CNV heavy) | Standard_E32s_v5 | 32 | 256 GiB | Memory-optimised |
| Infra | Standard_D4s_v5 | 4 | 16 GiB | |

### GCP

| Role | Machine Type | vCPU | RAM | Notes |
|---|---|---|---|---|
| Control plane | n2-standard-8 | 8 | 32 GiB | |
| Worker (general) | n2-standard-8 | 8 | 32 GiB | |
| Worker (CNV) | n2-standard-16 | 16 | 64 GiB | Enable nested virt |
| Worker (CNV heavy) | n2-standard-32 | 32 | 128 GiB | Enable nested virt |
| Infra | n2-standard-4 | 4 | 16 GiB | |

### vSphere / Bare-metal

| Role | vCPU | RAM | Root Disk | Notes |
|---|---|---|---|---|
| Control plane | 8 | 32 GiB | 120 GiB | NVMe-backed datastore |
| Worker (general) | 8 | 32 GiB | 120 GiB | |
| Worker (CNV) | 16+ | 64+ GiB | 120 GiB | + data disks for ODF |
| Worker (CNV heavy) | 32+ | 128+ GiB | 120 GiB | Hugepages, CPU pinning |
| Infra | 4 | 16 GiB | 120 GiB | |

---

## Hugepages for CNV

For latency-sensitive VMs (telco, real-time), pre-allocate hugepages on worker
nodes via MachineConfig:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker-cnv
  name: 99-cnv-hugepages
spec:
  config:
    ignition:
      version: 3.4.0
  kernelArguments:
    - hugepagesz=1G
    - hugepages=16
```

This allocates 16 × 1 GiB hugepages per worker (adjust as needed).
