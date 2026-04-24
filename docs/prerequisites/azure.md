# Azure Prerequisites

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_azure/

---

## Azure Account Requirements

- An Azure subscription (Pay-As-You-Go or EA).
- An Azure Active Directory (AAD) service principal with **Contributor** and
  **User Access Administrator** roles on the subscription.
- A **public DNS zone** for the base domain hosted in Azure DNS.

## Service Principal Setup

```bash
# Create service principal
az ad sp create-for-rbac \
  --name "ocp-install-sp" \
  --role Contributor \
  --scopes "/subscriptions/${AZURE_SUBSCRIPTION_ID}"

# Grant User Access Administrator for role assignment (needed by installer)
az role assignment create \
  --assignee <sp-app-id> \
  --role "User Access Administrator" \
  --scope "/subscriptions/${AZURE_SUBSCRIPTION_ID}"
```

Store the SP credentials in `.secrets/azure-credentials.json`:

```json
{
  "subscriptionId": "...",
  "clientId": "...",
  "clientSecret": "...",
  "tenantId": "..."
}
```

Reference environment variable: `AZURE_AUTH_LOCATION=.secrets/azure-credentials.json`

## Service Quotas

Check and increase these quotas in your target region:

| Resource | Recommended |
|---|---|
| Total Regional vCPUs | ≥ 96 |
| Standard DSv5 Family vCPUs | ≥ 64 (for CNV Dsv5 workers) |
| Public IP Addresses | ≥ 10 |
| Load Balancers | ≥ 5 |

```bash
# Check vCPU usage
az vm list-usage --location "${AZURE_REGION}" \
  --query "[?name.value=='cores'].{Limit:limit, Current:currentValue}"
```

## Network Prerequisites

- Resource group for DNS zone (may differ from cluster RG).
- **Azure DNS zone** for the base domain must exist.
- If using existing VNet: subnets for control plane and workers with ≥ /27 each.
- Public Load Balancer (Standard SKU) created by installer.

```bash
# Verify DNS zone
az network dns zone show \
  --resource-group "${AZURE_DNS_RG}" \
  --name "${BASE_DOMAIN}"
```

## Pre-install Checks

```bash
# Verify authentication
az account show

# Check subscription
az account list --query "[?isDefault].id" -o tsv

# Confirm DNS zone
az network dns zone list \
  --query "[?name=='${BASE_DOMAIN}'].name" -o tsv
```

## CNV on Azure — Additional Requirements

- Use **Dsv5**, **Esv5**, **Dsv3**, or **Esv3** VM SKUs for workers — these
  support nested virtualisation automatically.
- Verify after deploy:

```bash
oc debug node/<worker-node> -- grep -m1 vmx /proc/cpuinfo
```

- For RWX storage (live migration): deploy ODF, or use Azure Files with
  `rwx` storage class.

```bash
# Check available SKUs that support nested virt in region
az vm list-skus --location "${AZURE_REGION}" \
  --resource-type virtualMachines \
  --query "[?contains(name,'s_v5')].name"
```
