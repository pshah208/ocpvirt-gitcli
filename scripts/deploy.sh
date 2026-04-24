#!/usr/bin/env bash
# scripts/deploy.sh — top-level deployment dispatcher.
#
# Usage:
#   VARS_FILE=cluster.vars.yaml bash scripts/deploy.sh [--skip-preflight]
#
# Reads 'platform' from VARS_FILE and delegates to the appropriate platform
# script in scripts/platforms/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
install_trap

# ── Arguments ─────────────────────────────────────────────────────────────────
SKIP_PREFLIGHT=false
for arg in "$@"; do
  case "${arg}" in
    --skip-preflight) SKIP_PREFLIGHT=true ;;
    *) log_fatal "Unknown argument: ${arg}" ;;
  esac
done

VARS_FILE="${VARS_FILE:-cluster.vars.yaml}"
require_file "${VARS_FILE}" "Cluster vars file"
load_vars "${VARS_FILE}"

PLATFORM="${PLATFORM:-}"
if [[ -z "${PLATFORM}" ]]; then
  log_fatal "PLATFORM not set in ${VARS_FILE}. Set 'platform: <aws|azure|gcp|vsphere|baremetal-agent|kvm-libvirt>'"
fi

CLUSTER_NAME="${CLUSTER_NAME:-}"
if [[ -z "${CLUSTER_NAME}" ]]; then
  log_fatal "CLUSTER_NAME not set in ${VARS_FILE}."
fi

log_info "Deploy: cluster='${CLUSTER_NAME}', platform='${PLATFORM}'"

# ── Preflight ─────────────────────────────────────────────────────────────────
if [[ "${SKIP_PREFLIGHT}" == "false" ]]; then
  log_info "Running prerequisite checks..."
  VARS_FILE="${VARS_FILE}" bash "${SCRIPT_DIR}/preflight.sh" "${PLATFORM}"
else
  log_warn "--skip-preflight specified — skipping preflight checks."
fi

# ── Render install-config.yaml ────────────────────────────────────────────────
log_info "Rendering install-config.yaml..."
TMPL_MAP=(
  "aws:${SCRIPT_DIR}/../templates/install-config/aws.install-config.yaml.tmpl"
  "azure:${SCRIPT_DIR}/../templates/install-config/azure.install-config.yaml.tmpl"
  "gcp:${SCRIPT_DIR}/../templates/install-config/gcp.install-config.yaml.tmpl"
  "vsphere:${SCRIPT_DIR}/../templates/install-config/vsphere.install-config.yaml.tmpl"
  "baremetal-agent:${SCRIPT_DIR}/../templates/install-config/baremetal.install-config.yaml.tmpl"
  "kvm-libvirt:${SCRIPT_DIR}/../templates/install-config/baremetal.install-config.yaml.tmpl"
)

TEMPLATE=""
for entry in "${TMPL_MAP[@]}"; do
  key="${entry%%:*}"
  val="${entry#*:}"
  if [[ "${PLATFORM}" == "${key}" ]]; then
    TEMPLATE="${val}"
    break
  fi
done

if [[ -z "${TEMPLATE}" ]]; then
  log_fatal "No template mapping for platform '${PLATFORM}'"
fi

BUILD_DIR="${SCRIPT_DIR}/../build/${CLUSTER_NAME}"
VARS_FILE="${VARS_FILE}" bash "${SCRIPT_DIR}/render.sh" \
  "${TEMPLATE}" \
  "${BUILD_DIR}/install-config.yaml"

# ── Agent-based: also render agent-config.yaml ───────────────────────────────
if [[ "${PLATFORM}" == "baremetal-agent" || "${PLATFORM}" == "kvm-libvirt" ]]; then
  log_info "Rendering agent-config.yaml..."
  VARS_FILE="${VARS_FILE}" bash "${SCRIPT_DIR}/render.sh" \
    "${SCRIPT_DIR}/../templates/agent/agent-config.yaml.tmpl" \
    "${BUILD_DIR}/agent-config.yaml"
fi

# ── Manifest dry-run ─────────────────────────────────────────────────────────
log_info "Running 'openshift-install create manifests' (dry-run)..."
cp "${BUILD_DIR}/install-config.yaml" "${BUILD_DIR}/install-config.yaml.bak"
openshift-install create manifests --dir "${BUILD_DIR}"

log_info "Manifests written to: ${BUILD_DIR}/manifests/"
log_info "Review them now if you need to add customisations."
echo ""

# ── Platform-specific deploy ─────────────────────────────────────────────────
case "${PLATFORM}" in
  aws)           bash "${SCRIPT_DIR}/platforms/aws.sh" "${BUILD_DIR}" ;;
  azure)         bash "${SCRIPT_DIR}/platforms/azure.sh" "${BUILD_DIR}" ;;
  gcp)           bash "${SCRIPT_DIR}/platforms/gcp.sh" "${BUILD_DIR}" ;;
  vsphere)       bash "${SCRIPT_DIR}/platforms/vsphere.sh" "${BUILD_DIR}" ;;
  baremetal-agent) bash "${SCRIPT_DIR}/platforms/baremetal-agent.sh" "${BUILD_DIR}" ;;
  kvm-libvirt)   bash "${SCRIPT_DIR}/platforms/baremetal-agent.sh" "${BUILD_DIR}" ;;
  *)             log_fatal "Unsupported platform: ${PLATFORM}" ;;
esac

# ── Post-install: set KUBECONFIG ──────────────────────────────────────────────
KUBECONFIG_PATH="${BUILD_DIR}/auth/kubeconfig"
if [[ -f "${KUBECONFIG_PATH}" ]]; then
  export KUBECONFIG="${KUBECONFIG_PATH}"
  log_ok "KUBECONFIG exported: ${KUBECONFIG_PATH}"
  log_info "Run: export KUBECONFIG=${KUBECONFIG_PATH}"
fi

# ── Optional: install CNV ─────────────────────────────────────────────────────
GOAL="${GOAL:-ocp-only}"
if [[ "${GOAL}" == "ocp+cnv" ]]; then
  log_info "Goal is ocp+cnv — installing OpenShift Virtualization..."
  VARS_FILE="${VARS_FILE}" bash "${SCRIPT_DIR}/install-cnv.sh"
fi

log_ok "Deployment complete for cluster: ${CLUSTER_NAME}"
