# ocpvirt-gitcli

> A **GitHub Copilot CLI–driven assistant** for deploying **Red Hat OpenShift
> Container Platform (OCP)** and **OpenShift Virtualization (CNV / OCP-V)**
> across on-premises and hyperscaler infrastructures.

[![Lint](https://github.com/pshah208/ocpvirt-gitcli/actions/workflows/lint.yml/badge.svg)](https://github.com/pshah208/ocpvirt-gitcli/actions/workflows/lint.yml)
[![Validate Templates](https://github.com/pshah208/ocpvirt-gitcli/actions/workflows/validate-templates.yml/badge.svg)](https://github.com/pshah208/ocpvirt-gitcli/actions/workflows/validate-templates.yml)

---

## Quickstart

```bash
# Install the gh-copilot extension
gh extension install github/gh-copilot

# Ask Copilot to deploy a cluster (from any directory)
gh copilot suggest "deploy a 3-node OpenShift Virtualization lab on vSphere"

# Or, inside this repo, use a registered skill:
gh copilot suggest "/deploy-openshift"
gh copilot suggest "/deploy-openshift-virtualization"

# Start the interactive intake questionnaire
gh copilot suggest "/intake"

# Run prerequisite checks
bash scripts/preflight.sh aws        # or azure | gcp | vsphere | baremetal | cnv

# Render a template with your vars
VARS_FILE=examples/aws-small.vars.yaml \
  bash scripts/render.sh \
    templates/install-config/aws.install-config.yaml.tmpl \
    /tmp/my-cluster/install-config.yaml

# Full deploy (reads platform from cluster.vars.yaml)
VARS_FILE=cluster.vars.yaml bash scripts/deploy.sh
```

---

## Supported Platforms

| Platform | OCP only | OCP + CNV | Method |
|---|---|---|---|
| **AWS** | ✅ | ✅ (metal instances) | IPI |
| **Azure** | ✅ | ✅ (Dsv5/Esv5) | IPI |
| **GCP** | ✅ | ✅ (nested virt) | IPI |
| **vSphere / vCenter** | ✅ | ✅ (CPU passthrough) | IPI |
| **Bare-metal** | ✅ | ✅ (native CPU flags) | Agent-based |
| **KVM / libvirt** | ✅ | ✅ (lab/dev) | Agent-based (UPI) |

---

## Repository Layout

```
.
├── .github/
│   ├── copilot-instructions.md    # Copilot repo-wide instructions
│   └── workflows/
│       ├── lint.yml               # yamllint + shellcheck + markdownlint
│       └── validate-templates.yml # render + validate example configs
├── .copilot/
│   ├── config.yml                 # Skills and prompts registry
│   ├── skills/                    # Copilot skill files (one per capability)
│   └── prompts/                   # Interactive prompt files
├── docs/
│   ├── architecture.md
│   ├── sizing-guide.md
│   ├── openshift-virtualization.md
│   └── prerequisites/             # Per-platform prerequisite guides
├── templates/
│   ├── install-config/            # install-config.yaml templates
│   ├── agent/                     # agent-config.yaml templates
│   ├── cnv/                       # HyperConverged Operator manifests
│   ├── storage/                   # ODF / LSO / hostpath manifests
│   └── networking/                # NMState / MetalLB / NNCP manifests
├── scripts/
│   ├── deploy.sh                  # Top-level dispatcher
│   ├── preflight.sh               # Prerequisite checker
│   ├── render.sh                  # Template renderer (envsubst)
│   ├── install-cnv.sh             # CNV install + HCO wait
│   ├── platforms/                 # Per-platform deploy scripts
│   └── lib/                       # Shared helpers
└── examples/                      # Ready-to-use vars files
```

---

## Copilot Skills

| Skill | Description |
|---|---|
| [`deploy-openshift`](.copilot/skills/deploy-openshift.md) | End-to-end OCP deployment |
| [`deploy-openshift-virtualization`](.copilot/skills/deploy-openshift-virtualization.md) | Install CNV on existing cluster |
| [`verify-prerequisites`](.copilot/skills/verify-prerequisites.md) | Check platform prerequisites |
| [`size-cluster`](.copilot/skills/size-cluster.md) | Recommend node counts and sizes |
| [`generate-install-config`](.copilot/skills/generate-install-config.md) | Render install-config.yaml |
| [`platform-aws`](.copilot/skills/platform-aws.md) | AWS specifics |
| [`platform-azure`](.copilot/skills/platform-azure.md) | Azure specifics |
| [`platform-gcp`](.copilot/skills/platform-gcp.md) | GCP specifics |
| [`platform-vsphere`](.copilot/skills/platform-vsphere.md) | vSphere specifics |
| [`platform-baremetal-agent`](.copilot/skills/platform-baremetal-agent.md) | Bare-metal Agent-based specifics |
| [`platform-kvm-libvirt`](.copilot/skills/platform-kvm-libvirt.md) | KVM/libvirt specifics |

## Copilot Prompts

| Prompt | Description |
|---|---|
| [`intake`](.copilot/prompts/intake-questionnaire.md) | Interactive cluster questionnaire |
| [`prereq-check`](.copilot/prompts/prereq-check.md) | Run and interpret preflight checks |
| [`cnv-post-install`](.copilot/prompts/cnv-post-install.md) | Post-install CNV configuration |
| [`troubleshoot`](.copilot/prompts/troubleshoot.md) | Diagnose install and CNV failures |

---

## Documentation

- [Architecture Overview](docs/architecture.md)
- [Sizing Guide](docs/sizing-guide.md)
- [OpenShift Virtualization Guide](docs/openshift-virtualization.md)
- Prerequisites: [Common](docs/prerequisites/common.md) · [AWS](docs/prerequisites/aws.md) · [Azure](docs/prerequisites/azure.md) · [GCP](docs/prerequisites/gcp.md) · [vSphere](docs/prerequisites/vsphere.md) · [Bare-metal](docs/prerequisites/baremetal.md)

---

## Example Vars Files

| File | Platform | Topology | CNV |
|---|---|---|---|
| [`aws-small.vars.yaml`](examples/aws-small.vars.yaml) | AWS | 3+3 standard | No |
| [`azure-medium.vars.yaml`](examples/azure-medium.vars.yaml) | Azure | 3+6 standard | No |
| [`vsphere-cnv-lab.vars.yaml`](examples/vsphere-cnv-lab.vars.yaml) | vSphere | 3-node compact | ✅ Yes |
| [`baremetal-3node-compact.vars.yaml`](examples/baremetal-3node-compact.vars.yaml) | Bare-metal | 3-node compact | ✅ Yes |

---

## Security

- **Never** commit pull secrets, cloud credentials, SSH private keys, or BMC
  passwords.
- Store all secrets in `.secrets/` — this directory is gitignored.
- Reference secret file paths in `cluster.vars.yaml`; the render script loads
  them at runtime.
- See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for
  the full security policy enforced on Copilot's behaviour.

---

## License

[Apache 2.0](LICENSE)