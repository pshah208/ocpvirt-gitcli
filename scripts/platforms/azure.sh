#!/usr/bin/env bash
# scripts/platforms/azure.sh — Azure prerequisite checks and deploy steps.
# Sourced by scripts/preflight.sh and scripts/deploy.sh.

set -euo pipefail

SCRIPT_DIR_PLATFORMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR_PLATFORMS}/../lib/common.sh"

# ── Prerequisite checks ───────────────────────────────────────────────────────
run_azure_checks() {
  local check_failures=0

  # Azure CLI
  if ! check_cmd az "Azure CLI"; then
    log_error "Install Azure CLI: https://learn.microsoft.com/en-us/cli/azure/install-azure-cli"
    (( check_failures++ )) || true
    return "${check_failures}"
  fi

  # Subscription / auth
  if az account show &>/dev/null 2>&1; then
    local sub_name
    sub_name="$(az account show --query name --output tsv 2>/dev/null)"
    log_ok "Azure subscription active: ${sub_name}"
  else
    log_error "Azure CLI not authenticated. Run: az login"
    (( check_failures++ )) || true
  fi

  # Region
  AZURE_REGION="${AZURE_REGION:-}"
  if [[ -z "${AZURE_REGION}" ]]; then
    log_warn "AZURE_REGION not set — skipping quota checks"
  else
    log_ok "Azure region: ${AZURE_REGION}"

    # vCPU quota
    local current_vcpu
    current_vcpu="$(az vm list-usage --location "${AZURE_REGION}" \
      --query "[?name.value=='cores'].currentValue" \
      --output tsv 2>/dev/null || echo '0')"
    log_info "Azure vCPU usage in ${AZURE_REGION}: ${current_vcpu}"
  fi

  # DNS zone
  AZURE_DNS_RG="${AZURE_DNS_RG:-}"
  if [[ -n "${BASE_DOMAIN:-}" && -n "${AZURE_DNS_RG}" ]]; then
    if az network dns zone show \
        --resource-group "${AZURE_DNS_RG}" \
        --name "${BASE_DOMAIN}" &>/dev/null 2>&1; then
      log_ok "Azure DNS zone found: ${BASE_DOMAIN} in RG ${AZURE_DNS_RG}"
    else
      log_warn "Azure DNS zone '${BASE_DOMAIN}' not found in RG '${AZURE_DNS_RG}'"
    fi
  else
    log_warn "AZURE_DNS_RG or BASE_DOMAIN not set — skipping DNS zone check"
  fi

  return "${check_failures}"
}

# ── Deploy (IPI) ──────────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  BUILD_DIR="${1:-}"
  if [[ -z "${BUILD_DIR}" ]]; then
    log_fatal "Usage: $0 <build-dir>"
  fi
  log_info "Deploying OpenShift on Azure..."
  openshift-install create cluster --dir "${BUILD_DIR}" --log-level info
  log_ok "Azure IPI deployment complete."
fi
