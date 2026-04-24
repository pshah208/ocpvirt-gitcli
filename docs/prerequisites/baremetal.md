# Bare-Metal Prerequisites

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/

---

## Overview

Bare-metal deployments use the **Agent-based Installer** (recommended for OCP
4.12+). Each node boots from a generated ISO; no PXE/DHCP server is required
by default.

## Hardware Requirements

| Role | Min vCPU | Min RAM | Min Disk |
|---|---|---|---|
| Control plane | 8 | 32 GiB | 120 GiB |
| Worker | 8 | 32 GiB | 120 GiB |
| Worker (CNV) | 16+ | 64+ GiB | 120 GiB |

- UEFI or Legacy BIOS supported (UEFI preferred).
- NIC with PXE or virtual media boot capability.
- BMC (iDRAC, iLO, iRMC, etc.) reachable from the installer host.

## BMC Requirements

Supported BMC protocols:

| Protocol | URL format |
|---|---|
| Redfish | `redfish+http://<ip>/redfish/v1/Systems/1` |
| Redfish TLS | `redfish+https://<ip>/redfish/v1/Systems/1` |
| Dell iDRAC Redfish | `idrac-virtualmedia+https://<ip>/redfish/v1/Systems/System.Embedded.1` |
| HPE iLO Redfish | `ilo5-virtualmedia+https://<ip>/redfish/v1/Systems/1` |
| IPMI | `ipmi://<ip>` |

Test BMC connectivity:

```bash
# Redfish
curl -sku "${BMC_USER}:${BMC_PASS}" \
  "https://${BMC_IP}/redfish/v1/Systems" | jq .

# IPMI
ipmitool -I lanplus -H "${BMC_IP}" \
  -U "${BMC_USER}" -P "${BMC_PASS}" \
  chassis power status
```

## Network Prerequisites

### VIPs (must be free / not in use)

- **API VIP**: `api.<cluster>.<domain>` — must resolve via DNS
- **Ingress VIP**: `*.apps.<cluster>.<domain>` — must resolve via DNS

Check VIPs are not in use:

```bash
arping -I <nic> -c3 "${API_VIP}"      # no reply = free
arping -I <nic> -c3 "${INGRESS_VIP}"  # no reply = free
```

### DNS Records (before install)

```bash
# Add to DNS server before running openshift-install
nslookup "api.${CLUSTER_NAME}.${BASE_DOMAIN}"
nslookup "test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"
```

### NTP

All nodes must have NTP connectivity. RHCOS uses chronyd; configure a
reachable NTP source via MachineConfig if your network is air-gapped.

### Rendezvous IP

The **Rendezvous host** is the first master node (or any host in the cluster)
designated to coordinate bootstrap. Its IP address must be stable and known
before ISO generation.

```bash
# Verify rendezvous IP is reachable from installer host
ping -c3 "${RENDEZVOUS_IP}"
```

## Storage for CNV on Bare-Metal

- Physical CPUs expose `vmx`/`svm` natively — no special config needed.
- Deploy **ODF** (3+ workers with NVMe/SAS) for RWX storage and live migration.
- For single-node lab: use **LSO + hostpath provisioner** (RWO only).

```bash
# After install, verify CPU flags on workers
for node in $(oc get nodes -l node-role.kubernetes.io/worker \
  -o jsonpath='{.items[*].metadata.name}'); do
  echo -n "${node}: "
  oc debug "node/${node}" -- grep -m1 -o 'vmx\|svm' /proc/cpuinfo 2>/dev/null
done
```

## Pre-install Checklist

- [ ] All hosts powered off and BMC reachable
- [ ] API VIP and Ingress VIP are free
- [ ] DNS A records created for API, API-int, and wildcard ingress
- [ ] NTP reachable from all host BMCs and network
- [ ] ISO can be mounted via BMC virtual media (or USB prepared)
- [ ] `openshift-install` version matches target OCP release
- [ ] Pull secret and SSH key in `.secrets/`
