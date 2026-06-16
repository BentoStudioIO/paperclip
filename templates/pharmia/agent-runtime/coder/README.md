# Coder (OSS) — self-hosted browser IDE on the "agents" VPS

Multi-tenant, per-user-isolated browser IDE at **https://code.bentostudio.io**, authenticated
via **PocketID OIDC**. Replaced the old shared `code-server` + `oauth2-proxy` stack.

- **Box:** Bento "agents" VPS (`agents-new` / ubuntu@149.56.13.177), 4 vCPU / 7.6 GB, docker gid 985.
  NOT a prod-traffic box — shared agent/dev workspace.
- **Reverse proxy:** host **Caddy** (`/etc/caddy/Caddyfile`) terminates TLS and proxies
  `code.bentostudio.io → 127.0.0.1:7080`.
- **Control plane:** `ghcr.io/coder/coder:latest` (v2.34.x) + `postgres:16`, isolated compose
  project `coder`, published to `127.0.0.1:7080` only.

## Files (SSOT)

- `docker-compose.yml` — control plane + Postgres. Isolated project `coder`. Zero secrets.
- `coder.env.example` — PLACEHOLDER env template. Real file = `/etc/coder/coder.env` on the box (root, 600).
- `template/main.tf` — per-user workspace template (Docker provider): one container + one
  dedicated home volume per user → **true per-person isolation**. NO prod creds baked.

## Deploy / operate (on the box)

```bash
# bring up / update the control plane
cd /opt/coder
sudo docker compose -p coder --env-file /etc/coder/coder.env up -d

# health
curl -s http://127.0.0.1:7080/healthz                 # 200
curl -s http://127.0.0.1:7080/api/v2/buildinfo | jq   # version
curl -s http://127.0.0.1:7080/api/v2/users/authmethods | jq .oidc

# logs
sudo docker logs --tail 100 coder
```

Caddy: `code.bentostudio.io { reverse_proxy 127.0.0.1:7080 }`. After editing the Caddyfile:
`sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile && sudo systemctl reload caddy`.

## Auth

- **OIDC (PocketID)** is the day-to-day login ("Sign in with PocketID"). Client registered via
  the PocketID API (name "Coder", redirect `https://code.bentostudio.io/api/v2/users/oidc/callback`,
  PKCE S256, scopes `openid profile email`). All email domains allowed (`CODER_OIDC_EMAIL_DOMAIN` unset).
- **First owner** = local password account (break-glass + for granting roles), escrowed at
  `/etc/coder/first-owner.creds` (root, 600).
- **Group/role sync is Premium → SKIPPED.** Admins are assigned manually:

  ```bash
  # grant owner to an OIDC user after their first login (run as an existing owner)
  sudo docker exec coder coder users edit-roles <username-or-email> --roles owner
  ```

- **Locking sign-in to specific PocketID users/groups is manual in OSS** — there is no built-in
  allow-list. Options: restrict at the PocketID client (allowed-users on the client) or review/disable
  users in Coder after they self-register.

## Workspaces

Each workspace = a Docker container `coder-<owner>-<workspace>` with its own `docker_volume`
`coder-<workspace.id>-home` mounted at `/home/coder` — isolated per person, persists across restarts.

**Release = one command** (from the workstation; encodes the docker-cp nesting trap, key
ownership, per-push variables, and the stored `workspace_image` param):

```bash
# template-only change (main.tf):
templates/pharmia/agent-runtime/release.sh
# new image version (bump VERSION + the main.tf workspace_image default together first):
templates/pharmia/agent-runtime/release.sh --image --devbox
```

Manual equivalent (what the script does):

```bash
# push the template (as an owner, from template/)
coder login https://code.bentostudio.io
coder templates push bento-workspace -d . --yes

# create a workspace
coder create my-ws --template bento-workspace \
  --parameter cpu=2 --parameter memory=2 \
  --parameter workspace_image=codercom/enterprise-node:ubuntu --yes
```

