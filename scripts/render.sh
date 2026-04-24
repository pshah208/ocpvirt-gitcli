#!/usr/bin/env bash
# scripts/render.sh — render an envsubst template into an output file.
#
# Usage:
#   VARS_FILE=cluster.vars.yaml bash scripts/render.sh <template> <output>
#
# All ${VAR} placeholders in <template> are resolved using environment variables.
# Variables are first loaded from VARS_FILE (if set), then from the environment.
# Pull secret and SSH key are loaded from files referenced by PULL_SECRET_PATH
# and SSH_KEY_PATH — they are NEVER stored in vars files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
install_trap

# ── Arguments ─────────────────────────────────────────────────────────────────
TEMPLATE="${1:-}"
OUTPUT="${2:-}"

if [[ -z "${TEMPLATE}" || -z "${OUTPUT}" ]]; then
  log_fatal "Usage: VARS_FILE=cluster.vars.yaml bash $0 <template> <output>"
fi

require_file "${TEMPLATE}" "Template file"
require_cmd envsubst "Template renderer (install gettext-base)"

# ── Load vars ─────────────────────────────────────────────────────────────────
VARS_FILE="${VARS_FILE:-cluster.vars.yaml}"
if [[ -f "${VARS_FILE}" ]]; then
  load_vars "${VARS_FILE}"
else
  log_warn "VARS_FILE '${VARS_FILE}' not found — using only environment variables"
fi

# ── Load secrets from files (never from vars) ─────────────────────────────────
PULL_SECRET_PATH="${PULL_SECRET_PATH:-.secrets/pull-secret.json}"
SSH_KEY_PATH="${SSH_KEY_PATH:-${HOME}/.ssh/id_rsa.pub}"

if [[ -f "${PULL_SECRET_PATH}" ]]; then
  export PULL_SECRET
  PULL_SECRET="$(cat "${PULL_SECRET_PATH}")"
else
  log_warn "Pull secret not found at '${PULL_SECRET_PATH}' — PULL_SECRET will be empty"
  export PULL_SECRET='{"auths":{}}'
fi

if [[ -f "${SSH_KEY_PATH}" ]]; then
  export SSH_KEY
  SSH_KEY="$(cat "${SSH_KEY_PATH}")"
else
  log_warn "SSH key not found at '${SSH_KEY_PATH}' — SSH_KEY will be empty"
  export SSH_KEY='ssh-ed25519 PLACEHOLDER'
fi

# ── Derive convenience vars (RAM in MB for vSphere template) ──────────────────
if [[ -n "${CP_RAM_GIB:-}" ]]; then
  export CP_RAM_MB=$(( CP_RAM_GIB * 1024 ))
fi
if [[ -n "${WORKER_RAM_GIB:-}" ]]; then
  export WORKER_RAM_MB=$(( WORKER_RAM_GIB * 1024 ))
fi

# ── Render ────────────────────────────────────────────────────────────────────
mkdir -p "$(dirname "${OUTPUT}")"
# Strip trailing whitespace from each line (avoids yamllint errors when
# commented-out optional vars expand to empty strings).
envsubst < "${TEMPLATE}" | sed 's/[[:space:]]*$//' > "${OUTPUT}"

log_ok "Rendered: ${OUTPUT}"
