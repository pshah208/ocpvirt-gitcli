# Skill: platform-gcp

GCP-specific prerequisites, IPI deployment steps, and OpenShift Virtualization
caveats for deploying OCP on Google Cloud Platform.

Reference: https://docs.openshift.com/container-platform/latest/installing/installing_gcp/

---

## Required CLIs

```bash
gcloud --version       # Google Cloud SDK
oc version --client
openshift-install version
```

Install gcloud SDK: https://cloud.google.com/sdk/docs/install

## Authentication Setup

```bash
# User auth (interactive)
gcloud auth login
gcloud auth application-default login

# Service account (CI)
gcloud auth activate-service-account \
  --key-file=.secrets/gcp-sa-key.json
export GOOGLE_APPLICATION_CREDENTIALS=.secrets/gcp-sa-key.json

# Verify
gcloud auth list
gcloud config set project <PROJECT_ID>
```

## Required GCP APIs

Enable the following APIs on your project:

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

## Minimum IAM Roles

The service account used by the installer needs:

- `roles/compute.admin`
- `roles/dns.admin`
- `roles/iam.serviceAccountAdmin`
- `roles/iam.serviceAccountKeyAdmin`
- `roles/storage.admin`
- `roles/resourcemanager.projectIamAdmin` (for Mint mode)

## Networking Prerequisites

- **VPC network and subnetworks**: installer creates by default; or provide
  existing via `platform.gcp.network` and `platform.gcp.controlPlaneSubnet` /
  `platform.gcp.computeSubnet`.
- **DNS zone**: Cloud DNS public managed zone for base domain must exist.
- **Firewall rules** are created by the installer.

## Example install-config snippet

```yaml
platform:
  gcp:
    projectID: ${GCP_PROJECT}
    region: ${GCP_REGION}
    # Uncomment for existing network:
    # network: ${GCP_VPC_NETWORK}
    # controlPlaneSubnet: ${GCP_CP_SUBNET}
    # computeSubnet: ${GCP_WORKER_SUBNET}
```

See full template: `templates/install-config/gcp.install-config.yaml.tmpl`

## OpenShift Virtualization on GCP — Caveats

| Requirement | Detail |
|---|---|
| Nested virtualisation | Must be **explicitly enabled** per instance via a custom machine image or instance template flag. |
| Enable nested virt | Only supported on Intel Haswell or newer (n1, n2, n2d, c2 families). |
| Default machine types | `n2-standard-8` supports nested virt; `e2` series does **not**. |
| Recommended for CNV | `n2-standard-16` (16 vCPU / 64 GiB) with nested virt enabled. |
| Storage for live migration | GCP Persistent Disk is RWO. Deploy ODF for RWX, or use Filestore for NFS-backed RWX. |

### Enabling nested virtualisation on worker MachineSet

After cluster install, patch the MachineSet to add the nested-virt
license and recreate workers:

```bash
# 1. Edit the worker MachineSet
oc edit machineset -n openshift-machine-api <worker-machineset>
# Add under spec.template.spec.providerSpec.value:
#   disks:
#   - autoDelete: true
#     boot: true
#     image: projects/rhcos-cloud/global/images/<rhcos-image>
#     licenses:
#       - https://www.googleapis.com/compute/v1/projects/vm-options/global/licenses/enable-vmx
#     type: pd-ssd

# 2. Scale workers (rolling replace)
oc scale machineset -n openshift-machine-api <worker-machineset> \
  --replicas=0
oc scale machineset -n openshift-machine-api <worker-machineset> \
  --replicas=<desired-count>

# 3. Verify CPU flags
oc debug node/<new-worker> -- grep -m1 vmx /proc/cpuinfo
```

Reference: https://cloud.google.com/compute/docs/instances/enable-nested-virtualization-vm-instances
