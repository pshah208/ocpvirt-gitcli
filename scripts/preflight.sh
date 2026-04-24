#!/usr/bin/env bash
# scripts/preflight.sh — run prerequisite checks for a given platform.
# Usage: bash scripts/preflight.sh <platform>
# Platform: aws | azure | gcp | vsphere | baremetal | cnv
#
# Exits 0 if all checks pass, non-zero if any ❌ failures are found.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
install_trap

# ── Argument handling ─────────────────────────────────────────────────────────
PLATFORM="${1:-}"
if [[ -z "${PLATFORM}" ]]; then
  log_fatal "Usage: $0 <platform>  (aws | azure | gcp | vsphere | baremetal | cnv)"
fi

# ── Load vars (optional — some checks need them) ──────────────────────────────
VARS_FILE="${VARS_FILE:-cluster.vars.yaml}"
if [[ -f "${VARS_FILE}" ]]; then
  load_vars "${VARS_FILE}"
else
  log_warn "No vars file found at '${VARS_FILE}' — skipping variable-dependent checks."
fi

PULL_SECRET_PATH="${PULL_SECRET_PATH:-.secrets/pull-secret.json}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}"
BASE_DOMAIN="${BASE_DOMAIN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"

# ── Failure tracking ──────────────────────────────────────────────────────────
FAILURES=0
fail() { log_error "$*"; (( FAILURES++ )) || true; }

# ── Common checks (all platforms) ────────────────────────────────────────────
common_checks() {
  log_info "=== Common prerequisite checks ==="

  require_cmd oc "OpenShift CLI"        || fail "oc not installed"
  require_cmd openshift-install "OpenShift Installer" || fail "openshift-install not installed"
  require_cmd jq "JSON processor"       || fail "jq not installed"
  require_cmd curl "HTTP client"        || fail "curl not installed"
  check_cmd yq "YAML processor"         || log_warn "yq not installed — some features may be limited"
  check_cmd envsubst "Template renderer (gettext)" || log_warn "envsubst not installed — template rendering unavailable"

  # Internet connectivity
  check_url "https://quay.io/v2/"            "quay.io"            || fail "quay.io unreachable"
  check_url "https://registry.redhat.io/v2/" "registry.redhat.io" || fail "registry.redhat.io unreachable"
  check_url "https://mirror.openshift.com"   "mirror.openshift.com" || fail "mirror.openshift.com unreachable"

  # Pull secret
  if require_file "${PULL_SECRET_PATH}" "Pull secret" 2>/dev/null; then
    if jq . "${PULL_SECRET_PATH}" &>/dev/null; then
      log_ok "Pull secret is valid JSON"
    else
      fail "Pull secret at ${PULL_SECRET_PATH} is not valid JSON"
    fi
  else
    fail "Pull secret not found at ${PULL_SECRET_PATH}"
  fi

  # SSH key
  require_file "${SSH_KEY_PATH}" "SSH public key" || fail "SSH public key not found at ${SSH_KEY_PATH}"

  # Base domain DNS
  if [[ -n "${BASE_DOMAIN}" ]]; then
    if nslookup "${BASE_DOMAIN}" &>/dev/null; then
      log_ok "Base domain resolvable: ${BASE_DOMAIN}"
    else
      log_warn "Base domain '${BASE_DOMAIN}' not resolvable from this host (may be expected)"
    fi
  else
    log_warn "BASE_DOMAIN not set — skipping DNS check"
  fi
}

# ── Platform-specific checks ──────────────────────────────────────────────────
aws_checks() {
  log_info "=== AWS prerequisite checks ==="
  # shellcheck source=scripts/platforms/aws.sh
  source "${SCRIPT_DIR}/platforms/aws.sh"
  run_aws_checks || (( FAILURES++ )) || true
}

azure_checks() {
  log_info "=== Azure prerequisite checks ==="
  # shellcheck source=scripts/platforms/azure.sh
  source "${SCRIPT_DIR}/platforms/azure.sh"
  run_azure_checks || (( FAILURES++ )) || true
}

gcp_checks() {
  log_info "=== GCP prerequisite checks ==="
  # shellcheck source=scripts/platforms/gcp.sh
  source "${SCRIPT_DIR}/platforms/gcp.sh"
  run_gcp_checks || (( FAILURES++ )) || true
}

vsphere_checks() {
  log_info "=== vSphere prerequisite checks ==="
  # shellcheck source=scripts/platforms/vsphere.sh
  source "${SCRIPT_DIR}/platforms/vsphere.sh"
  run_vsphere_checks || (( FAILURES++ )) || true
}

baremetal_checks() {
  log_info "=== Bare-metal (Agent-based) prerequisite checks ==="
  # shellcheck source=scripts/platforms/baremetal-agent.sh
  source "${SCRIPT_DIR}/platforms/baremetal-agent.sh"
  run_baremetal_checks || (( FAILURES++ )) || true
}

cnv_checks() {
  log_info "=== CNV-specific prerequisite checks ==="

  # virtctl CLI
  check_cmd virtctl "KubeVirt VM management CLI" || log_warn "virtctl not installed"

  # Must have a running cluster for most CNV checks
  if ! oc whoami &>/dev/null 2>&1; then
    log_warn "Not connected to an OpenShift cluster — skipping live CNV checks"
    return 0
  fi

  # Check for RWX storage class
  RWX_SC="${CNV_RWX_SC:-}"
  if [[ -n "${RWX_SC}" ]]; then
    if oc get storageclass "${RWX_SC}" &>/dev/null 2>&1; then
      log_ok "RWX storage class found: ${RWX_SC}"
    else
      fail "RWX storage class '${RWX_SC}' not found — live migration requires RWX"
    fi
  else
    log_warn "CNV_RWX_SC not set — manually verify an RWX storage class exists"
  fi

  # Check CPU flags on worker nodes
  log_info "Checking CPU virtualisation extensions on worker nodes..."
  for node in $(oc get nodes -l node-role.kubernetes.io/worker \
      -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    FLAGS=$(oc debug "node/${node}" -- grep -m1 -o 'vmx\|svm' /proc/cpuinfo 2>/dev/null || true)
    if [[ -n "${FLAGS}" ]]; then
      log_ok "Node ${node}: CPU flags present (${FLAGS})"
    else
      fail "Node ${node}: vmx/svm CPU flags NOT found — CNV requires hardware virt extensions"
    fi
  done
}

# ── Main dispatch ─────────────────────────────────────────────────────────────
common_checks

case "${PLATFORM,,}" in
  aws)        aws_checks ;;
  azure)      azure_checks ;;
  gcp)        gcp_checks ;;
  vsphere)    vsphere_checks ;;
  baremetal)  baremetal_checks ;;
  cnv)        cnv_checks ;;
  *)
    log_fatal "Unknown platform '${PLATFORM}'. Supported: aws | azure | gcp | vsphere | baremetal | cnv"
    ;;
esac

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if [[ "${FAILURES}" -eq 0 ]]; then
  log_ok "All prerequisite checks passed for platform: ${PLATFORM}"
  exit 0
else
  log_error "${FAILURES} prerequisite check(s) failed for platform: ${PLATFORM}."
  log_error "Fix the issues above before proceeding with the install."
  exit 1
fi