- **Image:** defaults to the pinned Bento agent-runtime image
  `git.bentostudio.io/bentostudio/bento-agent-runtime:1.2.1` — a zero-creds full Bento
  engineering environment (node 24 + bun/uv + Bento wrapper CLIs + gh/gitleaks/oha/bx/logcli/
  ovhcloud/curl_cffi + the **team engineering agents/skills** baked into
  `/opt/bento/claude-config`). Pinned (not `:latest`) for reproducible workspaces — bump the
  default when publishing a new version. On start the template syncs the baked agents/skills/rules
  into `$HOME/.claude` with `cp -rn` (no-clobber), solving the home-volume-shadowing problem.
  The image bakes the toolkit via `../provision.sh` and renders the agents/skills via `../build.sh`.
- **Multi-harness agents/skills (since 1.2.0):** `build.sh` runs rulesync once to emit EVERY
  harness format, baked at `/opt/bento/claude-config/{agents,skills,rules,codex,opencode,agents-std}`
  and synced on start to `$HOME/.claude`, `$HOME/.codex`, `$HOME/.config/opencode`, `$HOME/.agents`
  (agentskills.io). So `claude` + `opencode` see all 19 agents + 77 skills; `codex` sees the agents
  (rulesync emits no codex-format skills). All no-clobber — dev edits are never overwritten.
- **AI agents (ALL pre-baked in the image, ALL un-credentialed — each dev brings their own auth):**
  `claude`, `codex`, `opencode`, `gemini`, `amp`, `goose`, `cursor-agent`. Registry modules wire
  the dashboard tiles: `claude-code` + `codex` (CLI launchers, `install_* = false` → no per-start
  download), `opencode` + `goose` (AgentAPI web chat, path-based, gated by the per-workspace
  `opencode_web_chat` / `goose_web_chat` params — each enabled chat costs ~200-300 MB RSS).
  gemini/amp/cursor-agent have NO module on purpose: their modules hard-inherit
  `agentapi_subdomain = true` (dead link without a wildcard) — terminal-only.
- **Editors (deduped 2026-06-11):** `code-server` is THE browser VS Code (OpenVSX). Pre-configured
  via the module's `settings` input (single writer; written once if absent so dev edits survive):
  GitHub Dark Default theme + material icons + prettier-on-save + eslint fixAll + sane TS/git
  defaults. Extensions preinstalled: claude-code, python+debugpy, pdf, github-theme,
  material-icon-theme, prettier, eslint, tailwindcss, gitlens, errorlens, yaml, docker, dotenv — the `vscode-web` module was removed as a near-duplicate (re-add only for
  MS-marketplace-only extensions like pylance). VS Code Desktop = Coder's BUILT-IN display app
  (the `vscode-desktop` module duplicated it and was removed). Desktop hand-offs: `cursor` /
  `windsurf` / `zed` / `jetbrains-gateway` (IDE backend downloads on first connect, ~1 GB into
  the home volume). Plus `filebrowser` (web file manager, `subdomain = false`, baked binary).
- **Claude Code env parity (since 1.2.1):** the template injects the CTO's workstation
  `~/.claude/settings.json` env block into every workspace (`coder_env` for_each):
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (split-window teammates — tmux + screen are baked
  in the image for the pane display), autocompact 80%, telemetry off,
  no-flicker, adaptive-thinking off. Update path: edit `locals.claude_code_env` in main.tf.
- **Resource caps** are sized for the 4c/8GB box (cpu ≤4, memory ≤5 GB).

## Rollback (to the old stack)

```bash
sudo cp /etc/caddy/Caddyfile.bak-pre-coder-* /etc/caddy/Caddyfile   # restore 4180 target
sudo systemctl reload caddy
sudo systemctl enable --now oauth2-proxy code-server@ubuntu
sudo docker compose -p coder stop   # optional: stop Coder
```

The old `oauth2-proxy` + `code-server@ubuntu` units + configs are kept (disabled), so rollback is
a Caddy revert + re-enable.

## Known follow-ups (not done)

- **Wildcard `*.code.bentostudio.io` cert** for subdomain app/port access needs Caddy's Cloudflare
  DNS-01 module; stock apt Caddy lacks it. **Path-based app access works today without it.**
- **Sign-in allow-list** is manual in OSS (see Auth).
- **RAM note:** control plane (~coderd + PG) adds ~0.5–1 GB; cap concurrent workspaces on this box.
