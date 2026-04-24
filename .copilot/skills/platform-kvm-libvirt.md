# Skill: platform-kvm-libvirt

KVM/libvirt platform prerequisites and user-provisioned infrastructure (UPI)
deployment steps for development and lab environments.

> **Note:** The libvirt platform was removed from `openshift-install` as an
> officially supported target in OCP 4.x. This skill covers the Agent-based
> Installer approach on KVM-hosted VMs, which is fully supported.

---

## Required CLIs and Tools

```bash
virsh --version      # libvirt CLI
virt-install --version
openshift-install version
oc version --client
```

Host requirements: KVM + libvirt, `qemu-kvm`, `virt-manager` (optional GUI).

## Host Setup

```bash
# Verify KVM acceleration
egrep -c '(vmx|svm)' /proc/cpuinfo   # must be > 0
lsmod | grep kvm

# Install libvirt
sudo dnf install -y qemu-kvm libvirt virt-install

# Enable and start libvirtd
sudo systemctl enable --now libvirtd

# Add your user to the libvirt group
sudo usermod -aG libvirt "$(whoami)"
```

## Network Setup

```bash
# Create a libvirt network for OCP (isolated bridge)
virsh net-define /dev/stdin <<'EOF'
<network>
  <name>ocp</name>
  <bridge name="virbr-ocp" stp="on" delay="0"/>
  <ip address="192.168.130.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.130.100" end="192.168.130.200"/>
    </dhcp>
  </ip>
</network>
EOF
virsh net-start ocp
virsh net-autostart ocp
```

Add DNS entries to the host `/etc/hosts` or a local dnsmasq instance:

```
192.168.130.11 api.ocp4.example.com
192.168.130.11 api-int.ocp4.example.com
192.168.130.12 *.apps.ocp4.example.com
```

## Creating VMs with virt-install

```bash
# Download RHCOS live ISO
ISO_URL="https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-live.x86_64.iso"
curl -L -o /tmp/rhcos-live.iso "${ISO_URL}"

# Create a master VM (repeat for each node)
virt-install \
  --name ocp4-master-0 \
  --vcpus 8 \
  --memory 32768 \
  --disk path=/var/lib/libvirt/images/ocp4-master-0.qcow2,size=120,format=qcow2 \
  --network network=ocp,model=virtio \
  --os-variant rhel9.0 \
  --cdrom /tmp/agent.x86_64.iso \
  --boot hd,cdrom \
  --noautoconsole
```

## Deployment with Agent-based Installer

### 1. Render configs

```bash
VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/install-config/baremetal.install-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/install-config.yaml"

VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/agent/agent-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/agent-config.yaml"
```

### 2. Generate ISO and boot VMs

```bash
openshift-install agent create image --dir "build/${CLUSTER_NAME}"

# Attach ISO to each VM and boot
for vm in master-0 master-1 master-2 worker-0 worker-1 worker-2; do
  virsh change-media "ocp4-${vm}" hda \
    "$(pwd)/build/${CLUSTER_NAME}/agent.x86_64.iso" --update --live || true
  virsh start "ocp4-${vm}"
done
```

### 3. Monitor

```bash
openshift-install agent wait-for install-complete \
  --dir "build/${CLUSTER_NAME}" --log-level debug
```

## OpenShift Virtualization on KVM/libvirt

| Requirement | Detail |
|---|---|
| Nested virtualisation | Required. Enable on KVM host: `modprobe -r kvm_intel && modprobe kvm_intel nested=1` |
| Persistent nested virt | Add `options kvm_intel nested=1` to `/etc/modprobe.d/kvm.conf` |
| CPU passthrough | Use `--cpu host-passthrough` in virt-install, or set `<cpu mode="host-passthrough"/>` in VM XML. |
| Storage | Local qcow2 (RWO) or NFS share (RWX for live migration). |
| CNV use case | Best for lab/dev. Not recommended for production CNV workloads. |

### Enable nested virt on KVM host

```bash
# Intel
echo "options kvm_intel nested=1" | \
  sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel nested=1

# AMD
echo "options kvm_amd nested=1" | \
  sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd nested=1

# Verify
cat /sys/module/kvm_intel/parameters/nested   # should print Y or 1
```
