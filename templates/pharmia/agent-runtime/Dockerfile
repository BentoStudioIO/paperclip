# Pharmia agent runtime — the deterministic image Daytona uses as its snapshot.
# Bakes: toolchain + the Bento CLI toolkit (SSOT) + the coding agents + the research
# toolkit (gh/gitleaks/oha/bx/curl_cffi) + two browser engines (Camoufox=scraping,
# Chromium/Playwright=e2e). Credentials are NOT baked — injected at runtime (env today,
# Vaultwarden later): dev/qa read-write + prod read-only + comp read-write + BRAVE_SEARCH_API_KEY
# (see README.md "Injected at runtime").
#
# Sandbox caps (daytona-compose.yml): 15 GB disk / 4 GB RAM per sandbox. This image is
# ~2.5 GB; the two browser engines are intentional but must NOT both run heavy in parallel.
#
# Build (context = templates/pharmia so the CLI toolkit + vendored camofox source are in scope):
#   docker build -f templates/pharmia/agent-runtime/Dockerfile -t pharmia-agent-runtime templates/pharmia
FROM node:22-bookworm-slim

# System deps: CLI toolkit + Pharmia dev loop (clone/typecheck/test/push) + Camoufox/Firefox
# runtime libs + Xvfb (Camoufox uses a virtual display for full anti-detection) + fonts.
# No docker-in-docker: the agent ships to the dev env via push, it doesn't run the full
# stack locally — add it later only if an agent needs `docker:dev` in-sandbox.
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl jq git openssh-client postgresql-client ca-certificates \
      python3 python3-pip ripgrep less unzip \
      libgtk-3-0 libdbus-glib-1-2 libxt6 libasound2 libx11-xcb1 libxcomposite1 \
      libxcursor1 libxdamage1 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 \
      libxtst6 libegl1-mesa libgl1-mesa-dri libgbm1 xvfb \
      libx11-6 libxext6 libxinerama1 \
      fonts-liberation fonts-noto-color-emoji fontconfig \
    && rm -rf /var/lib/apt/lists/*
# NOTE: libx11-6 (libX11.so.6) + libxext6 + libxinerama1 are required by the Daytona
# daemon's computer-use plugin. Without libX11.so.6 the toolbox server fails to bind on
# :2280, so the runner's daemon-wait times out and NO sandbox can start from this snapshot
# ("timeout waiting for daemon to start"). The other X11 libs above were for Camoufox/Chromium.

# --- Static research binaries (pinned; URLs validated 2026-06-08) ------------------------
ARG GH_VERSION=2.93.0
ARG GITLEAKS_VERSION=8.30.1
ARG OHA_VERSION=1.14.0
ARG BX_VERSION=1.5.0
ARG LOKI_VERSION=3.7.2
RUN set -eux; \
    curl -fSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh"; \
    curl -fSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
      | tar -xz -C /usr/local/bin gitleaks; \
    curl -fSL -o /usr/local/bin/oha "https://github.com/hatoo/oha/releases/download/v${OHA_VERSION}/oha-linux-amd64"; \
    curl -fSL -o /usr/local/bin/bx "https://github.com/brave/brave-search-cli/releases/download/v${BX_VERSION}/bx-${BX_VERSION}-linux-amd64"; \
    curl -fSL -o /usr/local/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"; \
    curl -fSL -o /tmp/logcli.zip "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/logcli-linux-amd64.zip"; \
    unzip -q /tmp/logcli.zip -d /tmp && mv /tmp/logcli-linux-amd64 /usr/local/bin/logcli && rm -f /tmp/logcli.zip; \
    chmod +x /usr/local/bin/gh /usr/local/bin/gitleaks /usr/local/bin/oha /usr/local/bin/bx /usr/local/bin/yt-dlp /usr/local/bin/logcli; \
    gh --version; gitleaks version; oha --version; logcli --version

# curl_cffi — TLS-fingerprint-forging HTTP client (bypass WAF). bookworm is PEP-668-managed.
RUN pip3 install --no-cache-dir --break-system-packages curl_cffi==0.13.0

# --- Browser engine 1: Camoufox (anti-detect Firefox; agent-browser delegates to camofox) ---
# Pre-bake the pinned Camoufox binary so the runtime never fetches it (and camofox-js's
# postinstall fetch can be skipped during `npm ci`). unzip exits 1 on Unicode-name warnings.
ARG CAMOUFOX_VERSION=135.0.1
ARG CAMOUFOX_RELEASE=beta.24
RUN set -eux; \
    mkdir -p /home/agent/.cache/camoufox; \
    curl -fSL -o /tmp/camoufox.zip \
      "https://github.com/daijro/camoufox/releases/download/v${CAMOUFOX_VERSION}-${CAMOUFOX_RELEASE}/camoufox-${CAMOUFOX_VERSION}-${CAMOUFOX_RELEASE}-lin.x86_64.zip"; \
    (unzip -q /tmp/camoufox.zip -d /home/agent/.cache/camoufox || true); \
    rm -f /tmp/camoufox.zip; \
    test -f /home/agent/.cache/camoufox/camoufox-bin; \
    printf '{"version":"%s","release":"%s"}\n' "${CAMOUFOX_VERSION}" "${CAMOUFOX_RELEASE}" \
      > /home/agent/.cache/camoufox/version.json

# Vendored camofox-browser server (MIT @askjo/camofox-browser@1.5.2; LICENSE kept). The
# camofox CLI wrapper (in the toolkit) launches `node server.js`; ENV CAMOFOX_DIR points it here.
COPY agent-runtime/camofox-browser /opt/camofox-browser
RUN cd /opt/camofox-browser && npm_config_ignore_scripts=true npm ci --omit=dev
ENV CAMOFOX_DIR=/opt/camofox-browser

# --- Coding agents + browser engine 2: Playwright/Chromium (e2e) -------------------------
# Playwright pinned to the version PharmaMate resolves (package-lock.json → 1.60.0); a mismatch
# would download a second browser build. `playwright install --with-deps` runs apt → must be root.
RUN npm install -g @anthropic-ai/claude-code @openai/codex playwright@1.60.0
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
RUN npx playwright install --with-deps chromium

# The Bento/Pharmia CLI toolkit (source of truth = this repo's templates/pharmia/cli).
COPY cli /opt/bento-cli
RUN CLI_INSTALL_DIR=/usr/local/bin sh /opt/bento-cli/install.sh

# Baked env-bindings the agents reference at /home/agent/.claude/rules (SSOT = templates/pharmia/rules).
COPY rules /home/agent/.claude/rules

# Non-root agent user; work happens under /home/agent (per-issue worktree at runtime).
RUN useradd -m -s /bin/bash agent \
    && chown -R agent:agent /opt/camofox-browser /home/agent /ms-playwright
USER agent
WORKDIR /home/agent

# Injected at runtime by Daytona/Paperclip (NOT baked):
#   GITHUB_APP_* (or a git token), ANTHROPIC_API_KEY, BRAVE_SEARCH_API_KEY (for `bx`),
#   LOKI_{DEV,QA,CANARY}_TOKEN, PG_{DEV,QA}_* (rw) + PG_CANARY_* (READ-ONLY role),
#   AUTUMN_SECRET_KEY (LIVE am_sk_live — billing, for real MRR via `autumn`) + AUTUMN_URL,
#   ~/.config/<tool>/ for ol, langfuse, twenty, comp (read-write), dokploy (bento dev/qa only).
# `autumn` reads AUTUMN_SECRET_KEY from env (precedence over ~/.config/autumn/config). NOTE: the
# live key is billing READ-WRITE (customer:create/delete) — agents use read commands only (customers,
# customer <id>, products) to compute MRR/active-subs/churn for the growth dept's market-intel.
# Workflow: clone PharmaMate → `npm install` (arms the .husky CONFIRM hook) → per-issue
# worktree → push dev/qa freely; main/canary blocked by the hook (agents never set CONFIRM_DEPLOY).
CMD ["bash"]
