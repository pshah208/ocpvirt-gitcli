# CNV Post-Install Configuration Prompt

Use this prompt after `scripts/install-cnv.sh` has completed successfully
and the HyperConverged CR shows `Available=True`.

## Validation Steps

```bash
# 1. Confirm HCO is Available
oc get hco -n openshift-cnv kubevirt-hyperconverged \
  -o jsonpath='{.status.conditions}' | jq .

# 2. Check all CNV pods are Running
oc get pods -n openshift-cnv

# 3. Verify default storage class is set
oc get storageclass

# 4. Check live-migration configuration
oc get kubevirt -n openshift-cnv -o yaml | grep -A5 liveMigration
```

## Post-Install Configuration Tasks

Ask the user which of the following optional steps to perform:

### A. Configure default storage class for VM disks

```bash
# Tag ODF CephFS as default for RWX (live migration)
oc annotate storageclass ocs-storagecluster-cephfs \
  storageclass.kubernetes.io/is-default-class=true
```

### B. Create a linux-bridge NetworkAttachmentDefinition

```bash
oc apply -f templates/networking/nncp-example.yaml
```

### C. Set CPU Manager policy on CNV worker nodes

```bash
oc apply -f - <<'EOF'
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: cnv-kubeletconfig
spec:
  machineConfigPoolSelector:
    matchLabels:
      machineconfiguration.openshift.io/role: worker-cnv
  kubeletConfig:
    cpuManagerPolicy: static
    cpuManagerReconcilePeriod: 5s
EOF
```

### D. Deploy a test Fedora VM

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
# Wait for VM to reach Running state
oc wait vm/fedora-test --for=condition=Ready --timeout=300s
```

### E. Validate live migration

```bash
# Trigger a live migration
virtctl migrate fedora-test
# Monitor
oc get vmim -w
```

## Success Criteria

- `oc get hco -n openshift-cnv kubevirt-hyperconverged` shows `Available=True`
- Test VM reaches `Running` phase
- Live migration completes without downtime

Once all steps are validated, say:
_"OpenShift Virtualization is fully operational. Your cluster is ready for VM
workloads."_
