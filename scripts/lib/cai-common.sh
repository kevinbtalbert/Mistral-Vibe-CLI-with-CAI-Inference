#!/usr/bin/env bash
# cai-common.sh — shared helpers for CAI Inference + Mistral Vibe CLI.
# Sourced by install-cai-vibe.sh and vibe-cai-launch.sh. Do not execute directly.

: "${CAI_HOME:?CAI_HOME must be set before sourcing cai-common.sh}"

CONFIG_FILE="${CAI_CONFIG_FILE:-${CAI_HOME}/cai-inference.conf}"
VIBE_CONFIG="${CAI_VIBE_CONFIG:-${CAI_HOME}/config.toml}"
VIBE_ENV_FILE="${CAI_VIBE_ENV:-${CAI_HOME}/.env}"
CAI_MODEL_ALIAS="${CAI_MODEL_ALIAS:-cai}"

CAI_API_BASE="${CAI_API_BASE:-}"
CAI_MODEL_NAME="${CAI_MODEL_NAME:-}"
CAI_CDP_TOKEN="${CAI_CDP_TOKEN:-}"

cai_log() { printf '%s\n' "$*" >&2; }
cai_die() { cai_log "ERROR: $*"; exit 1; }

cai_is_interactive() {
  [ -t 0 ] && [ -t 1 ] && [ -z "${CAI_NONINTERACTIVE:-}" ]
}

cai_have_cmd() { command -v "$1" >/dev/null 2>&1; }

cai_prompt_default() {
  local __var="$1" __prompt="$2" __default="$3" __reply=""
  if ! cai_is_interactive; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi
  printf '%s [%s]: ' "$__prompt" "$__default" >&2
  read -r __reply || __reply=""
  if [ -z "$__reply" ]; then __reply="$__default"; fi
  printf -v "$__var" '%s' "$__reply"
}

