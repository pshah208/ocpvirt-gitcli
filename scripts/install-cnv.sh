#!/usr/bin/env bash
# scripts/install-cnv.sh — apply CNV manifests and wait for HCO to become Ready.
#
# Usage:
#   KUBECONFIG=<path> bash scripts/install-cnv.sh
#
# Requires an authenticated oc session (KUBECONFIG set).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
install_trap

TEMPLATES_CNV="${SCRIPT_DIR}/../templates/cnv"
HCO_NAMESPACE="openshift-cnv"
HCO_NAME="kubevirt-hyperconverged"
TIMEOUT_SECONDS=900  # 15 minutes

# ── Prerequisites ─────────────────────────────────────────────────────────────
require_cmd oc "OpenShift CLI"
if ! oc whoami &>/dev/null 2>&1; then
  log_fatal "Not connected to an OpenShift cluster. Set KUBECONFIG and ensure oc whoami works."
fi

log_info "Installing OpenShift Virtualization on cluster: $(oc whoami --show-server)"

# ── Apply manifests in order ──────────────────────────────────────────────────
for manifest in \
  "01-namespace.yaml" \
  "02-operatorgroup.yaml" \
  "03-subscription.yaml" \
  "04-hyperconverged.yaml"; do
  manifest_path="${TEMPLATES_CNV}/${manifest}"
  require_file "${manifest_path}" "CNV manifest"
  log_info "Applying: ${manifest}"
  oc apply -f "${manifest_path}"
done

# ── Wait for CSV to succeed ───────────────────────────────────────────────────
log_info "Waiting for kubevirt-hyperconverged CSV to reach Succeeded..."
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

until oc get csv -n "${HCO_NAMESPACE}" \
    -o jsonpath='{.items[?(@.spec.displayName=="KubeVirt HyperConverged Cluster Operator")].status.phase}' \
    2>/dev/null | grep -q "Succeeded"; do
  if [[ "$(date +%s)" -gt "${DEADLINE}" ]]; then
    log_fatal "Timed out waiting for CNV CSV to reach Succeeded after ${TIMEOUT_SECONDS}s"
  fi
  echo -n "."
  sleep 15
done
echo ""
log_ok "CNV CSV reached Succeeded"

# ── Wait for HCO to become Available ─────────────────────────────────────────
log_info "Waiting for HyperConverged CR '${HCO_NAME}' to become Available..."
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

until oc get hco "${HCO_NAME}" -n "${HCO_NAMESPACE}" \
    -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' \
    2>/dev/null | grep -q "True"; do
  if [[ "$(date +%s)" -gt "${DEADLINE}" ]]; then
    log_fatal "Timed out waiting for HyperConverged to become Available after ${TIMEOUT_SECONDS}s"
  fi
  echo -n "."
  sleep 15
done
echo ""
log_ok "HyperConverged '${HCO_NAME}' is Available"

# ── Summary ───────────────────────────────────────────────────────────────────
log_info "CNV components deployed:"
oc get pods -n "${HCO_NAMESPACE}" --no-headers \
  | awk '{print "  " $1 " — " $3}'

log_ok "OpenShift Virtualization installation complete."
log_info "Next steps:"
log_info "  1. Configure storage: oc apply -f templates/storage/odf-subscription.yaml"
log_info "  2. Configure networking: oc apply -f templates/networking/nmstate-operator.yaml"
log_info "  3. Deploy a test VM using the cnv-post-install prompt."
