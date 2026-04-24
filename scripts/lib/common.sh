#!/usr/bin/env bash
# scripts/lib/common.sh — shared helpers used by all scripts in this repo.
# Source with: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
log_info()  { echo -e "${BLUE}[INFO]${RESET}  $*"; }
log_ok()    { echo -e "${GREEN}✅${RESET}  $*"; }
log_warn()  { echo -e "${YELLOW}⚠️ ${RESET}  $*"; }
log_error() { echo -e "${RED}❌${RESET}  $*" >&2; }
log_fatal() { log_error "$*"; exit 1; }

# ── Prerequisite helpers ─────────────────────────────────────────────────────

# require_cmd <cmd> [description]
# Exits with an error if <cmd> is not found in PATH.
require_cmd() {
  local cmd="${1}"
  local desc="${2:-${cmd}}"
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "Required command not found: ${cmd} (${desc})"
    return 1
  fi
  log_ok "${cmd} found"
}

# check_cmd <cmd> [description]
# Like require_cmd but prints a warning and returns 1 instead of exiting.
check_cmd() {
  local cmd="${1}"
  local desc="${2:-${cmd}}"
  if ! command -v "${cmd}" &>/dev/null; then
    log_warn "${cmd} not found (${desc}) — some checks will be skipped"
    return 1
  fi
  log_ok "${cmd} found"
  return 0
}

# check_url <url> [description]
# Returns 0 if the URL is reachable, 1 otherwise.
check_url() {
  local url="${1}"
  local desc="${2:-${url}}"
  if curl -sSf --max-time 10 "${url}" &>/dev/null; then
    log_ok "Reachable: ${desc}"
    return 0
  else
    log_error "Unreachable: ${desc} (${url})"
    return 1
  fi
}

# require_file <path> [description]
# Exits with an error if the file does not exist.
require_file() {
  local path="${1}"
  local desc="${2:-${path}}"
  if [[ ! -f "${path}" ]]; then
    log_error "Required file not found: ${path} (${desc})"
    return 1
  fi
  log_ok "File exists: ${desc}"
}

# require_env <var>
# Exits if the environment variable is empty.
require_env() {
  local var="${1}"
  if [[ -z "${!var:-}" ]]; then
    log_error "Required environment variable not set: ${var}"
    return 1
  fi
}

# ── Error trap ────────────────────────────────────────────────────────────────

# Call install_trap at the start of a script to get a clean error message
# on unexpected exit.
install_trap() {
  trap '_trap_handler $? $LINENO' ERR
}

_trap_handler() {
  local exit_code="${1}"
  local line_no="${2}"
  log_error "Script failed at line ${line_no} with exit code ${exit_code}."
}

# ── Cluster vars loader ───────────────────────────────────────────────────────

# load_vars <vars-file>
# Exports all scalar values from a YAML vars file as environment variables.
# Requires python3 + pyyaml (or python3-yaml).
load_vars() {
  local vars_file="${1:-cluster.vars.yaml}"
  if [[ ! -f "${vars_file}" ]]; then
    log_fatal "Vars file not found: ${vars_file}"
  fi

  # Export flat key=value pairs from the YAML (nested keys use _ as separator)
  eval "$(python3 - "${vars_file}" <<'PY'
import sys, yaml
def flatten(d, prefix=''):
    for k, v in d.items():
        key = (prefix + '_' + str(k)).lstrip('_').upper()
        if isinstance(v, dict):
            flatten(v, key)
        elif v is not None:
            safe = str(v).replace("'", "'\\''")
            print(f"export {key}='{safe}'")
flatten(yaml.safe_load(open(sys.argv[1])) or {})
PY
)"
  log_info "Loaded vars from ${vars_file}"
}
