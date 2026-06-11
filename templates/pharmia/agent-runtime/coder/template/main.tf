# Bento workspace template (Coder + Docker provider) — the generic Bento dev workspace.
# (Coder template slug: bento-workspace. Generic: one shared template, per-user workspaces.)
#
# ISOLATION MODEL — true per-person isolation:
#   • One Docker CONTAINER per user/workspace, named coder-<owner>-<workspace>.
#   • One dedicated Docker VOLUME per workspace (coder-<workspace.id>-home) mounted at
#     /home/coder. Each person's files live in their own volume; no shared home.
#   • Containers are recreated on start/stop but the home VOLUME persists (lifecycle
#     ignore_changes), so a user's work survives restarts while staying isolated.
#
# CREDENTIALS — these are NO-CREDS dev sandboxes. ZERO prod credentials are baked into
# the image or injected here. Per-identity prod creds are granted out-of-band, never via
# this template (see PLAN-shared-agent-vps.md credentials axis).
#
# EDITORS / AGENTS — official pinned registry modules.
#   Browser IDE: code-server (OpenVSX; ONE browser VS Code on purpose — vscode-web was
#   a near-duplicate and was removed; re-add it only if someone needs an MS-marketplace-
#   only extension like pylance). Desktop hand-offs (pure protocol buttons, nothing
#   installed in-container): cursor, windsurf, zed, jetbrains-gateway (downloads the IDE
#   backend on first connect). VS Code Desktop uses Coder's BUILT-IN display app — the
#   vscode-desktop module was removed as an exact duplicate of it.
#   AI agents: claude-code + codex (CLI launcher tiles), opencode + goose (AgentAPI web
#   chat tiles, gated by the *_web_chat params below). ALL agent binaries are PRE-BAKED
#   in the workspace image (install_* = false → instant start, no per-start downloads).
#   gemini / amp / cursor-agent are ALSO baked but module-less: their registry modules
#   hard-inherit agentapi_subdomain=true, which is a dead link on this no-wildcard box —
#   use them from the terminal.
#   ZERO-CREDS invariant: every agent ships UN-credentialed (no API key / OAuth token
#   inputs set anywhere in this file); each dev authenticates themselves on first use.
#
# SUBDOMAIN GOTCHA — this control plane has NO wildcard access URL, so every web
# coder_app MUST be path-based: subdomain = false. vscode-web + filebrowser DEFAULT
# to subdomain = true upstream — never drop the explicit override.
#
# DEV ERGONOMICS (all official pinned registry modules — no hand-rolled scripts):
#   • git-clone → clones git_repo ONLY when the dev sets the param (default is
#     empty → nothing is precloned). When set to a git.bentostudio.io repo it
#     authenticates via the Forgejo external-auth (provider id "forgejo", OAuth2
#     flow; NO static token). Its post_clone_script writes apps/web/.env
#     (VITE_API_URL = dev_api_url) so the Vite frontend talks to the shared DEV
#     API with no local stack.
#   • git-config → per-user git identity. Git push over HTTPS works via the
#     Forgejo external-auth OAuth token (no SSH key upload needed).
#   • dotfiles + personalize → each dev applies their OWN dotfiles/setup on start.
#   • coder-login → auto-auth the `coder` CLI inside the workspace.
#   • coder_app "vite" → in-browser preview of the :5173 dev server (path-based).
#
# AUTOSTOP (set via `coder templates edit`, NOT in this file — it's template
# metadata, not TF): default-ttl 8h + activity-bump 1h, so idle workspaces stop
# ~1h after last activity and free RAM on this 8GB box. The home volume persists.
# (--inactivity-ttl / --failure-ttl / dormancy are Enterprise-only, off on OSS.)
#
# Push:  coder templates push bento-workspace -d . --yes
# (run from this dir, authenticated as a Coder owner: `coder login https://code.bentostudio.io`)

terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

