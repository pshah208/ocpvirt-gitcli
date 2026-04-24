#!/usr/bin/env bash
# scripts/platforms/aws.sh — AWS prerequisite checks and deploy steps.
# Sourced by scripts/preflight.sh and scripts/deploy.sh.

set -euo pipefail

SCRIPT_DIR_PLATFORMS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR_PLATFORMS}/../lib/common.sh"

# ── Prerequisite checks ───────────────────────────────────────────────────────
run_aws_checks() {
  local check_failures=0

  # AWS CLI
  if ! check_cmd aws "AWS CLI v2"; then
    log_error "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    (( check_failures++ )) || true
    return "${check_failures}"
  fi

  # Caller identity
  if aws sts get-caller-identity &>/dev/null 2>&1; then
    local account
    account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
    log_ok "AWS credentials valid (account: ${account})"
  else
    log_error "AWS credentials invalid or not configured. Run: aws configure"
    (( check_failures++ )) || true
  fi

  # Region
  AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo '')}"
  if [[ -z "${AWS_REGION}" ]]; then
    log_warn "AWS_REGION not set — some quota checks will be skipped"
  else
    log_ok "AWS region: ${AWS_REGION}"
  fi

  # Route53 hosted zone
  if [[ -n "${BASE_DOMAIN:-}" && -n "${AWS_REGION:-}" ]]; then
    if aws route53 list-hosted-zones-by-name \
        --dns-name "${BASE_DOMAIN}" \
        --query 'HostedZones[0].Name' \
        --output text 2>/dev/null | grep -q "${BASE_DOMAIN}"; then
      log_ok "Route53 hosted zone found for: ${BASE_DOMAIN}"
    else
      log_warn "No Route53 hosted zone found for '${BASE_DOMAIN}' — create one before install"
    fi
  fi

  # vCPU quota (Running On-Demand Standard instances)
  if [[ -n "${AWS_REGION:-}" ]]; then
    local vcpu_limit
    vcpu_limit="$(aws service-quotas get-service-quota \
      --service-code ec2 \
      --quota-code L-1216C47A \
      --region "${AWS_REGION}" \
      --query 'Quota.Value' \
      --output text 2>/dev/null || echo '0')"
    if [[ "${vcpu_limit%.*}" -ge 96 ]]; then
      log_ok "EC2 vCPU quota: ${vcpu_limit} (sufficient)"
    else
      log_warn "EC2 vCPU quota ${vcpu_limit} may be insufficient. Recommend ≥ 96 for standard cluster."
    fi
  fi

  return "${check_failures}"
}

# ── Deploy (IPI) ──────────────────────────────────────────────────────────────
# Called by deploy.sh with BUILD_DIR as argument
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  BUILD_DIR="${1:-}"
  if [[ -z "${BUILD_DIR}" ]]; then
    log_fatal "Usage: $0 <build-dir>"
  fi
  log_info "Deploying OpenShift on AWS..."
  openshift-install create cluster --dir "${BUILD_DIR}" --log-level info
  log_ok "AWS IPI deployment complete."
fi
