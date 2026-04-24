#!/usr/bin/env bash
# scripts/platforms/gcp.sh — GCP prerequisite checks and deploy steps.
# Sourced by scripts/preflight.sh and scripts/deploy.sh.

set -euo pipefail

SCRIPT_DIR_PLATFORMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR_PLATFORMS}/../lib/common.sh"

# Required GCP APIs for OpenShift IPI
REQUIRED_APIS=(
  "compute.googleapis.com"
  "dns.googleapis.com"
  "iam.googleapis.com"
  "iamcredentials.googleapis.com"
  "servicemanagement.googleapis.com"
  "cloudresourcemanager.googleapis.com"
  "storage-api.googleapis.com"
)

# ── Prerequisite checks ───────────────────────────────────────────────────────
run_gcp_checks() {
  local check_failures=0

  # gcloud CLI
  if ! check_cmd gcloud "Google Cloud SDK"; then
    log_error "Install gcloud SDK: https://cloud.google.com/sdk/docs/install"
    (( check_failures++ )) || true
    return "${check_failures}"
  fi

  # Auth
  if gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | grep -q '@'; then
    local active_account
    active_account="$(gcloud auth list --filter=status:ACTIVE \
      --format='value(account)' 2>/dev/null | head -1)"
    log_ok "gcloud authenticated as: ${active_account}"
  else
    log_error "gcloud not authenticated. Run: gcloud auth login"
    (( check_failures++ )) || true
  fi

  # Project
  GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || echo '')}"
  if [[ -z "${GCP_PROJECT}" ]]; then
    log_warn "GCP_PROJECT not set — skipping project and API checks"
  else
    log_ok "GCP project: ${GCP_PROJECT}"

    # Verify project is accessible
    if gcloud projects describe "${GCP_PROJECT}" &>/dev/null 2>&1; then
      log_ok "GCP project accessible: ${GCP_PROJECT}"
    else
      log_error "Cannot access GCP project: ${GCP_PROJECT}"
      (( check_failures++ )) || true
    fi

    # Check required APIs
    for api in "${REQUIRED_APIS[@]}"; do
      if gcloud services list --enabled \
          --project "${GCP_PROJECT}" \
          --filter="name:${api}" \
          --format='value(name)' 2>/dev/null | grep -q "${api}"; then
        log_ok "GCP API enabled: ${api}"
      else
        log_warn "GCP API not enabled: ${api} — run: gcloud services enable ${api}"
      fi
    done
  fi

  # DNS zone
  if [[ -n "${BASE_DOMAIN:-}" && -n "${GCP_PROJECT:-}" ]]; then
    if gcloud dns managed-zones list \
        --project "${GCP_PROJECT}" \
        --filter="dnsName:${BASE_DOMAIN}." \
        --format='value(name)' 2>/dev/null | grep -q '.'; then
      log_ok "GCP Cloud DNS zone found for: ${BASE_DOMAIN}"
    else
      log_warn "No Cloud DNS zone found for '${BASE_DOMAIN}' in project '${GCP_PROJECT}'"
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
  log_info "Deploying OpenShift on GCP..."
  openshift-install create cluster --dir "${BUILD_DIR}" --log-level info
  log_ok "GCP IPI deployment complete."
fi
