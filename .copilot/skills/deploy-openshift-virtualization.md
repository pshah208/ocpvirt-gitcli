# Skill: deploy-openshift-virtualization

Installs and configures **OpenShift Virtualization (CNV)** on an existing,
healthy OpenShift 4.x cluster.

## Prerequisites

- OpenShift cluster is up, `oc whoami` returns a cluster-admin user.
- `KUBECONFIG` is exported (e.g. `build/<cluster-name>/auth/kubeconfig`).
- Worker nodes expose CPU virtualisation extensions (`vmx` or `svm`).
- For cloud deployments: nested virtualisation is enabled on worker instances.
- A storage class that supports **RWX** access mode is available (ODF recommended).
- Scripts in `scripts/` are executable.

Verify: `bash scripts/preflight.sh cnv`

---

## Step 1 — Install the CNV Operator

```bash
bash scripts/install-cnv.sh
```

This applies the manifests in `templates/cnv/` in order:

| Manifest | Purpose |
|---|---|
| `01-namespace.yaml` | Creates `openshift-cnv` namespace |
| `02-operatorgroup.yaml` | Scopes the operator to the namespace |
| `03-subscription.yaml` | Subscribes to `kubevirt-hyperconverged` channel |
| `04-hyperconverged.yaml` | Creates the `HyperConverged` CR to deploy all CNV components |

The script waits up to 15 minutes for HCO to reach `Available=True`.

## Step 2 — Verify HCO is healthy

```bash
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions}' | jq .
```

Expected: `"Available": "True"`, `"Progressing": "False"`, `"Degraded": "False"`.

```bash
# Confirm all CNV pods are Running
oc get pods -n openshift-cnv
```

## Step 3 — Configure storage

### ODF (recommended for live migration)

```bash
oc apply -f templates/storage/odf-subscription.yaml
# Wait for ODF operator, then create StorageCluster CR
oc wait csv -n openshift-storage \
  -l operators.coreos.com/odf-operator.openshift-storage \
  --for=condition=Succeeded --timeout=15m
```

Set CephFS as default RWX class:

```bash
oc annotate storageclass ocs-storagecluster-cephfs \
  storageclass.kubernetes.io/is-default-class=true
```

### Local Storage + hostpath (lab / bare-metal without ODF)

```bash
oc apply -f templates/storage/lso-subscription.yaml
oc apply -f templates/storage/hostpath-provisioner.yaml
```

## Step 4 — Configure live-migration policy

```bash
oc patch hco kubevirt-hyperconverged -n openshift-cnv \
  --type=merge -p '{
    "spec": {
      "liveMigrationConfig": {
        "parallelMigrationsPerCluster": 5,
        "parallelOutboundMigrationsPerNode": 2,
        "completionTimeoutPerGiB": 800,
        "progressTimeout": 150
      }
    }
  }'
```

## Step 5 — Enable feature gates (bare-metal / CPU passthrough)

For bare-metal nodes where you want host CPU features visible to VMs:

```bash
oc patch hco kubevirt-hyperconverged -n openshift-cnv \
  --type=merge -p '{
    "spec": {
      "featureGates": {
        "withHostPassthroughCPU": true,
        "deployKubeSecondaryDNS": false
      }
    }
  }'
```

## Step 6 — Install NMState Operator (optional but recommended)

```bash
oc apply -f templates/networking/nmstate-operator.yaml
# Apply example node network configuration policy (linux bridge)
oc apply -f templates/networking/nncp-example.yaml
```

## Step 7 — Install MetalLB (bare-metal / vSphere without cloud LB)

```bash
oc apply -f templates/networking/metallb-operator.yaml
```

## Step 8 — Create a NetworkAttachmentDefinition (bridged networks)

After the NMState policy is applied and the bridge exists on nodes:

```bash
cat <<'EOF' | oc apply -f -
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: br-flat
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/resourceName: bridge.network.kubevirt.io/br-flat
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "name": "br-flat",
      "type": "cnv-bridge",
      "bridge": "br-flat",
      "macspoofchk": true
    }
EOF
```

## Step 9 — Deploy a test VM

```bash
cat <<'EOF' | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: fedora-test
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: fedora-test
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          containerDisk:
            image: quay.io/containerdisks/fedora:latest
EOF

oc wait vm/fedora-test \
  --for=jsonpath='{.status.ready}'=true \
  --timeout=300s -n default
virtctl console fedora-test
```

## Step 10 — Validate live migration

```bash
virtctl migrate fedora-test -n default
oc get vmim -n default -w
```

---

## References

- OpenShift Virtualization docs: https://docs.openshift.com/container-platform/latest/virt/
- HyperConverged Operator: https://github.com/kubevirt/hyperconverged-cluster-operator
- Live migration: https://docs.openshift.com/container-platform/latest/virt/live_migration/