# registry_auth lets the terraform docker provider PULL the private workspace image:
# pulls happen client-side (the provisioner inside the coder container), so the box
# root's `docker login` does NOT apply. The control-plane compose mounts the root
# docker config read-only at /docker-auth/config.json (see ../docker-compose.yml).
# Without this, new image versions fail with "error from registry: unauthorized".
provider "docker" {
  registry_auth {
    address     = "git.bentostudio.io"
    config_file = "/docker-auth/config.json"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Forgejo external-auth (provider id "forgejo", configured on the control plane as
# CODER_EXTERNAL_AUTH_0_*). Surfaces a one-time OAuth2 auth link in the workspace so
# git over HTTPS to git.bentostudio.io is authenticated — no static token, no SSH key.
# Optional (count = 0) when no repo is set, so an empty workspace doesn't force auth.
data "coder_external_auth" "forgejo" {
  count = trimspace(data.coder_parameter.git_repo.value) != "" ? 1 : 0
  id    = "forgejo"
}

# Workspace base image. Default: the published Bento agent-runtime image — a zero-creds
# full Bento engineering environment (node 24 + bun/uv + Bento wrapper CLIs + gh/gitleaks/
# oha/bx/logcli/ovhcloud/curl_cffi + claude-code + codex + the team engineering agents/skills
# baked into /opt/bento/claude-config). PINNED to a version (not :latest) for reproducible
# workspaces — bump the default when publishing a new image version. The agent-runtime image
# bakes the toolkit via agent-runtime/provision.sh and the agents/skills via build.sh.
data "coder_parameter" "workspace_image" {
  name         = "workspace_image"
  display_name = "Workspace image"
  description  = "Container image for the workspace. Must include git + a non-root sudo user 'coder' (or build from the provided Dockerfile). Default is the pinned Bento agent-runtime image."
  type         = "string"
  default      = "git.bentostudio.io/bentostudio/bento-agent-runtime:1.2.1"
  mutable      = true
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  type         = "number"
  default      = 2
  mutable      = true
  validation {
    min = 1
    max = 4 # box is 4 vCPU — cap per-workspace to avoid starving the control plane
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  type         = "number"
  default      = 2
  mutable      = true
  validation {
    min = 1
    max = 5 # box is ~7.6 GB total; control plane + PG need headroom
  }
}

# Repo to clone into ~/ on first build via the official git-clone module.
# Default is EMPTY → nothing is precloned; devs clone from Forgejo manually.
# When a dev sets this to a git.bentostudio.io repo, auth is the Forgejo
# external-auth configured on this control plane (provider id "forgejo", OAuth2)
# — the dev clicks an auth link once; NO static token is baked anywhere. The
# module is idempotent (skips if the repo dir already exists).
data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository (auto-clone, optional)"
  description  = "Optional. Leave empty to preclone nothing. Set to a git.bentostudio.io repo URL to auto-clone it into ~/ on first build via the Forgejo external-auth (OAuth2) — the first build prompts a one-time Forgejo auth link for private repos; no token is stored in the template."
  type         = "string"
  default      = ""
  mutable      = true
  validation {
    regex = "^(https?://.+)?$"
    error = "Must be empty or an http(s) git repo URL."
  }
}

# Shared DEV-environment API base the cloned frontend (apps/web, Vite :5173)
# points at, so interns can do frontend work without the full local stack.
# Discovered: packages/api/src/utils/url.ts getApiUrl('dev') === this value, and
# apps/web reads it via import.meta.env.VITE_API_URL. This is the NO-PROD-CREDS
# shared dev box — never point this at canary/prod.
data "coder_parameter" "dev_api_url" {
  name         = "dev_api_url"
  display_name = "Dev API base URL (VITE_API_URL)"
  description  = "Backend the local Vite frontend talks to. Default is the shared dev environment API. Used to write apps/web/.env after clone."
  type         = "string"
  default      = "https://api.dev.pharmia.ca"
  mutable      = true
}

# AI web-chat tiles (AgentAPI) are OPT-IN per workspace: each enabled chat runs an
# agentapi server + the agent process from workspace start (~200-300 MB RSS inside the
# workspace's own memory cap). The agent BINARIES are baked and always usable from the
# terminal regardless of these toggles — the params only control the dashboard chat tiles.
data "coder_parameter" "opencode_web_chat" {
  name         = "opencode_web_chat"
  display_name = "OpenCode web chat"
  description  = "Dashboard chat tile backed by the baked opencode binary (un-credentialed — run `opencode auth login` once). The CLI works in the terminal either way."
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "goose_web_chat" {
  name         = "goose_web_chat"
  display_name = "Goose web chat"
  description  = "Dashboard chat tile backed by the baked goose binary (un-credentialed — bring your own provider key). The CLI works in the terminal either way."
  type         = "bool"
  default      = false
  mutable      = true
}

locals {
  username = data.coder_workspace_owner.me.name
  repo_url = trimspace(data.coder_parameter.git_repo.value)
}

# ── Platform AI credential (admin-gated) ──────────────────────────────────────
# Platform AI-provider keys shared from Paperclip (same keys pharmia-dev uses).
# Supplied at template-push time as SENSITIVE template variables so they never
# touch git — the box keeps them at /etc/coder/{anthropic,openai}-api-key (root 600):
#   coder templates push ... \
#     --variable anthropic_api_key="$(cat /etc/coder/anthropic-api-key)" \
#     --variable openai_api_key="$(cat /etc/coder/openai-api-key)"
# CTO DECISION 2026-06-11: injected into EVERY workspace (not admin-gated) — anyone
# can use the providers. ANTHROPIC_API_KEY authenticates claude-code/opencode/goose;
# OPENAI_API_KEY authenticates codex. Each reads its key from session env.
# NOTE: template variables are per-push — a later push WITHOUT --variable silently
# disables injection (fail-closed; re-supply both on every push).
variable "anthropic_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Anthropic API key injected into all workspaces. Empty disables injection."
}

variable "openai_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "OpenAI API key (codex) injected into all workspaces. Empty disables injection."
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.main.id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "openai_api_key" {
  count    = var.openai_api_key != "" ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.main.id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

variable "groq_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Groq API key (FREE tier) injected into all workspaces — opencode auto-detects the groq provider. Empty disables injection."
}

resource "coder_env" "groq_api_key" {
  count    = var.groq_api_key != "" ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.main.id
  name     = "GROQ_API_KEY"
  value    = var.groq_api_key
}

variable "opencode_zen_api_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "OpenCode Zen API key (FREE coding models: opencode/big-pickle, minimax-m2.5-free, nemotron-3-super-free) injected into all workspaces as OPENCODE_API_KEY. Empty disables injection."
}

# Claude Code env parity with the CTO's workstation (~/.claude/settings.json env block,
# mirrored 2026-06-11 — "local CLAUDE_ENVS should be the same in the builder").
# AGENT_TEAMS is the split-window teammates feature; tmux+screen are baked in the image
# (>=1.2.1) so split-pane display works. Model overrides upgrade haiku→sonnet and
# sonnet/opus→opus-4-8 1M-context — NOTE this raises spend on the shared platform key.
locals {
  claude_code_env = {
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS  = "1"
    ANTHROPIC_DEFAULT_HAIKU_MODEL         = "claude-sonnet-4-6"
    ANTHROPIC_DEFAULT_SONNET_MODEL        = "claude-opus-4-8[1m]"
    ANTHROPIC_DEFAULT_OPUS_MODEL          = "claude-opus-4-8[1m]"
    CLAUDE_AUTOCOMPACT_PCT_OVERRIDE       = "80"
    CLAUDE_CODE_DISABLE_TELEMETRY         = "1"
    CLAUDE_CODE_NO_FLICKER                = "1"
    CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING = "1"
  }
}

resource "coder_env" "claude_code_env" {
  for_each = local.claude_code_env
  agent_id = coder_agent.main.id
  name     = each.key
  value    = each.value
}

resource "coder_env" "opencode_zen_api_key" {
  count    = var.opencode_zen_api_key != "" ? data.coder_workspace.me.start_count : 0
  agent_id = coder_agent.main.id
  name     = "OPENCODE_API_KEY"
  value    = var.opencode_zen_api_key
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  dir  = "/home/coder"

  # Startup script: (1) sync the baked TEAM engineering agents/skills/rules into $HOME/.claude,
  # and (2) seed code-server settings.json. Both idempotent. The repo CLONE and apps/web/.env
  # wiring are handled by the official git-clone module + its post_clone_script below (Forgejo
  # external-auth OAuth2 flow — NO static token), only when git_repo is set, not here.
  #
  # .claude SYNC — solves the home-volume-shadowing problem: the image bakes the team
  # agents/skills/rules into /opt/bento/claude-config (a NON-home path so Coder's per-user
  # home volume can't shadow it). On every start we copy them into $HOME/.claude with `cp -rn`
  # (no-clobber) so each workspace gets the engineering agents WITHOUT ever overwriting a
  # dev's own edits. New baked agents/skills appear on next start; dev-modified files are kept.
  startup_script = <<-EOT
    set -u
    if [ -d /opt/bento/claude-config ]; then
      mkdir -p "$HOME/.claude"
      for sub in agents skills rules; do
        if [ -d "/opt/bento/claude-config/$sub" ]; then
          mkdir -p "$HOME/.claude/$sub"
          cp -rn /opt/bento/claude-config/$sub/. "$HOME/.claude/$sub/" 2>/dev/null || true
        fi
      done
      echo "[startup] synced team agents/skills/rules → $HOME/.claude (no-clobber)"
      # environment-bindings.md is the PAPERCLIP-SANDBOX edition of the toolkit doc (assumes
      # injected scoped creds) — in zero-creds workspaces it made Claude over-claim access.
      # Removed every start (re-copied by the no-clobber sync above, so rm must follow it).
      rm -f "$HOME/.claude/rules/environment-bindings.md"
    fi
    # codex + opencode + agentskills.io std formats (rulesync fanout, baked at /opt/bento).
    # Same no-clobber pattern as .claude → a dev's own edits are never overwritten.
    if [ -d /opt/bento/claude-config/codex ]; then
      mkdir -p "$HOME/.codex"; cp -rn /opt/bento/claude-config/codex/. "$HOME/.codex/" 2>/dev/null || true
    fi
    if [ -d /opt/bento/claude-config/opencode ]; then
      mkdir -p "$HOME/.config/opencode"; cp -rn /opt/bento/claude-config/opencode/. "$HOME/.config/opencode/" 2>/dev/null || true
    fi
    if [ -d /opt/bento/claude-config/agents-std ]; then
      mkdir -p "$HOME/.agents"; cp -rn /opt/bento/claude-config/agents-std/. "$HOME/.agents/" 2>/dev/null || true
    fi
    echo "[startup] synced codex/opencode/agentskills formats → $HOME (no-clobber)"
    # Workspace-context rule — the baked team rules describe the full Bento CLI toolkit,
    # which makes Claude OVER-CLAIM access it doesn't have here (CLIs are baked but
    # zero-creds → inert). This rule states the workspace truth. Written once (no-clobber).
    if [ ! -f "$HOME/.claude/rules/workspace-context.md" ]; then
      cat > "$HOME/.claude/rules/workspace-context.md" <<'RULE'
# Bento Workspace Context (zero-creds) — READ FIRST

You are inside a SHARED Bento Coder workspace (code.bentostudio.io), not the CTO's
workstation. The Bento wrapper CLIs (loki, tempo, prom, pyro, pg, threads, langfuse,
dokploy, cfdns, twenty, autumn, ol, comp, pharmia-*) are on PATH but UN-credentialed:
no tokens, no SSH keys, no ~/.config/<tool> — they WILL fail here. Do NOT claim or
offer access to observability, prod/canary data, CRM, billing, or infra operations.

What DOES work out of the box:
- AI agents: claude, codex, opencode, goose (platform keys injected)
- git to git.bentostudio.io via the dev's own Forgejo OAuth
- the shared dev API (https://api.dev.pharmia.ca) for frontend work
- the full code/research toolchain (node/bun/uv, gh, ripgrep, …)

Per-identity ops credentials are granted out-of-band only — if the dev needs one,
tell them to ask the CTO instead of trying the CLI.
RULE
      echo "[startup] wrote workspace-context rule"
    fi
    # Codex auth: unlike claude (reads ANTHROPIC_API_KEY from env directly), the codex
    # CLI needs auth.json written once. When OPENAI_API_KEY is injected and codex isn't
    # already logged in, write it. Idempotent + zero-touch for every workspace.
    if [ -n "$${OPENAI_API_KEY:-}" ] && ! codex login status >/dev/null 2>&1; then
      printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null 2>&1 \
        && echo "[startup] codex authenticated via OPENAI_API_KEY" || true
    fi
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "top -bn1 | awk '/Cpu/ {print $2\"%\"}'"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory Usage"
    key          = "mem"
    script       = "free -m | awk 'NR==2{printf \"%.0f%%\", $3*100/$2}'"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Home Disk"
    key          = "disk"
    script       = "df -h /home/coder | awk 'NR==2{print $5}'"
    interval     = 60
    timeout      = 1
  }
}

# ── Editors ──────────────────────────────────────────────────────────────────
# We offer FOUR ways to open a workspace so devs use what they prefer:
#   • code-server  — browser VS Code, OpenVSX extension marketplace.
#   • vscode-web   — browser VS Code, Microsoft marketplace (extensions like the
#                    full ms-python.* pack that aren't on OpenVSX live here).
#   • vscode-desktop / cursor — open the workspace in the dev's LOCAL desktop
#                    VS Code / Cursor over the Coder remote connection.

# code-server (browser, OpenVSX). Pinned. Extensions are TEMPLATE DEFAULTS;
# users can install more per-workspace.
module "code-server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.5.0"
  agent_id = coder_agent.main.id
  order    = 1
  share    = "authenticated" # shared devbox: any logged-in user may open
  extensions = [
    # baseline (mirrors the CTO's Cursor)
    "anthropic.claude-code",
    "ms-python.python",
    "ms-python.debugpy",
    "tomoki1207.pdf",
    # team dev set (all verified on OpenVSX) — theme/icons + TS/React/Tailwind/Docker loop
    "github.github-vscode-theme",
    "pkief.material-icon-theme",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "bradlc.vscode-tailwindcss",
    "eamodio.gitlens",
    "usernamehw.errorlens",
    "redhat.vscode-yaml",
    "ms-azuretools.vscode-docker",
    "mikestead.dotenv",
  ]
  # Single source of the seeded editor defaults (the module writes User/settings.json
  # once if absent — dev edits are never overwritten). Theme/icons match the team set.
  settings = {
    "window.commandCenter"                       = true
    "explorer.confirmDelete"                     = false
    "files.autoSave"                             = "afterDelay"
    "workbench.colorTheme"                       = "GitHub Dark Default"
    "workbench.iconTheme"                        = "material-icon-theme"
    "workbench.startupEditor"                    = "none"
    "editor.fontSize"                            = 14
    "editor.tabSize"                             = 2
    "editor.formatOnSave"                        = true
    "editor.defaultFormatter"                    = "esbenp.prettier-vscode"
    "editor.codeActionsOnSave"                   = { "source.fixAll.eslint" = "explicit" }
    "editor.minimap.enabled"                     = false
    "editor.stickyScroll.enabled"                = true
    "editor.bracketPairColorization.enabled"     = true
    "files.trimTrailingWhitespace"               = true
    "typescript.updateImportsOnFileMove.enabled" = "always"
    "git.autofetch"                              = true
    "git.confirmSync"                            = false
    "terminal.integrated.defaultProfile.linux"   = "bash"
    "telemetry.telemetryLevel"                   = "off"
  }
}

# cursor — open in the dev's LOCAL Cursor over remote.
module "cursor" {
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
  order    = 4
}

# windsurf — open in the dev's LOCAL Windsurf over remote (protocol button only).
module "windsurf" {
  source   = "registry.coder.com/coder/windsurf/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
  order    = 5
}

# zed — open in the dev's LOCAL Zed over SSH (protocol button only).
module "zed" {
  source   = "registry.coder.com/coder/zed/coder"
  version  = "1.1.4"
  agent_id = coder_agent.main.id
  folder   = "/home/coder"
  order    = 6
}

# jetbrains-gateway — open in a LOCAL JetBrains IDE via Gateway. Adds an IDE-picker
# param on workspace create. NOTE: first connect downloads the IDE *backend* (~1 GB)
# into the workspace home volume — on-demand only, nothing runs until a dev uses it.
module "jetbrains-gateway" {
  source         = "registry.coder.com/coder/jetbrains-gateway/coder"
  version        = "1.2.6"
  agent_id       = coder_agent.main.id
  agent_name     = "main"
  folder         = "/home/coder"
  jetbrains_ides = ["WS", "IU", "PY", "GO"]
  default        = "WS"
  order          = 7
}

# filebrowser — web file manager (upload/download/browse the home volume). Uses the
# baked binary (run.sh skips install when `filebrowser` is on PATH). Path-based.
module "filebrowser" {
  source     = "registry.coder.com/coder/filebrowser/coder"
  version    = "1.1.5"
  agent_id   = coder_agent.main.id
  agent_name = "main" # REQUIRED when subdomain=false (path URLs are /@owner/ws.<agent>/apps/…)
  folder     = "/home/coder"
  subdomain  = false # upstream default is true → dead link without a wildcard access URL
  order      = 20
  share      = "authenticated" # shared devbox: any logged-in user may open
}

# ── AI agents ────────────────────────────────────────────────────────────────

# claude-code — Anthropic's CLI agent, PRE-BAKED in the image and NOT credentialed.
# install_claude_code = false → the module skips its per-start download and PATH-detects
# the baked `claude` binary (instant start). Both anthropic_api_key and
# claude_code_oauth_token are deliberately left unset, so NO ambient secret is baked
# into the template (zero-creds rule holds). Each dev authenticates themselves on
# first run (`claude` login with their own account / key, or `claude setup-token`).
module "claude-code" {
  source              = "registry.coder.com/coder/claude-code/coder"
  version             = "5.2.0"
  agent_id            = coder_agent.main.id
  install_claude_code = false
  # The baked binary lives in the root-owned npm prefix (/usr/local) — self-update can't
  # write there as the coder user and nags "Auto-update failed". Versions ship via image
  # bumps, so the updater is noise: this sets DISABLE_AUTOUPDATER=1 in the session env.
  # Ad-hoc update inside a workspace still possible: sudo npm i -g @anthropic-ai/claude-code@latest
  disable_autoupdater = true
}

# codex — OpenAI's CLI agent (CLI launcher tile, no AgentAPI daemon). Pre-baked binary
# (install_codex = false → PATH-detect), openai_api_key left unset (zero-creds).
module "codex" {
  source        = "registry.coder.com/coder-labs/codex/coder"
  version       = "5.1.0"
  agent_id      = coder_agent.main.id
  install_codex = false
}

# opencode — sst's CLI agent with an AgentAPI web chat tile (path-based; the module
# defaults subdomain=false). Pre-baked binary (install_opencode = false → the module
# PATH-detects it). cli_app = true also exposes a terminal launcher tile. auth_json /
# config_json left unset — each dev runs `opencode auth login` once (zero-creds).
# Gated by the opencode_web_chat param: the chat tile costs ~200-300 MB RSS per
# workspace while running, so devs can switch it off; the binary works regardless.
module "opencode" {
  count            = data.coder_parameter.opencode_web_chat.value ? 1 : 0
  source           = "registry.coder.com/coder-labs/opencode/coder"
  version          = "0.1.2"
  agent_id         = coder_agent.main.id
  workdir          = "/home/coder"
  install_opencode = false
  subdomain        = false
  cli_app          = false # web chat tile only — a separate "OpenCode CLI" tile is redundant
  order            = 10
}

# goose — Block's CLI agent with an AgentAPI web chat tile (path-based). Pre-baked
# binary (install_goose = false → PATH-detect). Provider/model are REQUIRED inputs;
# anthropic is configured WITHOUT any key — the dev brings their own (zero-creds).
# Default-off: opt in per workspace via the goose_web_chat param.
module "goose" {
  count          = data.coder_parameter.goose_web_chat.value ? 1 : 0
  source         = "registry.coder.com/coder/goose/coder"
  version        = "3.0.1"
  agent_id       = coder_agent.main.id
  folder         = "/home/coder"
  install_goose  = false
  subdomain      = false
  goose_provider = "anthropic"
  goose_model    = "claude-sonnet-4-6"
  order          = 11
}

# Dashboard launcher tiles for claude-code + codex: their v5-style modules install/
# wire the CLI only and create NO coder_app, so without these the agents are invisible
# in the UI (terminal-only). Each opens a web terminal running the agent.
resource "coder_app" "claude_code" {
  agent_id     = coder_agent.main.id
  slug         = "claude-code"
  display_name = "Claude Code"
  icon         = "/icon/claude.svg"
  command      = "claude"
  order        = 8
  share        = "authenticated" # shared devbox: any logged-in user may open
}

resource "coder_app" "codex" {
  agent_id     = coder_agent.main.id
  slug         = "codex"
  display_name = "Codex"
  icon         = "/icon/openai.svg"
  command      = "codex"
  order        = 9
  share        = "authenticated" # shared devbox: any logged-in user may open
}

# gemini-cli, amp, cursor-agent — baked in the image, NO registry module on purpose:
# their modules (coder-labs/gemini, coder-labs/sourcegraph-amp, coder-labs/cursor-cli)
# inherit agentapi_subdomain = true with no override input, which renders a dead web
# tile on this no-wildcard control plane. Use them from the terminal: `gemini`, `amp`,
# `cursor-agent` (each prompts for its own auth on first use).

# ── Repo + dev ergonomics (official modules) ───────────────────────────────────

# coder-login — auto-authenticate the `coder` CLI inside the workspace.
module "coder-login" {
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

# git-config — per-user git identity (name/email seeded from the Coder profile;
# the dev can change it). No static credentials.
module "git-config" {
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.33"
  agent_id = coder_agent.main.id
}

# NOTE: the github-upload-public-key module was removed — it is GitHub-only.
# With the Forgejo external-auth (provider id "forgejo"), git push over HTTPS
# works via the OAuth token Coder injects into the git credential helper, so no
# per-workspace SSH key needs to be uploaded anywhere.

# dotfiles — each dev auto-applies their OWN dotfiles repo on start (shell/nvm
# config per-user, nothing baked into the image). Optional per-workspace param.
module "dotfiles" {
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.2"
  agent_id = coder_agent.main.id
}

# personalize — runs the dev's own ~/personalize script on start for any extra
# per-user setup the dotfiles repo doesn't cover.
module "personalize" {
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "1.0.32"
  agent_id = coder_agent.main.id
}

# git-clone — clones the chosen repo on first build ONLY when git_repo is set
# (count = 0 when empty → nothing is precloned). For git.bentostudio.io repos the
# clone authenticates via the Forgejo external-auth (provider id "forgejo",
# OAuth2; NO static token), matched by its CODER_EXTERNAL_AUTH_0_REGEX. Idempotent.
# The post_clone_script wires apps/web/.env → shared dev API so frontend tasks
# work without a local stack.
module "git-clone" {
  count             = local.repo_url != "" ? 1 : 0
  source            = "registry.coder.com/coder/git-clone/coder"
  version           = "2.0.1"
  agent_id          = coder_agent.main.id
  url               = local.repo_url
  post_clone_script = <<-EOS
    set -u
    WEB_ENV="$HOME/${replace(basename(local.repo_url), ".git", "")}/apps/web/.env"
    if [ -d "$(dirname "$WEB_ENV")" ] && [ ! -f "$WEB_ENV" ]; then
      printf 'VITE_API_URL="%s"\n' "${data.coder_parameter.dev_api_url.value}" > "$WEB_ENV"
      echo "[post-clone] wrote $WEB_ENV (VITE_API_URL=${data.coder_parameter.dev_api_url.value})"
    fi
  EOS
}

# Browser preview for the Vite dev server (apps/web, port 5173). Path-based
# (subdomain = false) because CODER_WILDCARD_ACCESS_URL is NOT set on this
# control plane, so subdomain apps have no DNS/cert. The dev runs the frontend
# (e.g. `cd PharmaMate && npm run dev` or `cd apps/web && npm run dev`) and this
# app proxies :5173 in-browser. `share = "owner"` keeps it private to the owner.
resource "coder_app" "vite" {
  agent_id     = coder_agent.main.id
  slug         = "vite"
  display_name = "Vite preview (run: npm run dev)" # 502 until a dev server listens on :5173 — that is the expected idle state
  icon         = "/icon/code.svg"
  url          = "http://localhost:5173"
  subdomain    = false
  share        = "authenticated" # shared devbox
  healthcheck {
    url       = "http://localhost:5173"
    interval  = 10
    threshold = 30
  }
}

# Per-workspace HOME volume → true per-person isolation. Persists across restarts.
resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = data.coder_parameter.workspace_image.value
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Resource caps (sized for the 4c/8GB box).
  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  command = ["sh", "-c", coder_agent.main.init_script]
  env     = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  # Per-person home volume — isolated from every other workspace.
  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  # Reach the Coder control plane on the host.
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "coder_metadata" "workspace" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  item {
    key   = "image"
    value = data.coder_parameter.workspace_image.value
  }
  item {
    key   = "home_volume"
    value = docker_volume.home.name
  }
}
