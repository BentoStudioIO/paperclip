#!/usr/bin/env bash
# Pharmia agent-runtime provisioner — the SINGLE source of truth for installing the
# toolchain + pinned binaries + coding agents + the Bento CLI toolkit.
#
# Used by BOTH:
#   - the agent-runtime Dockerfile (RUN sh provision.sh), and
#   - host bare-metal (the shared agent VPS): `sudo bash provision.sh`
#
# Idempotent + re-runnable. Custom wrapper CLIs are installed via cli/install.sh and stay
# synced on every `git pull` through the repo's .githooks (post-merge/post-checkout) — so a
# clone + pull keeps them on PATH automatically. This script also wires those hooks.
#
# Flags (env):
#   CLI_INSTALL_DIR   where wrapper CLIs + binaries go (default /usr/local/bin)
#   WITH_BROWSERS=1   also install Camoufox + Playwright/Chromium + X11/Xvfb deps (heavy ~3GB)
#   WITH_CODE_SERVER=1  install code-server (browser VS Code), bound to localhost
#   NODE_MAJOR        node major to install if absent (default 22)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../templates/pharmia/agent-runtime
PHARMIA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                       # .../templates/pharmia
REPO_DIR="$(cd "$PHARMIA_DIR/../.." && pwd)"                      # paperclip repo root
: "${CLI_INSTALL_DIR:=/usr/local/bin}"
: "${NODE_MAJOR:=24}"
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
export DEBIAN_FRONTEND=noninteractive

# Pinned versions (URLs validated 2026-06-08; bump together with the Dockerfile ARGs).
GH_VERSION=2.93.0; GITLEAKS_VERSION=8.30.1; OHA_VERSION=1.14.0; BX_VERSION=1.5.0; LOKI_VERSION=3.7.2
FILEBROWSER_VERSION=2.63.14

say(){ printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }

# 1) Base apt deps (the toolkit + dev loop need these) -------------------------------------
say "apt: base deps"
$SUDO apt-get update -qq
$SUDO apt-get install -y --no-install-recommends \
  bash curl jq git openssh-client postgresql-client ca-certificates \
  python3 python3-pip ripgrep less unzip xz-utils bzip2 build-essential \
  tmux screen
if [ "${WITH_BROWSERS:-0}" = "1" ]; then
  say "apt: browser/X11 runtime deps (resilient: Debian bookworm + Ubuntu 24.04 noble t64)"
  # Names common to bookworm + noble (best-effort; do not abort the whole provisioner):
  $SUDO apt-get install -y --no-install-recommends \
    libdbus-glib-1-2 libx11-xcb1 libxcomposite1 libxcursor1 libxdamage1 \
    libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 \
    libgl1-mesa-dri libgbm1 xvfb fonts-liberation fonts-noto-color-emoji fontconfig || true
  # t64-renamed on Ubuntu 24.04 (noble): try the noble name, fall back to the bookworm name.
  apt_one(){ for p in "$@"; do $SUDO apt-get install -y --no-install-recommends "$p" >/dev/null 2>&1 && return 0; done; echo "WARN: browser dep unavailable (tried: $*)"; }
  apt_one libasound2t64 libasound2
  apt_one libgtk-3-0t64 libgtk-3-0
  apt_one libxt6t64 libxt6
  apt_one libegl1 libegl1-mesa
fi

# 2) Node (install only if absent — the Docker base image already ships it) ----------------
if ! command -v node >/dev/null 2>&1; then
  say "node: installing NodeSource ${NODE_MAJOR}.x (system-wide)"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | $SUDO bash -
  $SUDO apt-get install -y nodejs
fi
say "node $(node -v) / npm $(npm -v)"
command -v corepack >/dev/null 2>&1 && $SUDO corepack enable 2>/dev/null || true

# bun + uv (system-wide), idempotent
if ! command -v bun >/dev/null 2>&1; then
  say "bun: install"; curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash || true
fi
if ! command -v uv >/dev/null 2>&1; then
  say "uv: install"; curl -fsSL https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin $SUDO sh || true
fi

# 3) Pinned static binaries → CLI_INSTALL_DIR ---------------------------------------------
say "binaries: gh gitleaks oha bx logcli yt-dlp ovhcloud"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
dl(){ curl -fSL "$1" -o "$2"; }
# gh
dl "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" "$tmp/gh.tgz"
tar -xzf "$tmp/gh.tgz" -C "$tmp" --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh"; $SUDO install -m755 "$tmp/gh" "$CLI_INSTALL_DIR/gh"
# gitleaks
dl "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "$tmp/gl.tgz"
tar -xzf "$tmp/gl.tgz" -C "$tmp" gitleaks; $SUDO install -m755 "$tmp/gitleaks" "$CLI_INSTALL_DIR/gitleaks"
# oha, bx, yt-dlp (single-file binaries)
dl "https://github.com/hatoo/oha/releases/download/v${OHA_VERSION}/oha-linux-amd64" "$tmp/oha"; $SUDO install -m755 "$tmp/oha" "$CLI_INSTALL_DIR/oha"
dl "https://github.com/brave/brave-search-cli/releases/download/v${BX_VERSION}/bx-${BX_VERSION}-linux-amd64" "$tmp/bx"; $SUDO install -m755 "$tmp/bx" "$CLI_INSTALL_DIR/bx"
dl "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux" "$tmp/yt-dlp"; $SUDO install -m755 "$tmp/yt-dlp" "$CLI_INSTALL_DIR/yt-dlp"
# logcli (zip)
dl "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/logcli-linux-amd64.zip" "$tmp/logcli.zip"
unzip -qo "$tmp/logcli.zip" -d "$tmp"; $SUDO install -m755 "$tmp/logcli-linux-amd64" "$CLI_INSTALL_DIR/logcli"
# ovhcloud (official OVH CLI) — latest release; asset is a tarball ovhcloud-cli_Linux_x86_64.tar.gz
OVH_URL="$(curl -fsSL https://api.github.com/repos/ovh/ovhcloud-cli/releases/latest | jq -r '.assets[]|select(.name|test("Linux_x86_64\\.tar\\.gz$"))|.browser_download_url' | head -1)"
if [ -n "${OVH_URL:-}" ] && [ "$OVH_URL" != "null" ]; then
  dl "$OVH_URL" "$tmp/ovhcloud.tgz"; tar -xzf "$tmp/ovhcloud.tgz" -C "$tmp"
  ovhbin="$(find "$tmp" -maxdepth 3 -type f \( -name 'ovhcloud-cli' -o -name 'ovhcloud' \) | head -1)"
  if [ -n "$ovhbin" ]; then $SUDO install -m755 "$ovhbin" "$CLI_INSTALL_DIR/ovhcloud"; else echo "WARN: ovhcloud binary not found in tarball"; fi
