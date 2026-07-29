#!/usr/bin/env bash
# /etc/profile.d/vibe-caii.sh
#
# Sourced on every interactive JupyterLab terminal in the CAI Runtime image.
# Configures Mistral Vibe to use Cloudera AI Inference (CAII) via env vars:
#
#   CAII_OPENAI_BASE_URL — OpenAI-compatible base URL including /v1
#                          (NIM: .../endpoints/<name>/v1 ; vLLM: .../openai/v1)
#   CAII_API_TOKEN       — Bearer token (CDP JWT); if unset, read access_token from /tmp/jwt
#   CAII_MODEL           — model id for chat/completions (GET /models or endpoint docs)
#   CAII_MODEL_ALIAS     — optional Vibe active_model alias (default: caii)
#   CAII_TEMPERATURE     — optional sampling temperature (default: 0.7)
#   VIBE_HOME            — Vibe config root (default: ~/.vibe/cai-inference)
#
# Run `vibe` as documented upstream — config is refreshed from env before each launch
# when CAII_* is set. Optional: vibe-sync-config (write config only, with status output).

[[ $- != *i* ]] && return

export VIBE_HOME="${VIBE_HOME:-${HOME}/.vibe/cai-inference}"
_VIBE_CONFIG="${VIBE_HOME}/config.toml"
_VIBE_TEMPLATE="/opt/cai-vibe/config/vibe-caii.config.toml.template"
_VIBE_BIN="$(command -v vibe 2>/dev/null || true)"

_vibe_caii_ensure_token() {
    if [[ -n "${CAII_API_TOKEN:-}" ]]; then
        return 0
    fi
    if [[ ! -r /tmp/jwt ]]; then
        return 1
    fi
    local token=""
    token="$(python3 -c 'import json; print(json.load(open("/tmp/jwt"))["access_token"])' 2>/dev/null)" || return 1
    if [[ -n "$token" ]]; then
        export CAII_API_TOKEN="$token"
    fi
}

_vibe_caii_env_ready() {
    _vibe_caii_ensure_token
    [[ -n "${CAII_OPENAI_BASE_URL}" && -n "${CAII_API_TOKEN}" && -n "${CAII_MODEL}" ]]
}

_vibe_write_config() {
    local base_url="${CAII_OPENAI_BASE_URL%/}"
    local alias="${CAII_MODEL_ALIAS:-caii}"
    local temp="${CAII_TEMPERATURE:-0.7}"

    mkdir -p "${VIBE_HOME}"
    umask 077

    if [[ -f "${_VIBE_TEMPLATE}" ]]; then
        sed \
            -e "s|@CAII_OPENAI_BASE_URL@|${base_url}|g" \
            -e "s|@CAII_MODEL@|${CAII_MODEL}|g" \
            -e "s|@CAII_MODEL_ALIAS@|${alias}|g" \
            -e "s|@CAII_TEMPERATURE@|${temp}|g" \
            "${_VIBE_TEMPLATE}" >"${_VIBE_CONFIG}"
    else
        cat >"${_VIBE_CONFIG}" <<EOF
# Generated for Mistral Vibe → Cloudera AI Inference
active_model = "${alias}"
enable_update_checks = false
narrator_enabled = false

[[providers]]
name = "caii"
api_base = "${base_url}"
api_key_env_var = "CAII_API_TOKEN"
backend = "generic"
api_style = "openai"

[[models]]
name = "${CAII_MODEL}"
provider = "caii"
alias = "${alias}"
temperature = ${temp}
thinking = "off"
supports_images = false
input_price = 0.0
output_price = 0.0
EOF
    fi

    chmod 600 "${_VIBE_CONFIG}"
}

_vibe_sync_config() {
    local verbose="${1:-0}"
    if ! _vibe_caii_env_ready; then
        echo "vibe-sync-config: set CAII_OPENAI_BASE_URL and CAII_MODEL; set CAII_API_TOKEN or provide /tmp/jwt." >&2
        return 1
    fi
    _vibe_write_config
    if [[ "$verbose" == "1" ]]; then
        echo "Wrote ${_VIBE_CONFIG} (provider caii, model ${CAII_MODEL}, alias ${CAII_MODEL_ALIAS:-caii})."
        echo "API token is read from env CAII_API_TOKEN (not written to disk)."
    fi
}

vibe-sync-config() {
    _vibe_sync_config 1
}

vibe() {
    if [[ -z "${_VIBE_BIN}" ]]; then
        echo "vibe: CLI not installed." >&2
        return 127
    fi
    if _vibe_caii_env_ready; then
        _vibe_sync_config 0 || return 1
    fi
    command vibe "$@"
}

_vibe_banner() {
    echo ""
    echo "┌─ Mistral Vibe + Cloudera AI Inference ──────────────────────────────────┐"
    if [[ -n "${_VIBE_BIN}" ]]; then
        echo "│  ✓ vibe: ${_VIBE_BIN} ($(${_VIBE_BIN} --version 2>/dev/null | head -1 || echo ''))"
    else
        echo "│  ✗ vibe CLI not found"
    fi
    if _vibe_caii_env_ready; then
        echo "│  ✓ CAII env set (model: ${CAII_MODEL})"
        echo "│  → Run: vibe"
    else
        echo "│  ○ Set CAII_OPENAI_BASE_URL and CAII_MODEL; set CAII_API_TOKEN or use /tmp/jwt"
        echo "│    then: vibe"
    fi
    echo "│  VIBE_HOME=${VIBE_HOME}"
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

_vibe_banner