cai_trim_token() {
  printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

JWT_FILE="${CAI_JWT_FILE:-${CAI_HOME}/jwt.txt}"

cai_drain_tty_line() {
  local c=""
  while IFS= read -r -n 1 -t 0.05 c </dev/tty 2>/dev/null; do
    [ -z "$c" ] && break
  done
}

cai_press_enter_only() {
  local key=""
  while true; do
    IFS= read -r -n 1 key </dev/tty 2>/dev/null || IFS= read -r -n 1 key || key=""
    if [ -z "$key" ]; then
      printf '\n' >&2
      cai_drain_tty_line
      return 0
    fi
    cai_log "Press Enter only — do not paste the JWT into this terminal."
    cai_drain_tty_line
  done
}

cai_read_single_key() {
  local __var="$1" __prompt="$2" key=""
  printf '%s' "$__prompt" >&2
  IFS= read -r -n 1 key </dev/tty 2>/dev/null || IFS= read -r -n 1 key || key=""
  printf '\n' >&2
  cai_drain_tty_line
  printf -v "$__var" '%s' "$key"
}

cai_read_jwt_from_clipboard() {
  local __var="$1" raw=""
  if command -v pbpaste >/dev/null 2>&1; then
    raw="$(pbpaste 2>/dev/null || true)"
  elif command -v wl-paste >/dev/null 2>&1; then
    raw="$(wl-paste -n 2>/dev/null || wl-paste 2>/dev/null || true)"
  elif command -v xclip >/dev/null 2>&1; then
    raw="$(xclip -selection clipboard -o 2>/dev/null || true)"
  else
    return 1
  fi

  raw="$(cai_trim_token "$raw")"
  [ -n "$raw" ] || return 1
  printf -v "$__var" '%s' "$raw"
  return 0
}

cai_read_jwt_from_file() {
  local __var="$1" raw=""
  [ -s "$JWT_FILE" ] || return 1
  raw="$(cai_trim_token "$(cat "$JWT_FILE")")"
  rm -f "$JWT_FILE"
  [ -n "$raw" ] || return 1
  printf -v "$__var" '%s' "$raw"
  return 0
}

cai_prompt_jwt_via_file() {
  local __var="$1" token=""
  umask 077
  : >"$JWT_FILE" || cai_die "Cannot create ${JWT_FILE}"
  chmod 600 "$JWT_FILE"
  cai_log ""
  cai_log "Paste your JWT into this file (not the terminal):"
  cai_log "  ${JWT_FILE}"
  cai_log ""
  if cai_have_cmd cursor; then
    cursor "$JWT_FILE" >/dev/null 2>&1 &
  elif cai_have_cmd code; then
    code "$JWT_FILE" >/dev/null 2>&1 &
  elif [ -n "${EDITOR:-}" ]; then
    # shellcheck disable=SC2086
    $EDITOR "$JWT_FILE" >/dev/null 2>&1 &
  fi
  cai_log "Open the file in your editor, paste the full token, save, then press Enter here."
  cai_press_enter_only
  cai_read_jwt_from_file token || cai_die "No JWT in ${JWT_FILE}. Paste token, save, then try again."
  cai_log "JWT loaded (${#token} characters)."
  printf -v "$__var" '%s' "$token"
}

cai_prompt_secret_default() {
  local __var="$1" __prompt="$2" __default="$3" token="" choice=""
  if ! cai_is_interactive; then
    printf -v "$__var" '%s' "$__default"
    return 0
  fi

  cai_log ""
  cai_log "${__prompt}"
  cai_log "This terminal cannot accept long JWTs (~1KB line limit). Never paste the token here."
  if [ -n "$__default" ]; then
    cai_log "  Enter  keep saved token"
    cai_log "  r      replace from clipboard (Cmd+C first)"
    cai_log "  f      paste into a file instead (recommended in Cursor)"
    cai_read_single_key choice "Choice [Enter/r/f]: "
    if [ -z "$choice" ]; then
      printf -v "$__var" '%s' "$__default"
      return 0
    fi
    choice="$(printf '%s' "$choice" | tr '[:upper:]' '[:lower:]')"
    if [ "$choice" = "f" ]; then
      cai_prompt_jwt_via_file token
      printf -v "$__var" '%s' "$token"
      return 0
    fi
    if [ "$choice" != "r" ]; then
      cai_log "Unrecognized choice — loading new token."
    fi
  else
    cai_log "  Enter  load from clipboard (Cmd+C first)"
    cai_log "  f      paste into a file instead (recommended in Cursor)"
    cai_read_single_key choice "Choice [Enter/f]: "
    if [ "$choice" = "f" ] || [ "$choice" = "F" ]; then
      cai_prompt_jwt_via_file token
      printf -v "$__var" '%s' "$token"
      return 0
    fi
  fi

  cai_log "Copy JWT to clipboard (Cmd+C), then press Enter."
  cai_press_enter_only
  if cai_read_jwt_from_clipboard token; then
    cai_log "JWT loaded (${#token} characters)."
  elif [ -n "$__default" ]; then
    cai_log "Clipboard empty — keeping saved token."
    token="$__default"
  else
    cai_die "Could not read JWT. Press f for file method, or set CAI_CDP_TOKEN."
  fi

  [ -n "$token" ] || cai_die "JWT is empty."
  printf -v "$__var" '%s' "$token"
}

cai_shell_quote() {
  local q
  printf -v q '%q' "$1"
  printf '%s' "$q"
}

cai_load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    set -a
    source "$CONFIG_FILE"
    set +a
  fi
  CAI_API_BASE="${CAI_API_BASE:-}"
  CAI_MODEL_NAME="${CAI_MODEL_NAME:-}"
  CAI_CDP_TOKEN="${CAI_CDP_TOKEN:-${CDP_TOKEN:-}}"
  CAI_MODEL_ALIAS="${CAI_MODEL_ALIAS:-cai}"
}

cai_save_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  umask 077
  cat >"$CONFIG_FILE" <<EOF
# Cloudera AI Inference — saved by install-cai-vibe.sh / vibe-cai
CAI_API_BASE=$(cai_shell_quote "$CAI_API_BASE")
CAI_MODEL_NAME=$(cai_shell_quote "$CAI_MODEL_NAME")
CAI_CDP_TOKEN=$(cai_shell_quote "$CAI_CDP_TOKEN")
CAI_MODEL_ALIAS=$(cai_shell_quote "$CAI_MODEL_ALIAS")
EOF
  chmod 600 "$CONFIG_FILE"
}

cai_normalize_url() {
  local url="$1"
  local token="$2"
  url="${url%/}"

  case "$url" in
    */openai/v1|*/v1)
      printf '%s' "$url"
      return 0
      ;;
  esac

  local try_openai="${url}/openai/v1"
  local try_v1="${url}/v1"
  if curl -sf -o /dev/null --connect-timeout 8 --max-time 15 \
    -H "Authorization: Bearer ${token}" "${try_openai}/models" 2>/dev/null; then
    printf '%s' "$try_openai"
    return 0
  fi
  if curl -sf -o /dev/null --connect-timeout 8 --max-time 15 \
    -H "Authorization: Bearer ${token}" "${try_v1}/models" 2>/dev/null; then
    printf '%s' "$try_v1"
    return 0
  fi

  cai_die "Could not reach ${url}. Expected .../v1 (NIM) or .../openai/v1 (vLLM). Check URL and token."
}

cai_detect_endpoint_kind() {
  case "$1" in
    */openai/v1) printf 'vllm' ;;
    */v1) printf 'nim' ;;
    *) printf 'unknown' ;;
  esac
}

