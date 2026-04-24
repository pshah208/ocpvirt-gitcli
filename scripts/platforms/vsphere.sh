#!/usr/bin/env bash
# scripts/platforms/vsphere.sh — vSphere prerequisite checks and deploy steps.
# Sourced by scripts/preflight.sh and scripts/deploy.sh.

set -euo pipefail

SCRIPT_DIR_PLATFORMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR_PLATFORMS}/../lib/common.sh"

# ── Prerequisite checks ───────────────────────────────────────────────────────
run_vsphere_checks() {
  local check_failures=0

  # govc CLI (VMware govmomi)
  if ! check_cmd govc "VMware govmomi CLI (https://github.com/vmware/govmomi/tree/main/govc)"; then
    log_warn "govc not installed — vSphere-specific checks will be skipped"
    return 0
  fi

  # Required env vars
  VCENTER_FQDN="${VCENTER_FQDN:-}"
  VCENTER_USERNAME="${VCENTER_USERNAME:-}"
  VCENTER_PASSWORD="${VCENTER_PASSWORD:-}"

  if [[ -z "${VCENTER_FQDN}" || -z "${VCENTER_USERNAME}" || -z "${VCENTER_PASSWORD}" ]]; then
    log_warn "VCENTER_FQDN, VCENTER_USERNAME, or VCENTER_PASSWORD not set — skipping vCenter checks"
    return 0
  fi

  export GOVC_URL="https://${VCENTER_FQDN}/sdk"
  export GOVC_USERNAME="${VCENTER_USERNAME}"
  export GOVC_PASSWORD="${VCENTER_PASSWORD}"
  export GOVC_INSECURE="${GOVC_INSECURE:-false}"

  # vCenter reachability
  if curl -sSf --max-time 10 \
      "https://${VCENTER_FQDN}/rest/com/vmware/cis/session" \
      -k &>/dev/null 2>&1; then
    log_ok "vCenter reachable: ${VCENTER_FQDN}"
  else
    log_error "Cannot reach vCenter at https://${VCENTER_FQDN}"
    (( check_failures++ )) || true
    return "${check_failures}"
  fi

  # govc credentials
  if govc about &>/dev/null 2>&1; then
    log_ok "vCenter credentials valid"
  else
    log_error "vCenter credentials invalid for user ${VCENTER_USERNAME}"
    (( check_failures++ )) || true
    return "${check_failures}"
  fi

  # Datacenter
  VSPHERE_DATACENTER="${VSPHERE_DATACENTER:-}"
  if [[ -n "${VSPHERE_DATACENTER}" ]]; then
    if govc datacenter.info "${VSPHERE_DATACENTER}" &>/dev/null 2>&1; then
      log_ok "vSphere datacenter found: ${VSPHERE_DATACENTER}"
    else
      log_error "vSphere datacenter not found: ${VSPHERE_DATACENTER}"
      (( check_failures++ )) || true
    fi
  fi

  # Cluster
  VSPHERE_CLUSTER="${VSPHERE_CLUSTER:-}"
  if [[ -n "${VSPHERE_CLUSTER}" ]]; then
    if govc cluster.info "${VSPHERE_CLUSTER}" &>/dev/null 2>&1; then
      log_ok "vSphere cluster found: ${VSPHERE_CLUSTER}"
    else
      log_error "vSphere cluster not found: ${VSPHERE_CLUSTER}"
      (( check_failures++ )) || true
    fi
  fi

  # Datastore
  VSPHERE_DATASTORE="${VSPHERE_DATASTORE:-}"
  if [[ -n "${VSPHERE_DATASTORE}" ]]; then
    if govc datastore.info "${VSPHERE_DATASTORE}" &>/dev/null 2>&1; then
      local free_gb
      free_gb="$(govc datastore.info "${VSPHERE_DATASTORE}" 2>/dev/null \
        | grep -i 'Free:' | awk '{print $2}' || echo '?')"
      log_ok "vSphere datastore found: ${VSPHERE_DATASTORE} (free: ${free_gb})"
    else
      log_error "vSphere datastore not found: ${VSPHERE_DATASTORE}"
      (( check_failures++ )) || true
    fi
  fi

  # Network / portgroup
  VSPHERE_NETWORK="${VSPHERE_NETWORK:-}"
  if [[ -n "${VSPHERE_NETWORK}" ]]; then
    if govc network.info "${VSPHERE_NETWORK}" &>/dev/null 2>&1; then
      log_ok "vSphere network found: ${VSPHERE_NETWORK}"
    else
      log_error "vSphere network not found: ${VSPHERE_NETWORK}"
      (( check_failures++ )) || true
    fi
  fi

  return "${check_failures}"
}

# ── Deploy (IPI) ──────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  BUILD_DIR="${1:-}"
  if [[ -z "${BUILD_DIR}" ]]; then
    log_fatal "Usage: $0 <build-dir>"
  fi
  log_info "Deploying OpenShift on vSphere..."
  openshift-install create cluster --dir "${BUILD_DIR}" --log-level info
  log_ok "vSphere IPI deployment complete."
fi
