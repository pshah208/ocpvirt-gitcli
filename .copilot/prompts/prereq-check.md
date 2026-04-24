# Prerequisite Check Prompt

Run the platform preflight script and report the results clearly.

## Steps

1. Determine the target platform from `cluster.vars.yaml` (key: `platform`).
2. Run:

   ```bash
   bash scripts/preflight.sh <platform>
   ```

3. Parse the output:
   - Lines starting with ✅ are passing checks — show them in a collapsible
     "All passing checks" section.
   - Lines starting with ❌ are failures — list them prominently with a
     suggested remediation for each.
   - Lines starting with ⚠️ are warnings — note them and ask the user whether
     to proceed.

4. If **any** ❌ failures are present, **stop** and ask the user to remediate
   before continuing.

5. If only ⚠️ warnings (no failures), ask the user to confirm they want to
   proceed anyway.

6. On full pass, say:
   _"All prerequisites passed. Ready to render install-config.yaml. Shall I
   proceed?"_

## Common Remediations

| Check | Typical Fix |
|---|---|
| `oc` not found | `curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz \| tar xz -C /usr/local/bin` |
| `openshift-install` not found | Download from `mirror.openshift.com/pub/openshift-v4/clients/ocp/` |
| Pull secret invalid JSON | Re-download from https://console.redhat.com/openshift/install |
| DNS not resolving `api.<cluster>.<domain>` | Create A record pointing to API LB IP |
| AWS vCPU quota insufficient | Request increase in AWS Service Quotas console |
| Azure subscription quota | `az vm list-usage --location <region>` then request increase |
| GCP API not enabled | `gcloud services enable <api>.googleapis.com --project <proj>` |
| vCenter credentials rejected | Verify service account has required privileges (see `docs/prerequisites/vsphere.md`) |
| CNV: no `vmx`/`svm` CPU flags | Enable CPU passthrough / host-model in hypervisor settings |
| CNV: no RWX storage class | Install ODF or configure NFS with RWX provisioner |