cai_fetch_model_name() {
  local base="$1" token="$2"
  local body
  body="$(curl -sf --connect-timeout 8 --max-time 20 \
    -H "Authorization: Bearer ${token}" \
    "${base}/models")" || cai_die "GET ${base}/models failed — check token and URL."

  if cai_have_cmd python3; then
    printf '%s' "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["data"][0]["id"])'
    return 0
  fi
  if cai_have_cmd jq; then
    jq -r '.data[0].id // empty' <<<"$body"
    return 0
  fi
  cai_die "Need python3 or jq to parse /models response."
}

cai_validate_connection() {
  local base="$1" token="$2"
  curl -sf --connect-timeout 8 --max-time 20 \
    -H "Authorization: Bearer ${token}" \
    "${base}/models" >/dev/null \
    || cai_die "Connection test failed for ${base}/models"
}

cai_write_vibe_env() {
  mkdir -p "$(dirname "$VIBE_ENV_FILE")"
  umask 077
  cat >"$VIBE_ENV_FILE" <<EOF
# Generated by vibe-cai — CDP JWT for CAI Inference (Bearer token)
CAI_CDP_TOKEN=$(cai_shell_quote "$CAI_CDP_TOKEN")
EOF
  chmod 600 "$VIBE_ENV_FILE"
}

cai_write_vibe_config() {
  mkdir -p "$(dirname "$VIBE_CONFIG")"
  umask 077
  cat >"$VIBE_CONFIG" <<EOF
# Generated by vibe-cai — Mistral Vibe → Cloudera AI Inference (OpenAI-compatible)
active_model = "${CAI_MODEL_ALIAS}"
enable_update_checks = false
narrator_enabled = false

[[providers]]
name = "cai"
api_base = "${CAI_API_BASE}"
api_key_env_var = "CAI_CDP_TOKEN"
backend = "generic"
api_style = "openai"

[[models]]
name = "${CAI_MODEL_NAME}"
provider = "cai"
alias = "${CAI_MODEL_ALIAS}"
temperature = 0.7
thinking = "off"
supports_images = false
input_price = 0.0
output_price = 0.0
EOF
  chmod 600 "$VIBE_CONFIG"
}

cai_sync_vibe_files() {
  cai_write_vibe_env
  cai_write_vibe_config
}

cai_prompt_user_config() {
  local default_url="${CAI_API_BASE:-}"
  local default_token="${CAI_CDP_TOKEN:-}"
  local default_model="${CAI_MODEL_NAME:-}"
  local input_url input_token endpoint_kind

  if cai_is_interactive; then
    cai_log ""
    cai_log "Mistral Vibe + Cloudera AI Inference — configuration"
    cai_log "Press Enter to keep saved values in [brackets], or enter new ones."
    cai_log ""
  fi

  cai_prompt_default input_url "CAI endpoint URL (from Model Endpoint Code Sample)" "$default_url"
  cai_prompt_secret_default input_token "CDP JWT / API token" "$default_token"

  [ -n "$input_url" ] || cai_die "Endpoint URL is required."
  [ -n "$input_token" ] || cai_die "CDP token is required."

  cai_log "Checking endpoint (may take a few seconds) ..."
  CAI_API_BASE="$(cai_normalize_url "$input_url" "$input_token")"
  endpoint_kind="$(cai_detect_endpoint_kind "$CAI_API_BASE")"
  cai_log "Endpoint type: ${endpoint_kind} (${CAI_API_BASE})"

  if [ -n "$default_model" ]; then
    cai_prompt_default CAI_MODEL_NAME "Model name (from GET /models if unsure)" "$default_model"
  else
    cai_log "Discovering model from GET /models ..."
    CAI_MODEL_NAME="$(cai_fetch_model_name "$CAI_API_BASE" "$input_token")"
    cai_log "Using model: ${CAI_MODEL_NAME}"
  fi

  CAI_CDP_TOKEN="$input_token"
  cai_save_config
  cai_sync_vibe_files
}

cai_ensure_vibe() {
  cai_have_cmd vibe || cai_die "Mistral Vibe not installed. Run: ./scripts/install-cai-vibe.sh"
}

cai_launch_vibe() {
  cai_ensure_vibe
  export VIBE_HOME="$CAI_HOME"
  export CAI_CDP_TOKEN
  cai_sync_vibe_files

  cai_log ""
  cai_log "Launching Mistral Vibe → CAI (${CAI_MODEL_NAME} at ${CAI_API_BASE})"
  cai_log "VIBE_HOME=${CAI_HOME}"
  cai_log ""

  if [ $# -gt 0 ]; then
    exec vibe "$@"
  else
    exec vibe
  fi
}
