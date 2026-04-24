# Skill: platform-baremetal-agent

Bare-metal Agent-based Installer prerequisites and deployment steps, including
Rendezvous IP, API/Ingress VIPs, and per-host BMC configuration.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/

---

## Overview

The Agent-based Installer creates a bootable ISO that each node boots from.
One node acts as the **Rendezvous host** to coordinate discovery. The cluster
is built entirely on-premises without a cloud provider.

## Required CLIs

```bash
openshift-install version   # >= 4.12 for agent subcommand
oc version --client
ipmitool -V   # for IPMI BMC access
# or
curl https://<bmc>/redfish/v1/  # for Redfish BMC access
```

## Prerequisites

### Network

- **Two static VIPs** (not in use):
  - `API VIP`: `api.<cluster>.<domain>` DNS A record
  - `Ingress VIP`: `*.apps.<cluster>.<domain>` wildcard DNS A record
- All hosts must be on the same L2 segment as the Rendezvous host, OR routable
  to it on port 8090 (assisted-service).
- NTP configured and reachable from all hosts.
- PXE/DHCP not required (ISO boot).

### BMC

Each host's BMC must be reachable from the machine running `openshift-install`.
Supported protocols:

| Protocol | URL format |
|---|---|
| Redfish | `redfish+http://<bmc-ip>/redfish/v1/Systems/1` |
| Redfish TLS | `redfish+https://<bmc-ip>/redfish/v1/Systems/1` |
| IPMI | `ipmi://<bmc-ip>` |
| Dell iDRAC (Redfish) | `idrac-virtualmedia+https://<bmc-ip>/redfish/v1/Systems/System.Embedded.1` |

### Host list

For each host, gather:
- Hostname
- Role: `master` or `worker`
- MAC address of the primary NIC (used for discovery matching)
- BMC address, username, and password (password stored in `.secrets/`)
- Root device hints (if multiple disks)

## Example agent-config.yaml

See template: `templates/agent/agent-config.yaml.tmpl`

```yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: ${CLUSTER_NAME}
rendezvousIP: ${RENDEZVOUS_IP}
hosts:
  - hostname: master-0
    role: master
    interfaces:
      - name: eno1
        macAddress: "aa:bb:cc:dd:ee:01"
    rootDeviceHints:
      deviceName: /dev/sda
    bmc:
      address: redfish+http://192.168.1.10/redfish/v1/Systems/1
      username: admin
      # password loaded from .secrets/bmc-master-0.txt at render time
      disableCertificateVerification: false
```

## Deployment Steps

### 1. Render configs

```bash
VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/install-config/baremetal.install-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/install-config.yaml"

VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/agent/agent-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/agent-config.yaml"
```

### 2. Generate the agent ISO

```bash
openshift-install agent create image \
  --dir "build/${CLUSTER_NAME}" \
  --log-level debug
# Output: build/${CLUSTER_NAME}/agent.x86_64.iso
```

### 3. Boot each host from the ISO

Options:
- Mount as virtual media via BMC (Redfish/iLO/iDRAC).
- Write to USB: `dd if=agent.x86_64.iso of=/dev/sdX bs=4M status=progress`
- Serve via HTTP and PXE-chain.

Using `openshift-install` automated BMC booting (if BMC details in
agent-config):

```bash
# The installer can trigger virtual media boot via Redfish automatically
openshift-install agent create image --dir "build/${CLUSTER_NAME}"
# Then boot via scripts/platforms/baremetal-agent.sh
bash scripts/platforms/baremetal-agent.sh
```

### 4. Monitor installation

```bash
openshift-install agent wait-for bootstrap-complete \
  --dir "build/${CLUSTER_NAME}" --log-level debug

openshift-install agent wait-for install-complete \
  --dir "build/${CLUSTER_NAME}" --log-level debug
```

### 5. Export KUBECONFIG

```bash
export KUBECONFIG="build/${CLUSTER_NAME}/auth/kubeconfig"
oc get nodes
```

## OpenShift Virtualization on Bare-Metal

| Requirement | Detail |
|---|---|
| CPU flags | `vmx` (Intel) or `svm` (AMD) must be present in `/proc/cpuinfo`. |
| No nested virt needed | Physical CPUs expose flags natively — no special config required. |
| Storage | ODF on NVMe/SAS recommended for RWX. LSO + hostpath for single-node. |
| SR-IOV | Configure via SR-IOV Network Operator for high-performance NICs. |
| Hugepages | Pre-allocate via MachineConfig for latency-sensitive VMs. |
