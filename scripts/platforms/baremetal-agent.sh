#!/usr/bin/env bash
# scripts/platforms/baremetal-agent.sh — bare-metal Agent-based Installer checks
# and deploy steps.
# Sourced by scripts/preflight.sh and scripts/deploy.sh.

set -euo pipefail

SCRIPT_DIR_PLATFORMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR_PLATFORMS}/../lib/common.sh"

# ── Prerequisite checks ───────────────────────────────────────────────────────
run_baremetal_checks() {
  local check_failures=0

  # openshift-install agent subcommand requires >= 4.12
  if command -v openshift-install &>/dev/null; then
    local oi_version
    oi_version="$(openshift-install version 2>/dev/null | head -1 | awk '{print $2}' || echo '')"
    log_info "openshift-install version: ${oi_version}"
  fi

  # ipmitool / curl for BMC checks
  check_cmd ipmitool "IPMI BMC tool" || log_warn "ipmitool not installed — IPMI BMC checks skipped"

  # API and Ingress VIPs
  API_VIP="${API_VIP:-}"
  INGRESS_VIP="${INGRESS_VIP:-}"

  if [[ -z "${API_VIP}" || -z "${INGRESS_VIP}" ]]; then
    log_warn "API_VIP or INGRESS_VIP not set — skipping VIP availability checks"
  else
    for vip_label in "API_VIP:${API_VIP}" "INGRESS_VIP:${INGRESS_VIP}"; do
      label="${vip_label%%:*}"
      vip_addr="${vip_label#*:}"
      # arping availability check — only works on the same L2 segment
      if command -v arping &>/dev/null; then
        if ! arping -c 2 -w 3 "${vip_addr}" &>/dev/null 2>&1; then
          log_ok "${label} (${vip_addr}) appears to be free (no ARP response)"
        else
          log_warn "${label} (${vip_addr}) received ARP response — may already be in use"
        fi
      else
        log_warn "arping not available — cannot check if ${label} (${vip_addr}) is free"
      fi
    done

    # DNS checks
    if [[ -n "${CLUSTER_NAME:-}" && -n "${BASE_DOMAIN:-}" ]]; then
      for record in \
          "api.${CLUSTER_NAME}.${BASE_DOMAIN}" \
          "test.apps.${CLUSTER_NAME}.${BASE_DOMAIN}"; do
        if nslookup "${record}" &>/dev/null 2>&1; then
          log_ok "DNS resolves: ${record}"
        else
          log_warn "DNS not resolving: ${record} — create A record before install"
        fi
      done
    fi
  fi

  # Rendezvous IP
  RENDEZVOUS_IP="${RENDEZVOUS_IP:-}"
  if [[ -n "${RENDEZVOUS_IP}" ]]; then
    if ping -c 1 -W 3 "${RENDEZVOUS_IP}" &>/dev/null 2>&1; then
      log_ok "Rendezvous IP reachable: ${RENDEZVOUS_IP}"
    else
      log_warn "Rendezvous IP not reachable: ${RENDEZVOUS_IP} (host may be powered off — expected)"
    fi
  else
    log_warn "RENDEZVOUS_IP not set — skipping rendezvous check"
  fi

  return "${check_failures}"
}

# ── Deploy (Agent-based) ──────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  BUILD_DIR="${1:-}"
  if [[ -z "${BUILD_DIR}" ]]; then
    log_fatal "Usage: $0 <build-dir>"
  fi

  require_file "${BUILD_DIR}/install-config.yaml" "install-config.yaml"
  require_file "${BUILD_DIR}/agent-config.yaml" "agent-config.yaml"

  log_info "Generating Agent ISO..."
  openshift-install agent create image --dir "${BUILD_DIR}" --log-level info

  ISO_PATH="${BUILD_DIR}/agent.x86_64.iso"
  if [[ -f "${ISO_PATH}" ]]; then
    log_ok "Agent ISO created: ${ISO_PATH}"
    log_info "Boot each host from this ISO (virtual media, USB, or PXE chain)."
  fi

  log_info "Waiting for bootstrap to complete..."
  openshift-install agent wait-for bootstrap-complete \
    --dir "${BUILD_DIR}" --log-level debug

  log_info "Waiting for installation to complete..."
  openshift-install agent wait-for install-complete \
    --dir "${BUILD_DIR}" --log-level debug

  log_ok "Agent-based deployment complete."
fi
