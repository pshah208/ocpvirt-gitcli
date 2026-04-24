#!/usr/bin/env bash
# scripts/lib/prompts.sh — interactive read -p helpers for intake Q&A.
# Source with: source "$(dirname "${BASH_SOURCE[0]}")/lib/prompts.sh"

set -euo pipefail

# ── Prompt helpers ────────────────────────────────────────────────────────────

# ask <variable_name> <prompt_text> [default_value]
# Reads a value from stdin; if empty and default is provided, uses the default.
# Stores the result in the named variable.
ask() {
  local var_name="${1}"
  local prompt_text="${2}"
  local default="${3:-}"
  local display_default=""

  if [[ -n "${default}" ]]; then
    display_default=" [${default}]"
  fi

  local value=""
  read -r -p "${prompt_text}${display_default}: " value
  if [[ -z "${value}" && -n "${default}" ]]; then
    value="${default}"
  fi
  # Export so caller can use the variable
  printf -v "${var_name}" '%s' "${value}"
  export "${var_name?}"
}

# ask_required <variable_name> <prompt_text>
# Keeps prompting until the user provides a non-empty value.
ask_required() {
  local var_name="${1}"
  local prompt_text="${2}"
  local value=""

  while [[ -z "${value}" ]]; do
    read -r -p "${prompt_text} (required): " value
    if [[ -z "${value}" ]]; then
      echo "  This field is required. Please enter a value."
    fi
  done
  printf -v "${var_name}" '%s' "${value}"
  export "${var_name?}"
}

# ask_choice <variable_name> <prompt_text> <option1> [option2 ...]
# Prompts for one of a set of allowed values; loops until valid input.
ask_choice() {
  local var_name="${1}"
  local prompt_text="${2}"
  shift 2
  local options=("$@")
  local value=""
  local joined
  joined="$(printf ' | %s' "${options[@]}")"
  joined="${joined:3}"  # strip leading ' | '

  while true; do
    read -r -p "${prompt_text} (${joined}): " value
    for opt in "${options[@]}"; do
      if [[ "${value}" == "${opt}" ]]; then
        printf -v "${var_name}" '%s' "${value}"
        export "${var_name?}"
        return 0
      fi
    done
    echo "  Invalid choice '${value}'. Please enter one of: ${joined}"
  done
}

# ask_yesno <variable_name> <prompt_text> [default: yes|no]
# Stores 'true' or 'false' in the named variable.
ask_yesno() {
  local var_name="${1}"
  local prompt_text="${2}"
  local default="${3:-no}"
  local value=""

  while true; do
    read -r -p "${prompt_text} (yes/no) [${default}]: " value
    value="${value:-${default}}"
    case "${value,,}" in
      yes|y|true)  printf -v "${var_name}" 'true';  export "${var_name?}"; return 0 ;;
      no|n|false)  printf -v "${var_name}" 'false'; export "${var_name?}"; return 0 ;;
      *) echo "  Please enter yes or no." ;;
    esac
  done
}

# confirm <message>
# Prompts for confirmation (y/N). Exits 1 if user declines.
confirm() {
  local message="${1:-Continue?}"
  local response=""
  read -r -p "${message} (y/N): " response
  case "${response,,}" in
    y|yes) return 0 ;;
    *) echo "Aborted."; return 1 ;;
  esac
}
