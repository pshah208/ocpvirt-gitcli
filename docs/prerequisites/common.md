# Common Prerequisites

These prerequisites apply to **all** target platforms before running
`openshift-install` or the Agent-based Installer.

Reference: https://docs.openshift.com/container-platform/latest/installing/overview/

---

## Required Tools

| Tool | Minimum Version | Install |
|---|---|---|
| `openshift-install` | Match target OCP version | https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ |
| `oc` CLI | Match target OCP version | https://mirror.openshift.com/pub/openshift-v4/clients/ocp/ |
| `jq` | 1.6+ | `apt install jq` / `brew install jq` |
| `yq` | 4.x | https://github.com/mikefarah/yq |
| `curl` | Any | Standard |
| `envsubst` | Any | `apt install gettext-base` / `brew install gettext` |
| `ssh-keygen` | Any | Standard |

## Internet Connectivity

The following hosts must be reachable from the cluster nodes (unless mirroring):

- `quay.io` — container images
- `registry.redhat.io` — Red Hat registry
- `mirror.openshift.com` — installer binaries and images
- `api.openshift.com` — Insights Operator
- `access.redhat.com` — subscription management

Check connectivity:

```bash
curl -sSf https://quay.io/v2/ > /dev/null && echo "quay.io OK"
curl -sSf https://registry.redhat.io/v2/ > /dev/null && echo "registry.redhat.io OK"
curl -sSf https://mirror.openshift.com > /dev/null && echo "mirror.openshift.com OK"
```

## Pull Secret

Download your pull secret from:
https://console.redhat.com/openshift/install

Save it to `.secrets/pull-secret.json` (gitignored):

```bash
mkdir -p .secrets
# Paste or copy pull secret JSON:
# Do NOT commit this file
cat > .secrets/pull-secret.json << 'EOF'
<paste pull secret here>
EOF
chmod 600 .secrets/pull-secret.json

# Validate
jq . .secrets/pull-secret.json > /dev/null && echo "Pull secret valid JSON"
```

## SSH Key

```bash
# Generate if needed
ssh-keygen -t ed25519 -C "ocp-install" -f ~/.ssh/ocp_ed25519

# Reference the public key in cluster.vars.yaml
# ssh_key_path: ~/.ssh/ocp_ed25519.pub
```

## DNS Requirements

Before installing, create the following DNS records:

| Record | Type | Value |
|---|---|---|
| `api.<cluster>.<domain>` | A | API load balancer IP |
| `api-int.<cluster>.<domain>` | A | API internal LB IP (same as API for IPI) |
| `*.apps.<cluster>.<domain>` | A / CNAME | Ingress VIP / LB |

Validate:

```bash
nslookup api.${CLUSTER_NAME}.${BASE_DOMAIN}
nslookup test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}
```

## NTP Synchronisation

All cluster nodes must have accurate time. Verify NTP is configured on the
host where the installer runs (nodes inherit NTP from RHCOS defaults or
MachineConfig).

## Firewall / Security Group Rules

Minimum ports that must be open between nodes:

| Port | Protocol | Purpose |
|---|---|---|
| 6443 | TCP | Kubernetes API server |
| 22623 | TCP | Machine Config Server (bootstrap) |
| 2379–2380 | TCP | etcd peer |
| 9000–9999 | TCP | Host services |
| 10250 | TCP | kubelet |
| 4789 | UDP | VXLAN (OVN-K) |
| 6081 | UDP | Geneve (OVN-K) |
| 500, 4500 | UDP | IPsec (if enabled) |

See full list: https://docs.openshift.com/container-platform/latest/installing/installing_network_requirements/

## Proxy (Optional)

If your environment requires a proxy, set these in `cluster.vars.yaml`:

```yaml
proxy:
  http_proxy: "http://proxy.example.com:3128"
  https_proxy: "http://proxy.example.com:3128"
  no_proxy: "localhost,127.0.0.1,.example.com,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
```

The templates include `proxy:` stanzas that `scripts/render.sh` will populate.
