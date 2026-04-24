# Skill: platform-vsphere

vSphere / vCenter prerequisites, IPI deployment steps, and OpenShift
Virtualization caveats for deploying OCP on VMware vSphere.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/

---

## Required CLIs

```bash
govc version            # VMware govmomi CLI
oc version --client
openshift-install version
```

Install govc: https://github.com/vmware/govmomi/tree/main/govc#installation

## Authentication Setup

```bash
export GOVC_URL="https://${VCENTER_FQDN}/sdk"
export GOVC_USERNAME="${VCENTER_USERNAME}"
export GOVC_PASSWORD="${VCENTER_PASSWORD}"
export GOVC_INSECURE=false  # set true only if using self-signed certs in lab

# Verify
govc about
```

Store vCenter password in `.secrets/vsphere-credentials.env` (gitignored).

## Required vSphere Privileges

The install account needs the following minimum privileges:

- **Datastore**: Allocate space, Browse, Low-level operations
- **Folder**: Create folder, Delete folder
- **Global**: Cancel task, Set custom attribute
- **Network**: Assign network
- **Resource**: Assign VM to resource pool, Migrate VM
- **Virtual machine**: Configuration (all), Interaction (all), Inventory (all), Provisioning (all)
- **vCenter Inventory Service**: Add, Modify, Remove
- **vSphere Tagging**: All

Full list: https://docs.openshift.com/container-platform/latest/installing/installing_vsphere/installing-vsphere-installer-provisioned.html#installation-vsphere-installer-infra-requirements_installing-vsphere-installer-provisioned

## Infrastructure Prerequisites

- vSphere ≥ 7.0 Update 2 (vSphere 8 recommended)
- vCenter ≥ 7.0 Update 2
- DRS and HA **enabled** on the target cluster
- Datastore must have sufficient free space:
  - Control plane: 3 × (100 GiB disk + 40 GiB etcd) = ~420 GiB
  - Workers: N × disk_gib
- Portgroup (VM Network) exists and has connectivity to the external network
- VM folder pre-created (or installer creates one)

## Networking Prerequisites

- DHCP or static IPs for all nodes in the machine CIDR
- DNS A records before install:
  - `api.<cluster>.<domain>` → API VIP
  - `*.apps.<cluster>.<domain>` → Ingress VIP
- NTP synchronisation on all nodes and vCenter

## Example install-config snippet

```yaml
platform:
  vsphere:
    vcenter: ${VCENTER_FQDN}
    username: ${VCENTER_USERNAME}
    password: ${VCENTER_PASSWORD}
    datacenter: ${VSPHERE_DATACENTER}
    defaultDatastore: ${VSPHERE_DATASTORE}
    folder: ${VSPHERE_FOLDER}
    network: ${VSPHERE_NETWORK}
    cluster: ${VSPHERE_CLUSTER}
    # Optional resource pool (omit to use cluster default)
    # resourcePool: ${VSPHERE_RESOURCE_POOL}
```

See full template: `templates/install-config/vsphere.install-config.yaml.tmpl`

## OpenShift Virtualization on vSphere — Caveats

| Requirement | Detail |
|---|---|
| CPU passthrough / EVC | Set vSphere CPU compatibility mode to `Passthrough` or use EVC mode >= Haswell to expose `vmx`/`svm` flags. |
| Nested virtualisation | Enable in VM settings: **CPU > Hardware Virtualisation > Expose hardware-assisted virtualisation**. Apply via MachineConfig or VM template. |
| Storage for live migration | vSphere CSI driver provides RWX on vSAN File Service. Alternatively, deploy ODF or NFS. |
| vSAN | Recommended for ODF backing. iSCSI and NFS also work. |
| Hugepages | Configure in MachineConfig for high-performance VM workloads. |
| MAC address pools | Configure `KubeMacPool` range to avoid conflicts with existing VMs. |

### Enabling hardware virtualisation in VM template

Via govc before cloning the RHCOS template:

```bash
govc vm.change \
  -vm "${VSPHERE_FOLDER}/${CLUSTER_NAME}-bootstrap" \
  -nested-hv-enabled=true
```

Or via MachineConfig after install (requires node reboot):

```bash
oc apply -f - <<'EOF'
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-nested-virt
spec:
  config:
    ignition:
      version: 3.4.0
    systemd:
      units: []
EOF
# Hardware virtualisation must be enabled at the vSphere level.
```

### Verify CPU flags after deploy

```bash
oc debug node/<worker-node> -- grep -m1 vmx /proc/cpuinfo
# Should show: vmx (Intel) or svm (AMD)
```
