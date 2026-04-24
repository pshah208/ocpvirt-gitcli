# Skill: verify-prerequisites

Instructs Copilot to run `scripts/preflight.sh <platform>` and interpret the
results before proceeding with any install.

## Usage

```bash
# Replace <platform> with: aws | azure | gcp | vsphere | baremetal | cnv
bash scripts/preflight.sh <platform>
```

The script prints ✅, ❌, or ⚠️ for each check and exits non-zero on any
failure.

---

## Checks Performed

### Common (all platforms)

| Check | Tool / Command |
|---|---|
| `oc` CLI present and correct version | `oc version --client` |
| `openshift-install` present | `openshift-install version` |
| `jq` present | `jq --version` |
| `yq` present | `yq --version` |
| `curl` reachable to `quay.io` | `curl -sSf https://quay.io/v2/` |
| `curl` reachable to `registry.redhat.io` | `curl -sSf https://registry.redhat.io/v2/` |
| `curl` reachable to `mirror.openshift.com` | `curl -sSf https://mirror.openshift.com` |
| Pull secret path exists | `test -f "${PULL_SECRET_PATH}"` |
| Pull secret is valid JSON | `jq . "${PULL_SECRET_PATH}"` |
| SSH public key path exists | `test -f "${SSH_KEY_PATH}"` |
| Base domain is resolvable | `nslookup "${BASE_DOMAIN}"` |

### AWS

| Check | Command |
|---|---|
| `aws` CLI present | `aws --version` |
| Caller identity valid | `aws sts get-caller-identity` |
| Region vCPU quota | `aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A` |
| Elastic IP quota | `aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3` |
| Route53 hosted zone for base domain | `aws route53 list-hosted-zones-by-name --dns-name "${BASE_DOMAIN}"` |

### Azure

| Check | Command |
|---|---|
| `az` CLI present | `az --version` |
| Subscription active | `az account show` |
| vCPU quota in region | `az vm list-usage --location "${AZURE_REGION}"` |
| DNS zone for base domain | `az network dns zone show --name "${BASE_DOMAIN}"` |

### GCP

| Check | Command |
|---|---|
| `gcloud` CLI present | `gcloud --version` |
| Auth configured | `gcloud auth list` |
| Project exists | `gcloud projects describe "${GCP_PROJECT}"` |
| Required APIs enabled | `gcloud services list --enabled --project "${GCP_PROJECT}"` |
| DNS zone for base domain | `gcloud dns managed-zones list` |

Required APIs: `compute`, `dns`, `iam`, `servicemanagement`,
`cloudresourcemanager`, `storage-api`.

### vSphere

| Check | Command |
|---|---|
| `govc` CLI present | `govc version` |
| vCenter reachable | `curl -sSf "https://${VCENTER_FQDN}/rest/com/vmware/cis/session"` |
| vCenter credentials valid | `govc about` |
| Datacenter exists | `govc datacenter.info "${VSPHERE_DATACENTER}"` |
| Cluster exists + DRS enabled | `govc cluster.info "${VSPHERE_CLUSTER}"` |
| Datastore free space ≥ required | `govc datastore.info "${VSPHERE_DATASTORE}"` |
| Portgroup exists | `govc network.info "${VSPHERE_NETWORK}"` |

### Bare-metal (Agent-based)

| Check | Description |
|---|---|
| BMC reachability | `curl` or `ipmitool` ping each BMC address |
| Two VIPs are free | `arping` or `nmap` to confirm API/Ingress VIPs are not in use |
| DNS A records for API/Ingress | `nslookup "api.${CLUSTER_NAME}.${BASE_DOMAIN}"` |
| Rendezvous IP reachable | `ping -c1 "${RENDEZVOUS_IP}"` |

### CNV-specific

| Check | Description |
|---|---|
| CPU virt extensions on workers | `oc debug node/<node> -- grep -m1 vmx /proc/cpuinfo` |
| RWX storage class exists | `oc get sc -o jsonpath='{.items[?(@.metadata.annotations...)].metadata.name}'` |
| Cloud: nested virt enabled | Platform-specific (see platform skills) |
| `virtctl` CLI present | `virtctl version` |

---

## Interpreting Results

- **All ✅** — proceed to `generate-install-config` skill.
- **Any ❌** — stop; fix the listed failures; re-run preflight.
- **Only ⚠️** — review warnings; ask user to confirm before continuing.
