#!/usr/bin/env bash
#
# vibe-cai-launch.sh — Launch Mistral Vibe against Cloudera AI Inference (OpenAI API).
#
# Installed to ~/.local/bin/vibe-cai by install-cai-vibe.sh.
#
# Usage:
#   vibe-cai                  # interactive Vibe session
#   vibe-cai --help           # Vibe help
#   vibe-cai --reconfigure    # change endpoint URL or JWT

set -Eeuo pipefail
IFS=$' \t\n'

INSTALL_ENV="${CAI_INSTALL_ENV:-${HOME}/.vibe/cai-inference/install.env}"
if [ ! -f "$INSTALL_ENV" ]; then
  printf 'ERROR: Not installed. Run install-cai-vibe.sh first.\n' >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$INSTALL_ENV"

CAI_HOME="${CAI_HOME:?}"
# shellcheck disable=SC1090
source "${CAI_HOME}/lib/cai-common.sh"

usage() {
  cat <<EOF
Usage: vibe-cai [vibe-args...]

Launch Mistral Vibe with Cloudera AI Inference (direct OpenAI-compatible API; no proxy).

  vibe-cai --reconfigure    Re-prompt for endpoint URL and JWT

Install / reinstall: ${CAI_INSTALL_SCRIPT:-install-cai-vibe.sh}
EOF
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --reconfigure)
      cai_load_config
      cai_prompt_user_config
      cai_log "Configuration saved to ${CONFIG_FILE}"
      exit 0
      ;;
  esac

  cai_load_config

  if [ -z "${CAI_API_BASE:-}" ] || [ -z "${CAI_CDP_TOKEN:-}" ]; then
    cai_prompt_user_config
  else
    CAI_API_BASE="$(cai_normalize_url "$CAI_API_BASE" "$CAI_CDP_TOKEN")"
  fi

  [ -n "$CAI_MODEL_NAME" ] || CAI_MODEL_NAME="$(cai_fetch_model_name "$CAI_API_BASE" "$CAI_CDP_TOKEN")"

  cai_launch_vibe "$@"
}

main "$@"
