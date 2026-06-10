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
- `template/code-server-settings.json` — seeded default editor settings (overridable per-workspace).

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

```bash
# push the template (as an owner, from template/)
coder login https://code.bentostudio.io
coder templates push pharmia-dev-sandbox -d . --yes

# create a workspace
coder create my-ws --template pharmia-dev-sandbox \
  --parameter cpu=2 --parameter memory=2 \
  --parameter workspace_image=codercom/enterprise-node:ubuntu --yes
```

- **Image:** defaults to the pinned Pharmia agent-runtime image
  `git.bentostudio.io/bentostudio/pharmia-agent-runtime:1.0.0` — a zero-creds full Bento
  engineering environment (node 24 + bun/uv + Bento wrapper CLIs + gh/gitleaks/oha/bx/logcli/
  ovhcloud/curl_cffi + claude-code + codex + the **team engineering agents/skills** baked into
  `/opt/bento/claude-config`). Pinned (not `:latest`) for reproducible workspaces — bump the
  default when publishing a new version. On start the template syncs the baked agents/skills/rules
  into `$HOME/.claude` with `cp -rn` (no-clobber), solving the home-volume-shadowing problem.
  The image bakes the toolkit via `../provision.sh` and renders the agents/skills via `../build.sh`.
- **IDE:** Coder's official `coder/code-server` registry module. Seeds the default `settings.json`
  and pre-installs OpenVSX extensions (`anthropic.claude-code`, `ms-python.python`,
  `ms-python.debugpy`, `tomoki1207.pdf`) — all template defaults users can override.
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
