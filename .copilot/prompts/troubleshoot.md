# Troubleshooting Prompt

Use this prompt when an OpenShift install or CNV configuration step has failed.
Work through each section methodically.

## 1. Install-time failures

```bash
# View openshift-install logs
cat build/<cluster-name>/.openshift_install.log | tail -100

# Check bootstrap machine logs (SSH into bootstrap node)
ssh -i <ssh-key> core@<bootstrap-ip> \
  "journalctl -u release-image.service --no-pager | tail -50"

# Wait for bootstrap to complete manually
openshift-install wait-for bootstrap-complete \
  --dir build/<cluster-name> --log-level debug
```

## 2. Cluster Operators not available

```bash
# List degraded/unavailable operators
oc get clusteroperators | grep -v "True.*False.*False"

# Get events for a specific operator
oc describe clusteroperator <name>

# Check operator pod logs
oc logs -n openshift-<operator> -l app=<operator> --tail=100
```

## 3. Nodes not joining

```bash
# Check pending CSRs
oc get csr | grep Pending
# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve

# Check node status
oc get nodes -o wide

# SSH into a node and check kubelet
ssh core@<node-ip> "sudo journalctl -u kubelet --no-pager | tail -50"
```

## 4. CNV / HCO failures

```bash
# Check HCO conditions
oc get hco -n openshift-cnv kubevirt-hyperconverged -o yaml | \
  grep -A 20 conditions

# Check all CNV pods
oc get pods -n openshift-cnv --field-selector=status.phase!=Running

# Get HCO operator logs
oc logs -n openshift-cnv \
  $(oc get pod -n openshift-cnv -l name=hyperconverged-cluster-operator \
    -o jsonpath='{.items[0].metadata.name}') --tail=100
```

## 5. VM not starting

```bash
# Check VM events
oc describe vm/<vm-name> -n <namespace>

# Check VMI (VirtualMachineInstance) status
oc get vmi -n <namespace>
oc describe vmi/<vm-name> -n <namespace>

# Check virt-launcher pod
oc logs $(oc get pod -l kubevirt.io/vm=<vm-name> \
  -o jsonpath='{.items[0].metadata.name}') -c compute --tail=100
```

## 6. Networking issues

```bash
# Check OVN pods
oc get pods -n openshift-ovn-kubernetes

# Verify NetworkAttachmentDefinitions
oc get net-attach-def -A

# Check NMState node network state
oc get nnce  # NodeNetworkConfigurationEnactment
oc describe nnce/<node-name>
```

## 7. Storage issues

```bash
# Check ODF cluster status
oc get storagecluster -n openshift-storage

# Check PVC status
oc get pvc -A | grep -v Bound

# Check Ceph cluster health
oc exec -n openshift-storage \
  $(oc get pod -n openshift-storage -l app=rook-ceph-tools \
    -o jsonpath='{.items[0].metadata.name}') -- ceph status
```

## 8. Collecting must-gather for Red Hat Support

```bash
# Standard must-gather
oc adm must-gather --dest-dir=/tmp/must-gather

# CNV-specific must-gather
oc adm must-gather \
  --image=registry.redhat.io/container-native-virtualization/cnv-must-gather-rhel9 \
  --dest-dir=/tmp/cnv-must-gather
```

Reference: https://access.redhat.com/solutions/4387261
