# Cloudera ML runtime + Mistral Vibe CLI → Cloudera AI Inference (OpenAI-compatible API)
FROM --platform=linux/amd64 docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-jupyterlab-python3.13-standard:2026.04.2-b16

# ── System dependencies (agent tooling) ────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        vim nano \
        tmux screen \
        curl wget less tree jq unzip zip \
        ripgrep fd-find bat \
        netcat-openbsd dnsutils iputils-ping \
        pciutils htop procps lsof strace \
        ssh-client rsync socat ca-certificates git \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# ── Mistral Vibe CLI (https://github.com/mistralai/mistral-vibe) ───────────
RUN pip3 install --no-cache-dir 'mistral-vibe>=2.23,<3' \
    && command -v vibe >/dev/null

# ── ttyd: browser-based terminal (optional; CML may wire APP_PORT) ─────────
RUN TTYD_URL=$(curl -s https://api.github.com/repos/tsl0922/ttyd/releases/latest \
        | grep '"browser_download_url"' \
        | grep 'ttyd\.x86_64"' \
        | head -1 \
        | cut -d'"' -f4) && \
    curl -fsSL "$TTYD_URL" -o /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# ── Runtime directories ────────────────────────────────────────────────────
RUN mkdir -p /home/cdsw/.vibe/cai-inference /opt/cai-vibe/config && \
    chown -R cdsw:cdsw /home/cdsw/.vibe

COPY config/vibe-caii.config.toml.template /opt/cai-vibe/config/vibe-caii.config.toml.template
COPY scripts/cai-runtime-startup.sh /etc/profile.d/vibe-caii.sh
RUN chmod +x /etc/profile.d/vibe-caii.sh && \
    echo '[ -f /etc/profile.d/vibe-caii.sh ] && source /etc/profile.d/vibe-caii.sh' \
        >> /etc/bash.bashrc

# ── Default environment (override in CML project / session settings) ───────
ENV VIBE_HOME="/home/cdsw/.vibe/cai-inference" \
    CAII_OPENAI_BASE_URL="" \
    CAII_API_TOKEN="" \
    CAII_MODEL="" \
    CAII_MODEL_ALIAS="caii" \
    CAII_TEMPERATURE="0.7" \
    APP_PORT="8080"

EXPOSE 8080
WORKDIR /home/cdsw


ENV ML_RUNTIME_EDITION="Mistral Vibe"
LABEL com.cloudera.ml.runtime.edition=$ML_RUNTIME_EDITION