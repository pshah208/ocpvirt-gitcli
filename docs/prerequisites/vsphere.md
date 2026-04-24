# vSphere Prerequisites

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/

---

## vSphere Version Requirements

| Component | Minimum Version |
|---|---|
| vSphere / ESXi | 7.0 Update 2 |
| vCenter Server | 7.0 Update 2 |
| vSphere 8 | Fully supported (recommended) |
| Hardware Version | VMX-15 or later |

## Required vSphere Infrastructure

- **Datacenter** with the target cluster
- **Datastore** (vSAN, VMFS, or NFS) with:
  - At least 400 GiB free for a standard 3+3 cluster
  - Low-latency recommended (SSD-backed)
- **VM Folder** (pre-create or let installer create)
- **Portgroup** with connectivity to the machine network CIDR
- **Resource Pool** (optional; uses cluster root pool by default)
- **DRS and vSphere HA** enabled on the target cluster

## vCenter Account Permissions

Create a dedicated vCenter service account with the following privileges:

```
Datastore:
  AllocateSpace, Browse, FileManagement, UpdateVirtualMachineFiles
Folder:
  Create, Delete
Global:
  CancelTask, SetCustomAttribute
Network:
  AssignNetwork
Resource:
  AssignVMToPool, MigrateVMPoweredOff, MigrateVMPoweredOn
StoragePolicy:
  View
VirtualMachine.Configuration (all)
VirtualMachine.Interaction (all)
VirtualMachine.Inventory (all)
VirtualMachine.Provisioning (all)
vSphere Tagging (all)
```

Full reference: https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/installing-vsphere-installer-provisioned.html#installation-vsphere-installer-infra-requirements_installing-vsphere-installer-provisioned

## Network Prerequisites

- DHCP or static IP reservation for all nodes in the machine CIDR.
- DNS A records **before** install:
  - `api.<cluster>.<domain>` → API VIP (or external LB IP)
  - `api-int.<cluster>.<domain>` → same as API VIP
  - `*.apps.<cluster>.<domain>` → Ingress VIP
- NTP synchronisation on vCenter and all ESXi hosts.
- The portgroup must allow VM-to-VM and VM-to-uplink traffic.

## Pre-install Checks

```bash
export GOVC_URL="https://${VCENTER_FQDN}/sdk"
export GOVC_USERNAME="${VCENTER_USERNAME}"
export GOVC_PASSWORD="${VCENTER_PASSWORD}"

# Test connectivity
govc about

# Check datacenter
govc datacenter.info "${VSPHERE_DATACENTER}"

# Check cluster
govc cluster.info "${VSPHERE_CLUSTER}"

# Check datastore free space (GB)
govc datastore.info "${VSPHERE_DATASTORE}" | grep -i free

# Check portgroup
govc network.info "${VSPHERE_NETWORK}"
```

## CNV on vSphere — Additional Requirements

- Enable **hardware virtualisation** in each worker VM's CPU settings:
  - vSphere UI: VM > Edit > CPU > Expose hardware-assisted virtualisation to guest OS
  - Or set CPU compatibility mode to `Passthrough` or EVC mode ≥ Haswell.

- **vSAN File Service** or external NFS required for RWX storage (live migration).

- Configure `KubeMacPool` MAC range in the HyperConverged CR to avoid conflicts
  with existing vSphere VM MACs.

```bash
# Check if vSAN File Service is enabled (for RWX)
govc datastore.info "${VSPHERE_DATASTORE}" | grep -i vsan

# Verify CPU passthrough setting on a VM
govc vm.info -json <vm-name> | \
  jq '.VirtualMachines[].Config.Hardware.NumCPU'
```

## vSphere CSI Driver

The installer configures the vSphere CSI driver automatically (IPI). Ensure:

- vCenter has a valid certificate (or thumbprint is provided in install-config).
- The service account has `StorageProfile.View` privilege.
- vSphere CNS (Cloud Native Storage) is available in vCenter 7.0+.

```bash
# After install, verify CSI driver
oc get storageclass
oc get csidrivers
```
