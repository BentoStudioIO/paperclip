# Pharmia dev-sandbox workspace template (Coder + Docker provider).
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
# EDITORS / AGENTS — official pinned registry modules: code-server
# (browser/OpenVSX), vscode-web (browser/MS-marketplace, for ms-python.* etc.),
# vscode-desktop and cursor (open the workspace in the dev's LOCAL desktop editor
# over remote), and claude-code (Anthropic CLI agent, INSTALLED but un-credentialed
# — each dev authenticates themselves; NO baked key). Extension lists are TEMPLATE
# DEFAULTS; users can add more.
#
# DEV ERGONOMICS (all official pinned registry modules — no hand-rolled scripts):
#   • git-clone → auto-clone git_repo on first build via the GitHub external-auth
#     DEVICE FLOW (one-time auth link; NO static token). Its post_clone_script
#     writes apps/web/.env (VITE_API_URL = dev_api_url) so the Vite frontend
#     talks to the shared DEV API with no local stack.
#   • git-config → per-user git identity. github-upload-public-key → per-workspace
#     SSH key whose PUBLIC half is uploaded to the dev's GitHub (push without PAT).
#   • dotfiles + personalize → each dev applies their OWN dotfiles/setup on start.
#   • coder-login → auto-auth the `coder` CLI inside the workspace.
#   • coder_app "vite" → in-browser preview of the :5173 dev server (path-based).
#
# AUTOSTOP (set via `coder templates edit`, NOT in this file — it's template
# metadata, not TF): default-ttl 8h + activity-bump 1h, so idle workspaces stop
# ~1h after last activity and free RAM on this 8GB box. The home volume persists.
# (--inactivity-ttl / --failure-ttl / dormancy are Enterprise-only, off on OSS.)
#
# Push:  coder templates push pharmia-dev-sandbox -d . --yes
# (run from this dir, authenticated as a Coder owner: `coder login https://code.bentostudio.io`)

terraform {
  required_providers {
    coder  = { source = "coder/coder" }
    docker = { source = "kreuzwerker/docker" }
  }
}

provider "docker" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Workspace base image. Default: minimal node:24 (no-creds sandbox). Swap to the published
# Pharmia agent-runtime image (node 24 + Bento wrapper CLIs) once it's on Forgejo, e.g.
#   default = "git.bentostudio.io/bento/pharmia-agent-runtime:latest"
# The agent-runtime image already bakes the toolkit via agent-runtime/provision.sh.
data "coder_parameter" "workspace_image" {
  name         = "workspace_image"
  display_name = "Workspace image"
  description  = "Container image for the workspace. Must include git + a non-root sudo user 'coder' (or build from the provided Dockerfile)."
  type         = "string"
  default      = "codercom/enterprise-node:ubuntu"
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

# Repo auto-cloned into ~/ on first build via the official git-clone module.
# Default is the Pharmia monorepo (PRIVATE). Auth is the GitHub external-auth
# DEVICE FLOW configured on this control plane (provider id "github") — the dev
# clicks an auth link once; NO static token is baked anywhere. The module is
# idempotent (skips if the repo dir already exists).
data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "Git repository (auto-clone)"
  description  = "Repo cloned into ~/ on first build via GitHub external-auth (device flow). Default is the Pharmia monorepo. The first build prompts a one-time GitHub auth link for private repos — no token is stored in the template. Set to any other GitHub/GitLab repo URL to clone that instead."
  type         = "string"
  default      = "https://github.com/BentoStudioIO/PharmaMate"
  mutable      = true
  validation {
    regex = "^https?://.+"
    error = "Must be an http(s) git repo URL."
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

locals {
  username = data.coder_workspace_owner.me.name
  repo_url = trimspace(data.coder_parameter.git_repo.value)
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  dir  = "/home/coder"

  # Startup script: seed code-server settings.json (idempotent). The repo CLONE
  # and the apps/web/.env wiring are handled by the official git-clone module +
  # its post_clone_script below (which integrates with the GitHub external-auth
  # device flow — NO static token), not here.
  startup_script = <<-EOT
    set -u
    mkdir -p /home/coder/.local/share/code-server/User
    if [ ! -f /home/coder/.local/share/code-server/User/settings.json ]; then
      cat > /home/coder/.local/share/code-server/User/settings.json <<'SETTINGS'
${file("${path.module}/code-server-settings.json")}
SETTINGS
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
  source     = "registry.coder.com/coder/code-server/coder"
  version    = "1.5.0"
  agent_id   = coder_agent.main.id
  order      = 1
  extensions = [
    "anthropic.claude-code",
    "ms-python.python",
    "ms-python.debugpy",
    "tomoki1207.pdf",
  ]
  settings = {
    "window.commandCenter"   = true
    "explorer.confirmDelete" = false
    "files.autoSave"         = "afterDelay"
  }
}

# vscode-web (browser, Microsoft marketplace). Offered IN ADDITION to code-server
# so MS-marketplace-only extensions (full ms-python.* tooling) are available.
module "vscode-web" {
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.5.0"
  agent_id       = coder_agent.main.id
  accept_license = true
  order          = 2
  extensions     = [
    "ms-python.python",
    "ms-python.debugpy",
    "ms-python.vscode-pylance",
  ]
}

# vscode-desktop — open in the dev's LOCAL VS Code over remote.
module "vscode-desktop" {
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.2.1"
  agent_id = coder_agent.main.id
  order    = 3
}

# cursor — open in the dev's LOCAL Cursor over remote.
module "cursor" {
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
  order    = 4
}

# claude-code — Anthropic's CLI agent, INSTALLED but NOT credentialed. Both
# anthropic_api_key and claude_code_oauth_token are deliberately left unset, so
# NO ambient secret is baked into the template (zero-creds rule holds). Each dev
# authenticates themselves on first run (`claude` login with their own account /
# key, or `claude setup-token`).
module "claude-code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "5.2.0"
  agent_id = coder_agent.main.id
}

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

# github-upload-public-key — generates a per-workspace SSH key and uploads the
# PUBLIC half to the dev's GitHub account (via the "github" external-auth), so
# the dev can git push from the workspace. No PAT, no static token.
module "github-upload-public-key" {
  source           = "registry.coder.com/coder/github-upload-public-key/coder"
  version          = "1.0.32"
  agent_id         = coder_agent.main.id
  external_auth_id = "github"
}

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

# git-clone — clone the chosen repo on first build via the GitHub external-auth
# device flow (NO static token). Idempotent. The post_clone_script wires
# apps/web/.env → shared dev API so frontend tasks work without a local stack.
module "git-clone" {
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "2.0.1"
  agent_id = coder_agent.main.id
  url      = local.repo_url
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
  display_name = "Vite dev server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:5173"
  subdomain    = false
  share        = "owner"
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
  count = data.coder_workspace.me.start_count
  image = data.coder_parameter.workspace_image.value
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
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