else echo "WARN: could not resolve ovhcloud release URL — skipping"; fi

# 4) curl_cffi (TLS-fingerprint HTTP client; bookworm/noble are PEP-668 managed) ----------
say "pip: curl_cffi"
$SUDO pip3 install --no-cache-dir --break-system-packages "curl_cffi==0.13.0" || true

# 5) Coding agents — baked so Coder workspace modules start instantly with install_* = false
#    (zero-creds: every agent is installed UN-credentialed; each dev authenticates themselves)
say "npm -g: claude-code + codex + opencode + gemini-cli + amp"
$SUDO npm install -g @anthropic-ai/claude-code @openai/codex opencode-ai @google/gemini-cli @sourcegraph/amp

# goose (Block's CLI agent) — static binary; CONFIGURE=false keeps it non-interactive
if ! command -v goose >/dev/null 2>&1; then
  say "goose: install → $CLI_INSTALL_DIR"
  curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh \
    | $SUDO env CONFIGURE=false GOOSE_BIN_DIR="$CLI_INSTALL_DIR" bash || true
fi

# filebrowser (web file manager, served per-workspace by the Coder filebrowser module)
if ! command -v filebrowser >/dev/null 2>&1; then
  say "filebrowser: install v${FILEBROWSER_VERSION} → $CLI_INSTALL_DIR"
  dl "https://github.com/filebrowser/filebrowser/releases/download/v${FILEBROWSER_VERSION}/linux-amd64-filebrowser.tar.gz" "$tmp/fb.tgz"
  tar -xzf "$tmp/fb.tgz" -C "$tmp" filebrowser && $SUDO install -m755 "$tmp/filebrowser" "$CLI_INSTALL_DIR/filebrowser"
fi

# cursor-agent (Cursor's CLI agent) — installer is $HOME-relative, so bake under /opt and
# symlink onto PATH. Self-update is read-only for non-root (sudo available in workspaces).
if ! command -v cursor-agent >/dev/null 2>&1; then
  say "cursor-agent: install → /opt/cursor-agent"
  { $SUDO env HOME=/opt/cursor-agent bash -c 'curl -fsS https://cursor.com/install | bash' \
    && $SUDO chmod -R a+rX /opt/cursor-agent \
    && $SUDO ln -sf /opt/cursor-agent/.local/bin/cursor-agent "$CLI_INSTALL_DIR/cursor-agent"; } \
    || echo "WARN: cursor-agent install failed — skipping (not fatal)"
fi

# 6) Optional: browser engines ----------------------------------------------------------
if [ "${WITH_BROWSERS:-0}" = "1" ]; then
  say "playwright + chromium"
  $SUDO npm install -g playwright@1.60.0
  export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
  $SUDO env PLAYWRIGHT_BROWSERS_PATH=/ms-playwright npx playwright install --with-deps chromium || true
  # Camoufox: vendored server lives at agent-runtime/camofox-browser; the camofox CLI wrapper launches it.
  if [ -d "$SCRIPT_DIR/camofox-browser" ]; then
    say "camofox-browser (vendored server)"; ( cd "$SCRIPT_DIR/camofox-browser" && npm_config_ignore_scripts=true npm ci --omit=dev ) || true
  fi
fi

# 7) The Bento CLI toolkit (wrapper CLIs) — SSOT = templates/pharmia/cli -------------------
say "cli toolkit → $CLI_INSTALL_DIR (via cli/install.sh)"
CLI_INSTALL_DIR="$CLI_INSTALL_DIR" sh "$PHARMIA_DIR/cli/install.sh"
# Arm the repo git hooks so wrapper CLIs re-sync on every pull (clone + pull keeps PATH fresh).
( cd "$REPO_DIR" && git config core.hooksPath .githooks 2>/dev/null ) || true

# 8) Optional: code-server (browser VS Code, localhost-only) ------------------------------
if [ "${WITH_CODE_SERVER:-0}" = "1" ] && ! command -v code-server >/dev/null 2>&1; then
  say "code-server (localhost-bound)"
  curl -fsSL https://code-server.dev/install.sh | $SUDO sh
  echo "code-server installed — enable per-user: systemctl --user enable --now code-server (binds 127.0.0.1:8080; reach via ssh -L)."
fi

say "DONE. Verify: $(command -v gh logcli ovhcloud claude codex opencode gemini amp goose filebrowser node bun uv 2>/dev/null | tr '\n' ' ')"
say "Wrapper CLIs on PATH: $(command -v loki pg threads ol comp dokploy cfdns 2>/dev/null | tr '\n' ' ')"
