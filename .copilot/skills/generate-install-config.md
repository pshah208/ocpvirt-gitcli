# Skill: generate-install-config

Renders the correct `install-config.yaml` (and optionally `agent-config.yaml`)
from the templates in `templates/install-config/` using values from
`cluster.vars.yaml`.

## Prerequisites

- `cluster.vars.yaml` is populated (run `intake` prompt if needed).
- `scripts/preflight.sh <platform>` has passed.
- `envsubst` is available (`apt install gettext-base` or `brew install gettext`).

---

## Step 1 — Source variables

```bash
# Load cluster.vars.yaml into environment
source <(python3 - <<'PY'
import yaml, sys
with open('cluster.vars.yaml') as f:
    d = yaml.safe_load(f)
def emit(d, prefix=''):
    for k, v in d.items():
        key = (prefix + '_' + k).upper().lstrip('_')
        if isinstance(v, dict):
            emit(v, key)
        elif v is not None:
            print(f"export {key}='{v}'")
emit(d)
PY
)

# Load pull secret from .secrets/ (never from vars file)
export PULL_SECRET="$(cat "${PULL_SECRET_PATH}")"
export SSH_KEY="$(cat "${SSH_KEY_PATH}")"
```

## Step 2 — Render the template

```bash
mkdir -p "build/${CLUSTER_NAME}"

VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    "templates/install-config/${PLATFORM}.install-config.yaml.tmpl" \
    "build/${CLUSTER_NAME}/install-config.yaml"

echo "Rendered: build/${CLUSTER_NAME}/install-config.yaml"
```

## Step 3 — Validate YAML syntax

```bash
python3 -c "import yaml; yaml.safe_load(open('build/${CLUSTER_NAME}/install-config.yaml'))"
# or
yamllint "build/${CLUSTER_NAME}/install-config.yaml"
```

## Step 4 — (Agent-based only) Render agent-config.yaml

For `platform: baremetal-agent` or `platform: kvm-libvirt`:

```bash
VARS_FILE=cluster.vars.yaml \
  bash scripts/render.sh \
    templates/agent/agent-config.yaml.tmpl \
    "build/${CLUSTER_NAME}/agent-config.yaml"
```

## Step 5 — Dry-run manifest generation

```bash
# This consumes install-config.yaml — keep a backup first
cp "build/${CLUSTER_NAME}/install-config.yaml" \
   "build/${CLUSTER_NAME}/install-config.yaml.bak"

openshift-install create manifests \
  --dir "build/${CLUSTER_NAME}"
```

Review generated manifests in `build/${CLUSTER_NAME}/manifests/` and
`build/${CLUSTER_NAME}/openshift/` before proceeding to cluster creation.

---

## Template Variable Reference

All templates use `${VAR}` syntax resolved by `envsubst`. Key variables:

| Variable | Source | Description |
|---|---|---|
| `CLUSTER_NAME` | `cluster.vars.yaml` | Short cluster name |
| `BASE_DOMAIN` | `cluster.vars.yaml` | DNS base domain |
| `OCP_VERSION` | `cluster.vars.yaml` | OpenShift version string |
| `PULL_SECRET` | `.secrets/pull-secret.json` | Red Hat pull secret (never in vars) |
| `SSH_KEY` | `~/.ssh/id_rsa.pub` | SSH public key (never in vars) |
| `MACHINE_CIDR` | `cluster.vars.yaml` | Host/node network CIDR |
| `CLUSTER_CIDR` | `cluster.vars.yaml` | Pod network CIDR |
| `SERVICE_CIDR` | `cluster.vars.yaml` | Service network CIDR |
| `NETWORK_TYPE` | `cluster.vars.yaml` | `OVNKubernetes` or `OpenShiftSDN` |

Platform-specific variables are documented in each template file.
