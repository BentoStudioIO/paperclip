# Pharmia agent runtime — the deterministic Coder workspace base image.
#
# Bakes a ZERO-CREDS engineering environment: node 24 + bun + uv toolchain, the Bento CLI
# toolkit (SSOT = templates/pharmia/cli), the research toolkit (gh/gitleaks/oha/bx/logcli/
# ovhcloud/curl_cffi), the coding agents (claude-code + codex), and the TEAM engineering
# agents + skills (rendered from templates/pharmia/{agents,skills}). Credentials are NOT
# baked — prod access is granted out-of-band per-identity, never via this image.
#
# Browsers are intentionally SKIPPED here (WITH_BROWSERS unset) to keep the Coder workspace
# image lean — dev workspaces don't need Camoufox/Chromium e2e.
#
# THE HOME-VOLUME SHADOWING PROBLEM: Coder mounts a per-user volume at /home/coder, which
# SHADOWS anything baked under /home/coder. So the team agents/skills are baked into a
# NON-HOME path (/opt/bento/claude-config/{agents,skills,rules}); the Coder template's
# startup script idempotently syncs that into $HOME/.claude on workspace start.
#
# Build (context = templates/pharmia so cli/ + rendered .claude-config-staging are in scope):
#   # 1) render the team agents/skills into the build context (deterministic from SSOT):
#   #    see agent-runtime/build.sh — it renders then builds.
#   docker build --platform linux/amd64 \
#     -f templates/pharmia/agent-runtime/Dockerfile \
#     -t git.bentostudio.io/bentostudio/pharmia-agent-runtime:1.0.0 templates/pharmia
FROM node:24-bookworm-slim

# Run the SSOT provisioner: installs toolchain + pinned binaries + Bento CLI toolkit +
# claude-code + codex. WITH_BROWSERS unset → no Camoufox/Chromium (lean Coder image).
# sudo is needed by provision.sh's apt/install steps even though we run it as root here
# (it no-ops SUDO when uid 0); we install it first so the script's `$SUDO` is harmless.
RUN apt-get update && apt-get install -y --no-install-recommends sudo ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# The Bento CLI toolkit source (symlink targets must persist in the image — install.sh
# symlinks /usr/local/bin/<tool> -> /opt/bento-cli/bin/<tool>). provision.sh reads it via
# PHARMIA_DIR/cli, so place the whole templates/pharmia tree where the script expects it:
# SCRIPT_DIR=/opt/bento/templates/pharmia/agent-runtime, PHARMIA_DIR=/opt/bento/templates/pharmia.
COPY cli /opt/bento/templates/pharmia/cli
COPY rules /opt/bento/templates/pharmia/rules
COPY agent-runtime/provision.sh /opt/bento/templates/pharmia/agent-runtime/provision.sh
RUN chmod +x /opt/bento/templates/pharmia/agent-runtime/provision.sh \
    && CLI_INSTALL_DIR=/usr/local/bin NODE_MAJOR=24 \
       bash /opt/bento/templates/pharmia/agent-runtime/provision.sh

# Bake the TEAM engineering agents + skills + rules into a NON-HOME path so the Coder
# per-user home volume can't shadow them. Rendered from the paperclip SSOT at build time
# (agent-runtime/build.sh runs scripts/sync-claude-{agents,skills}.mjs into this staging dir).
COPY agent-runtime/.claude-config-staging /opt/bento/claude-config
# The env-bindings rule the agents reference (SSOT = templates/pharmia/rules).
RUN cp -f /opt/bento/templates/pharmia/rules/*.md /opt/bento/claude-config/rules/ 2>/dev/null || true

# Non-root `coder` user with PASSWORDLESS sudo INSIDE the container (safe: the container is
# isolated, no host mounts, no host root). git/bash/curl/openssh-client come from provision.sh.
RUN useradd -m -s /bin/bash coder \
    && echo 'coder ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder \
    && chown -R coder:coder /opt/bento/claude-config
USER coder
WORKDIR /home/coder

# Injected at runtime per-identity (NOT baked): GITHUB/Forgejo auth, ANTHROPIC_API_KEY,
# BRAVE_SEARCH_API_KEY, LOKI_* tokens, PG_* (dev/qa rw; canary READ-ONLY), AUTUMN_*,
# ~/.config/<tool>/ for ol/langfuse/twenty/comp/dokploy. Ops agents whose CLIs need creds
# are inert without them — that is the intended zero-creds guardrail.
CMD ["bash"]
