# Skill: size-cluster

Helps determine the correct number of nodes and resource sizing for an
OpenShift (and optionally OpenShift Virtualization) cluster.

See also: `docs/sizing-guide.md` for full reference tables.

---

## Sizing Inputs

Ask the user:

1. **Topology**: compact | standard | SNO | ha-infra
2. **Workload profile**: dev/test | production | CNV-heavy | mixed
3. **Number of application pods** (rough estimate)
4. **For CNV**: estimated number of VMs, average vCPU/RAM per VM, percentage
   with live migration enabled

---

## Control-Plane Sizing

| Environment | vCPU | RAM | Root Disk |
|---|---|---|---|
| Minimum (lab) | 4 | 16 GiB | 120 GiB |
| Recommended (prod) | 8 | 32 GiB | 120 GiB |
| Large clusters (500+ nodes) | 16 | 64 GiB | 120 GiB |

Control-plane nodes **must not** run application or VM workloads in production.
For compact (3-node) clusters, control-plane nodes are schedulable — size them
as workers.

## Worker Sizing

| Workload | Min vCPU | Min RAM | Notes |
|---|---|---|---|
| General OCP workloads | 4 | 16 GiB | Baseline |
| CNV VM hosting | 16 | 64 GiB | CPU Manager recommended |
| CNV high-density | 32 | 128 GiB | Dedicated workers, hugepages |
| Infra nodes (router, registry, monitoring) | 4 | 16 GiB | Taint `infra` |

### CNV Worker Formula

```
required_vcpu = (sum of all VM vCPUs) * 1.10   # 10 % overhead
required_ram  = (sum of all VM RAM) + 12 GiB    # 12 GiB OS + overhead
workers_needed = ceil(required_vcpu / worker_vcpu)
```

Ensure at least 3 workers for pod scheduling redundancy.

## 3-Node Compact

- Schedulable masters ≥ 8 vCPU / 32 GiB each.
- **Not recommended** for heavy CNV workloads.
- No dedicated infra nodes; infra pods schedule on masters.

## SNO (Single-Node OpenShift)

- Minimum: 8 vCPU / 32 GiB / 120 GiB.
- No HA; use for edge or development only.
- CNV is supported but live migration is not available (only cold migration).

## Platform-specific Recommendations

### AWS

| Role | Recommended Instance | Notes |
|---|---|---|
| Control plane | `m6i.xlarge` (4 vCPU / 16 GiB) | or `m6i.2xlarge` for prod |
| Worker (general) | `m6i.2xlarge` (8 vCPU / 32 GiB) | |
| Worker (CNV) | `m6i.metal` (128 vCPU / 512 GiB) | Required for nested virt |
| Infra | `m6i.xlarge` | |

### Azure

| Role | Recommended SKU | Notes |
|---|---|---|
| Control plane | `Standard_D8s_v5` (8 vCPU / 32 GiB) | |
| Worker (general) | `Standard_D8s_v5` | |
| Worker (CNV) | `Standard_D16s_v5` or `Standard_E16s_v5` | Dsv5/Esv5 support nested virt |
| Infra | `Standard_D4s_v5` | |

### GCP

| Role | Recommended Type | Notes |
|---|---|---|
| Control plane | `n2-standard-8` | |
| Worker (general) | `n2-standard-8` | |
| Worker (CNV) | `n2-standard-16` | Enable `--enable-nested-virtualization` |
| Infra | `n2-standard-4` | |

### vSphere / Bare-metal

| Role | vCPU | RAM | Disk |
|---|---|---|---|
| Control plane | 8 | 32 GiB | 120 GiB |
| Worker (general) | 8 | 32 GiB | 120 GiB |
| Worker (CNV) | 16+ | 64+ GiB | 120 GiB + data disks |
| Infra | 4 | 16 GiB | 120 GiB |

---

## Output

Emit a sizing summary:

```yaml
sizing_summary:
  control_plane:
    count: 3
    vcpu: 8
    ram_gib: 32
    disk_gib: 120
  workers:
    count: 6
    vcpu: 16
    ram_gib: 64
    disk_gib: 120
  infra_nodes:
    count: 3
    vcpu: 4
    ram_gib: 16
    disk_gib: 120
  notes: "Dedicated CNV workers with CPU Manager and 64 GiB RAM."
```
