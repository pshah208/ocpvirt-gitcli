# GCP Prerequisites

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_gcp/

---

## GCP Project Requirements

- A GCP project with billing enabled.
- A service account with sufficient IAM roles (see below).
- A **Cloud DNS public managed zone** for the base domain.

## Service Account Setup

```bash
# Create service account
gcloud iam service-accounts create ocp-install \
  --display-name "OpenShift Installer" \
  --project "${GCP_PROJECT}"

SA_EMAIL="ocp-install@${GCP_PROJECT}.iam.gserviceaccount.com"

# Assign required roles
for role in \
  roles/compute.admin \
  roles/dns.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountKeyAdmin \
  roles/storage.admin \
  roles/resourcemanager.projectIamAdmin; do
  gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}"
done

# Create and download key
gcloud iam service-accounts keys create \
  .secrets/gcp-sa-key.json \
  --iam-account="${SA_EMAIL}" \
  --project="${GCP_PROJECT}"

export GOOGLE_APPLICATION_CREDENTIALS=.secrets/gcp-sa-key.json
```

## Required APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  dns.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  servicemanagement.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage-api.googleapis.com \
  storage-component.googleapis.com \
  --project "${GCP_PROJECT}"
```

## Service Quotas

Check and increase these quotas in your target region:

| Resource | Recommended |
|---|---|
| CPUS (per region) | ≥ 96 |
| IN_USE_ADDRESSES | ≥ 10 |
| DISKS_TOTAL_GB | ≥ 2000 |
| FIREWALLS | ≥ 15 |

```bash
gcloud compute project-info describe \
  --project "${GCP_PROJECT}" \
  --format="table(quotas.metric,quotas.limit,quotas.usage)"
```

## Network Prerequisites

- **Cloud DNS** managed zone for base domain.
- If using existing VPC: subnet must have Private Google Access enabled.
- Firewall rules are created by the installer.

```bash
# Verify DNS zone
gcloud dns managed-zones list \
  --project "${GCP_PROJECT}" \
  --filter="dnsName:${BASE_DOMAIN}."
```

## Pre-install Checks

```bash
# Verify auth
gcloud auth list --filter=status:ACTIVE

# Verify project
gcloud projects describe "${GCP_PROJECT}"

# Verify required APIs enabled
gcloud services list --enabled \
  --project "${GCP_PROJECT}" \
  --filter="name:(compute OR dns OR iam OR storage)"
```

## CNV on GCP — Additional Requirements

- Nested virtualisation must be **explicitly enabled** per VM instance.
- Use `n2-standard-16` or larger (Intel Haswell or newer required).
- After install, patch the worker MachineSet to add the nested-virt license.
  See `.copilot/skills/platform-gcp.md` for the procedure.

```bash
# Verify nested virt on existing VMs
gcloud compute instances describe <worker-vm> \
  --zone "${GCP_ZONE}" \
  --format="yaml(advancedMachineFeatures)"
# Expected: enableNestedVirtualization: true
```
