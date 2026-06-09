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
# IDE — Coder's official code-server registry module. Seeds the owner's default editor
# settings and pre-installs a small OpenVSX extension set + claude-code. All are TEMPLATE
# DEFAULTS users can override per-workspace (settings.json is regular user config; extra
# extensions can be installed in-session).
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

locals {
  username = data.coder_workspace_owner.me.name
}

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  dir  = "/home/coder"

  # Seed the owner's default code-server settings as a TEMPLATE DEFAULT (users may override).
  # heredoc-rendered from the committed code-server-settings.json so the two stay in sync.
  startup_script = <<-EOT
    set -e
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

# Official code-server module. Seeds settings + pre-installs OpenVSX extensions
# (template defaults; users can install more per-workspace). claude-code is the
# Anthropic agent extension. anthropic.claude-code / ms-python.python /
# ms-python.debugpy / tomoki1207.pdf are confirmed available on OpenVSX.
module "code-server" {
  source     = "registry.coder.com/coder/code-server/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.main.id
  extensions = [
    "anthropic.claude-code",
    "ms-python.python",
    "ms-python.debugpy",
    "tomoki1207.pdf",
  ]
  settings = {
    "window.commandCenter" = true
    "explorer.confirmDelete" = false
    "files.autoSave"       = "afterDelay"
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
