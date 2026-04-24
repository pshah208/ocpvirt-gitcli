# Skill: platform-azure

Azure-specific prerequisites, IPI deployment steps, and OpenShift Virtualization
caveats for deploying OCP on Microsoft Azure.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_azure/

---

## Required CLIs

```bash
az --version           # Azure CLI >= 2.x
oc version --client
openshift-install version
```

Install Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli

## Authentication Setup

```bash
# Login interactively
az login

# Service principal (CI/non-interactive)
az login \
  --service-principal \
  --username <app-id> \
  --password <client-secret> \
  --tenant <tenant-id>

# Verify
az account show
```

Store SP credentials in `.secrets/azure-credentials.json` (gitignored) or
Azure Key Vault — never in source code.

## Minimum IAM / RBAC Permissions

The installer service principal needs **Contributor** role on the subscription
plus `User Access Administrator` to create role assignments for cluster
components.

For manual credential mode (`credentialsMode: Manual`), pre-create app
registrations for each component. See:
https://docs.openshift.com/container-platform/latest/installing/installing_azure/manually-creating-iam-azure.html

## Networking Prerequisites

- **Resource Group**: installer creates one by default; or provide an existing
  pre-created empty group.
- **VNet**: installer creates; or provide existing VNet + subnets IDs in
  `platform.azure.networkResourceGroupName`.
- **DNS zone**: Azure DNS public zone for base domain must exist.
- **Azure Load Balancer** (Standard SKU) is created automatically by the
  installer.

## Example install-config snippet

```yaml
platform:
  azure:
    baseDomainResourceGroupName: ${AZURE_DNS_RG}
    region: ${AZURE_REGION}
    # Uncomment for existing resource group:
    # resourceGroupName: ${AZURE_RG}
    # Uncomment for existing VNet:
    # virtualNetwork: ${AZURE_VNET}
    # controlPlaneSubnet: ${AZURE_CP_SUBNET}
    # computeSubnet: ${AZURE_WORKER_SUBNET}
    # networkResourceGroupName: ${AZURE_VNET_RG}
```

See full template: `templates/install-config/azure.install-config.yaml.tmpl`

## OpenShift Virtualization on Azure — Caveats

| Requirement | Detail |
|---|---|
| Nested virtualisation | Only supported on **Dsv3**, **Dsv5**, **Esv3**, **Esv5**, and **Ebsv5** VM families. |
| Recommended SKU for CNV workers | `Standard_D16s_v5` (16 vCPU / 64 GiB) or `Standard_E16s_v5` |
| Storage for live migration | Azure Disk (RWO only); deploy ODF or Azure Files for RWX. |
| Ultra Disk | Supported for high-IOPS VM disks; not required for base install. |
| Availability Zones | Use zones for HA; not all regions have 3 AZs. |

### Enabling nested virt on workers

Workers using Dsv5/Esv5 get nested virtualisation automatically.
Verify after deploy:

```bash
oc debug node/<worker-node> -- grep -m1 vmx /proc/cpuinfo
```

### Setting worker SKU in install-config

```yaml
compute:
  - name: worker
    replicas: 3
    platform:
      azure:
        type: Standard_D16s_v5
        osDisk:
          diskSizeGB: 128
          diskType: Premium_LRS
        zones:
          - "1"
          - "2"
          - "3"
```
