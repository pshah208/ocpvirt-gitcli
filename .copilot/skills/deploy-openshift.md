# Skill: deploy-openshift

Guides Copilot through a complete, end-to-end OpenShift IPI or Agent-based
deployment.

## Prerequisites

Before starting, ensure:

- `cluster.vars.yaml` exists (run the `intake` prompt if not).
- `scripts/preflight.sh <platform>` passes with no ❌ failures.

---

## Step 1 — Load cluster variables

```bash
# Export all vars from cluster.vars.yaml as shell environment variables
# so envsubst can resolve templates.
eval "$(python3 - <<'PY'
import yaml, os, sys
with open('cluster.vars.yaml') as f:
    data = yaml.safe_load(f)
def flatten(d, prefix=''):
    for k, v in d.items():
        key = (prefix + '_' + k).upper().lstrip('_')
        if isinstance(v, dict):
            flatten(v, key)
        else:
            print(f"export {key}='{v}'")
flatten(data)
PY
)"
```

If `cluster.vars.yaml` does not exist, invoke the `intake` prompt first.

## Step 2 — Run prerequisite checks

```bash
bash scripts/preflight.sh "${PLATFORM}"
```

Stop and remediate any ❌ failures before continuing.

## Step 3 — Render install-config.yaml

```bash
VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    "templates/install-config/${PLATFORM}.install-config.yaml.tmpl" \
    "build/${CLUSTER_NAME}/install-config.yaml"
```

Review the rendered file and confirm there are no obvious errors before proceeding.

## Step 4 — Create manifests (dry-run)

```bash
openshift-install create manifests --dir "build/${CLUSTER_NAME}"
```

This validates the install-config schema and generates machine manifests.
Review `build/${CLUSTER_NAME}/manifests/` for any customisations needed
(e.g. MachineConfig, custom CA bundles, mirror registry config).

## Step 5a — Create cluster (IPI: aws / azure / gcp / vsphere)

```bash
openshift-install create cluster \
  --dir "build/${CLUSTER_NAME}" \
  --log-level info
```

Monitor `build/${CLUSTER_NAME}/.openshift_install.log` for progress.
Typical install time: 30–45 minutes.

## Step 5b — Agent-based install (baremetal / kvm-libvirt)

```bash
# 1. Render agent-config.yaml alongside install-config.yaml
VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/agent/agent-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/agent-config.yaml"

# 2. Create the agent ISO
openshift-install agent create image --dir "build/${CLUSTER_NAME}"

# 3. Boot each host from the generated ISO:
#    build/${CLUSTER_NAME}/agent.x86_64.iso
#    (Use BMC virtual media, iDRAC, iLO, or dd to USB)

# 4. Monitor discovery and installation
openshift-install agent wait-for bootstrap-complete \
  --dir "build/${CLUSTER_NAME}" --log-level debug
openshift-install agent wait-for install-complete \
  --dir "build/${CLUSTER_NAME}" --log-level debug
```

## Step 6 — Export KUBECONFIG

```bash
export KUBECONFIG="build/${CLUSTER_NAME}/auth/kubeconfig"
oc whoami   # should return system:admin
oc get nodes
```

## Step 7 — Post-install hardening

```bash
# a. Wait for all cluster operators to be available
oc wait clusteroperators --all \
  --for=condition=Available=True --timeout=30m

# b. Configure a non-kubeadmin identity provider (htpasswd example)
htpasswd -c -B -b /tmp/htpasswd admin <STRONG_PASSWORD>
oc create secret generic htpass-secret \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config
oc apply -f - <<'EOF'
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
    - name: htpasswd_provider
      mappingMethod: claim
      type: HTPasswd
      htpasswd:
        fileData:
          name: htpass-secret
EOF

# c. Grant cluster-admin to the new admin user
oc adm policy add-cluster-role-to-user cluster-admin admin

# d. Remove the kubeadmin secret (after confirming new admin works)
oc delete secret kubeadmin -n kube-system

# e. Configure ingress default certificate (optional)
# oc patch ingresscontroller default -n openshift-ingress-operator \
#   --type=merge -p '{"spec":{"defaultCertificate":{"name":"<secret-name>"}}}'
```

## Step 8 — Optional: install OpenShift Virtualization

If `goal == ocp+cnv`, run:

```bash
bash scripts/install-cnv.sh
```

Or invoke the `deploy-openshift-virtualization` skill.

---

## References

- Installing OCP on AWS: https://docs.openshift.com/container-platform/latest/installing/installing_aws/
- Agent-based Installer: https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/
