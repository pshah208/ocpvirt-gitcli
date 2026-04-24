# OpenShift Virtualization (CNV) — Deployment and Operations Guide

Reference: https://docs.openshift.com/container-platform/latest/virt/

---

## Overview

OpenShift Virtualization (formerly Container-Native Virtualization / CNV)
enables running virtual machines natively on OpenShift alongside containers.
It is built on **KubeVirt** and managed by the **HyperConverged Cluster Operator
(HCO)**.

---

## Prerequisites

### Cluster Requirements

- OpenShift 4.12 or later (4.15+ recommended for latest features).
- Worker nodes must expose CPU virtualisation extensions:
  - **Intel**: `vmx` flag in `/proc/cpuinfo`
  - **AMD**: `svm` flag in `/proc/cpuinfo`
- For cloud deployments, nested virtualisation must be enabled at the hypervisor
  level (see platform skills for platform-specific instructions).

### Storage Requirements

| Storage Class | Access Mode | Live Migration | Notes |
|---|---|---|---|
| ODF (CephFS) | RWX | ✅ Yes | Recommended |
| ODF (RBD) | RWO / ROX | ❌ No | Block; use for boot disks with CDI |
| NFS (external) | RWX | ✅ Yes | Requires NFS provisioner |
| Local Storage (LSO) | RWO | ❌ No | Boot VMs only; no live migration |
| Cloud default (EBS/PD) | RWO | ❌ No | Not suitable for live migration |

**Live migration requires an RWX-capable storage class.**

### Networking Requirements

- **OVN-Kubernetes** (default in OCP 4.12+) is required for pod networking.
- For bridged VM networks (L2 access): NMState Operator + linux-bridge CNI.
- For DHCP/IP management on secondary networks: use MetalLB or external DHCP.
- MAC address pool (KubeMacPool) should be configured to avoid conflicts.

---

## Installation

```bash
# Apply the CNV manifests (creates namespace, operatorgroup, subscription, HCO)
bash scripts/install-cnv.sh

# Monitor HCO readiness
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions}' | jq .
```

The install script waits up to 15 minutes for HCO to become `Available=True`.

---

## HyperConverged Operator (HCO) Configuration

The `HyperConverged` CR is the single point of configuration for all CNV
components. Key fields:

```yaml
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  # Feature gates
  featureGates:
    withHostPassthroughCPU: false    # Set true for bare-metal CPU passthrough
    deployKubeSecondaryDNS: false

  # Live migration defaults
  liveMigrationConfig:
    parallelMigrationsPerCluster: 5
    parallelOutboundMigrationsPerNode: 2
    completionTimeoutPerGiB: 800
    progressTimeout: 150

  # Workload update strategy (for rolling kubevirt upgrades)
  workloadUpdateStrategy:
    workloadUpdateMethods:
      - LiveMigrate
      - Evict
    batchEvictionInterval: 1m
    batchEvictionSize: 10
```

---

## Supported Storage Configurations

### ODF (OpenShift Data Foundation) — Recommended

Provides both RWX (CephFS) and RWO/block (RBD) storage classes.

```bash
oc apply -f templates/storage/odf-subscription.yaml
```

After the StorageCluster is ready, set the CephFS class as default for VMs:

```bash
oc annotate storageclass ocs-storagecluster-cephfs \
  storageclass.kubernetes.io/is-default-class=true
```

### LSO + HostPath Provisioner (lab / bare-metal without Ceph)

```bash
oc apply -f templates/storage/lso-subscription.yaml
oc apply -f templates/storage/hostpath-provisioner.yaml
```

Note: hostpath is RWO only; live migration is not supported.

---

## Networking

### NMState Operator

Manages node network configuration declaratively. Required for linux-bridge
and bonding on worker nodes.

```bash
oc apply -f templates/networking/nmstate-operator.yaml
# Apply a NodeNetworkConfigurationPolicy (example: linux bridge)
oc apply -f templates/networking/nncp-example.yaml
```

### NetworkAttachmentDefinition (for bridged VMs)

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: br-flat
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "br-flat",
      "type": "cnv-bridge",
      "bridge": "br-flat",
      "macspoofchk": true
    }
```

### MetalLB (for bare-metal / vSphere LB)

```bash
oc apply -f templates/networking/metallb-operator.yaml
```

---

## Hugepages

Pre-allocate 1 GiB hugepages on CNV worker nodes for latency-sensitive VMs:

```bash
oc apply -f - <<'EOF'
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
EOF
```

---

## SR-IOV (High-Performance Networking)

Install the SR-IOV Network Operator and create `SriovNetworkNodePolicy` and
`SriovNetwork` resources to attach SR-IOV VFs directly to VMs.

Reference: https://docs.openshift.com/container-platform/latest/networking/hardware_networks/about-sriov.html

---

## Migration Policies

Create per-namespace migration policies to control concurrency and behaviour:

```yaml
apiVersion: migrations.kubevirt.io/v1alpha1
kind: MigrationPolicy
metadata:
  name: large-vms
spec:
  selectors:
    namespaceSelector:
      matchLabels:
        large-vms: "true"
  completionTimeoutPerGiB: 400
  allowAutoConverge: true
  allowPostCopy: false
```

---

## Backup and Disaster Recovery

Use **OADP (OpenShift API for Data Protection)** with the KubeVirt plugin for
VM-consistent backups:

```bash
# Install OADP Operator via OperatorHub or CLI
# Reference: https://docs.openshift.com/container-platform/latest/backup_and_restore/application_backup_and_restore/
```

Key considerations:
- Quiesce VMs before backup for application consistency.
- Use Velero `VolumeSnapshotLocation` backed by your storage provider.
- Test restore procedures regularly.

---

## Validation Checklist

```bash
# 1. HCO Available
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'
# Expected: True

# 2. All CNV pods Running
oc get pods -n openshift-cnv | grep -v Running

# 3. Storage class supports RWX
oc get storageclass | grep -i rwx

# 4. CPU flags on workers
oc debug node/<worker> -- grep -m1 vmx /proc/cpuinfo 2>/dev/null

# 5. Deploy test VM and confirm SSH
virtctl ssh fedora@fedora-test -n default
```
