# Architecture Overview

## Repository Purpose

`ocpvirt-gitcli` provides a **GitHub Copilot CLI–driven deployment assistant**
for Red Hat OpenShift Container Platform (OCP) and OpenShift Virtualization
(CNV / OCP-V). A user can run natural-language commands via `gh copilot` and
be guided interactively through the full deployment lifecycle.

---

## Component Diagram

```
┌──────────────────────────────────────────────────────┐
│                  User / Operator                     │
│          gh copilot suggest / copilot chat           │
└───────────────────────┬──────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────┐
│              GitHub Copilot CLI / IDE                │
│  Reads: .github/copilot-instructions.md              │
│  Loads: .copilot/config.yml (skills + prompts)       │
└──────┬───────────────────────────────┬───────────────┘
       │                               │
       ▼                               ▼
 Skills (.copilot/skills/)      Prompts (.copilot/prompts/)
 ┌──────────────────────┐      ┌───────────────────────┐
 │ deploy-openshift     │      │ intake-questionnaire  │
 │ deploy-cnv           │      │ prereq-check          │
 │ verify-prerequisites │      │ cnv-post-install      │
 │ size-cluster         │      │ troubleshoot          │
 │ generate-config      │      └───────────────────────┘
 │ platform-aws/azure/  │
 │ gcp/vsphere/bm/kvm   │
 └──────────┬───────────┘
            │
            ▼
┌──────────────────────────────────────────────────────┐
│                    Scripts                           │
│  scripts/deploy.sh      ← top-level dispatcher      │
│  scripts/preflight.sh   ← prerequisite checks       │
│  scripts/render.sh      ← envsubst template render  │
│  scripts/install-cnv.sh ← HCO install + wait        │
│  scripts/platforms/     ← per-platform deploy logic │
│  scripts/lib/           ← common helpers             │
└──────────┬───────────────────────────────────────────┘
            │
            ▼
┌──────────────────────────────────────────────────────┐
│                   Templates                          │
│  templates/install-config/  ← install-config.yaml   │
│  templates/agent/           ← agent-config.yaml     │
│  templates/cnv/             ← HCO manifests         │
│  templates/storage/         ← ODF/LSO/hostpath      │
│  templates/networking/      ← NMState/MetalLB/NAD   │
└──────────┬───────────────────────────────────────────┘
            │   (rendered into build/<cluster-name>/)
            ▼
┌──────────────────────────────────────────────────────┐
│          OpenShift Installer / CLI                   │
│  openshift-install create cluster                   │
│  openshift-install agent create image               │
│  oc apply / oc patch                                │
└──────────────────────────────────────────────────────┘
```

---

## Supported Deployment Paths

| Platform | Method | CNV Support |
|---|---|---|
| AWS | IPI (installer-provisioned) | ✅ (metal instances required) |
| Azure | IPI | ✅ (Dsv5/Esv5 instances) |
| GCP | IPI | ✅ (nested virt required) |
| vSphere | IPI | ✅ (CPU passthrough in vSphere) |
| Bare-metal | Agent-based Installer | ✅ (native CPU flags) |
| KVM/libvirt | Agent-based Installer (UPI) | ✅ (lab/dev only, nested virt) |

---

## Secret Handling

```
.secrets/                    ← gitignored directory
├── pull-secret.json         ← Red Hat pull secret
├── azure-credentials.json   ← Azure SP credentials
├── gcp-sa-key.json          ← GCP service account key
├── vsphere-credentials.env  ← vCenter username/password
└── bmc-<hostname>.txt       ← BMC passwords for bare-metal
```

Scripts read secrets from these files at runtime using file paths stored in
`cluster.vars.yaml`. Secrets are **never** stored in `cluster.vars.yaml` or
committed to source control.

---

## CI Workflow

```
.github/workflows/
├── lint.yml                 ← yamllint + shellcheck + markdownlint
└── validate-templates.yml  ← render examples + yamllint output
```

Both workflows run on every push and pull request.
