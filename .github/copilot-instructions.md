# GitHub Copilot Instructions — ocpvirt-gitcli

## Purpose

This repository is a **turnkey GitHub Copilot CLI assistant** for deploying
**Red Hat OpenShift Container Platform (OCP)** and
**OpenShift Virtualization (CNV / OCP-V)** on:

- On-premises VMs (vSphere/vCenter, KVM/libvirt, Nutanix, RHV)
- On-premises bare-metal (Assisted Installer or Agent-based installer)
- Public clouds: **AWS**, **Azure**, **GCP** (installer-provisioned IPI)

All workflows are driven by `scripts/`, templated configs live in `templates/`,
and reusable Copilot skills live in `.copilot/skills/`.

---

## Mandatory Copilot Behaviour

1. **Always run `scripts/preflight.sh <platform>` before suggesting or
   generating any installer config.** Do not skip preflight even if the user
   seems impatient.

2. **Always ask the user for the target platform and desired cluster sizing
   before generating any config files.** Use `.copilot/prompts/intake-questionnaire.md`
   as the structured intake guide.

3. **Never hardcode pull secrets, cloud credentials, SSH private keys, BMC
   passwords, or any other secrets.** Reference the path
   `./.secrets/pull-secret.json` (gitignored) and tell the user to place
   secrets there.

4. **Prefer templates in `templates/` over ad-hoc YAML.** Render them via
   `scripts/render.sh` rather than emitting raw YAML inline.

5. **Use `oc` (not `kubectl`) for all OpenShift-specific resources** such as
   Projects, Routes, OperatorGroups, Subscriptions, MachineConfigs, etc.

6. **Always run `openshift-install create manifests --dir <build-dir>` as a
   dry-run validation step before running `create cluster`.**

7. **Never print secrets to the terminal.** If you need to reference a secret,
   show only the file path or a redacted placeholder.

8. **Always recommend `--dry-run`/`--plan`** for Terraform or Ansible before
   apply/run.

---

## Supported Platforms & Canonical Skill Files

| Platform | Skill file |
|---|---|
| AWS | `.copilot/skills/platform-aws.md` |
| Azure | `.copilot/skills/platform-azure.md` |
| GCP | `.copilot/skills/platform-gcp.md` |
| vSphere / vCenter | `.copilot/skills/platform-vsphere.md` |
| Bare-metal (Agent-based) | `.copilot/skills/platform-baremetal-agent.md` |
| KVM / libvirt | `.copilot/skills/platform-kvm-libvirt.md` |

Top-level orchestration skills:

| Goal | Skill file |
|---|---|
| Full OCP deploy | `.copilot/skills/deploy-openshift.md` |
| OpenShift Virtualization install | `.copilot/skills/deploy-openshift-virtualization.md` |
| Prerequisite checks | `.copilot/skills/verify-prerequisites.md` |
| Cluster sizing | `.copilot/skills/size-cluster.md` |
| Generate install-config | `.copilot/skills/generate-install-config.md` |

---

## Key Scripts

| Script | Purpose |
|---|---|
| `scripts/deploy.sh` | Top-level deploy dispatcher |
| `scripts/preflight.sh` | Runs all prerequisite checks for a platform |
| `scripts/render.sh` | Renders `envsubst` templates into `build/` |
| `scripts/install-cnv.sh` | Applies CNV manifests and waits for HCO ready |
| `scripts/platforms/<plat>.sh` | Platform-specific deploy steps |
| `scripts/lib/common.sh` | Shared helpers: logging, `require_cmd`, error traps |
| `scripts/lib/prompts.sh` | Interactive `read -p` helpers for intake Q&A |

---

## Template Format

All templates use `${VAR}` placeholders resolved by `envsubst` (GNU gettext).
Call `scripts/render.sh` to resolve them; never export secrets as shell
variables — load them from files inside `.secrets/`.

## References

- OpenShift Install docs: https://docs.openshift.com/container-platform/latest/installing/
- OpenShift Virtualization docs: https://docs.openshift.com/container-platform/latest/virt/
- Agent-based Installer: https://docs.openshift.com/container-platform/latest/installing/installing_with_agent_based_installer/
