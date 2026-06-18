---
name: "pharmia-infra"
description: "Pharmia infrastructure environment — Dokploy instances, VPS topology, compose IDs, cfdns/Gatus/PocketID workflows. Use when deploying, managing services, DNS, or tenants on Pharmia/Bento infrastructure."
slug: "pharmia-infra"
metadata:
  paperclip:
    slug: "pharmia-infra"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-infra"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-infra"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-infra"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-infra"
user-invocable: false
---

# Pharmia Infrastructure

Environment knowledge for operating Pharmia and Bento Studio infrastructure on Dokploy.

## Dokploy CLI

```bash
# Pattern: dokploy <instance> <args...>  (instances: bento, devops, prod, orange)
# Most args forward to @dokploy/cli; a few are custom wrapper commands (see --help).

# Read
dokploy bento project all --json                 # projects + composes/apps
dokploy bento status [--broken] [--json]         # health across services
dokploy bento apps [<substr>]                    # flat service list -> NAME, ID (composeId)
dokploy bento logs <app> [--tail N] [--deployment N]
dokploy bento deployments [<app>] [--running] [--json]  # deploy feed = the build QUEUE (what's building NOW)

# Deploy (composeId from `apps` / `project all`)
dokploy bento compose deploy --composeId XUsJlG8eIiGnZNadm3x5J

# Env (corruption-proof: backup->keydiff-guard->verify->git commit; SAVE only, NOT deploy)
dokploy bento env-set <app> KEY=VAL [--dry-run]  # follow with `compose deploy` to apply
dokploy bento env-rm  <app> KEY [--dry-run]
dokploy bento env-rollback <app> [<sha>]         # restore prior env from git history

# GOTCHA: the old dotted `compose.all` / `compose.one '{json}'` syntax is GONE —
# those silently no-op. `status`/`apps` show only the LAST result, never in-flight,
# so use `deployments` to see what's building / queued. For other reads, query
# Dokploy's Postgres directly: docker exec <dokploy-postgres> psql -U dokploy -d dokploy
#   tables: compose (sourceType/branch/env/autoDeploy), domain (host/port/uniqueConfigKey)
# (a deploy queued behind another has NO deployment row until it starts; a no-op/
#  README-only change can finish 'done' WITHOUT recreating the container — same image.)
```

## VPS Topology

- **bento** (51.222.204.73) — Dev/staging, internal tools. SSH: `ssh bento`
- **devops** (158.69.219.78) — Observability, monitoring, CI. SSH: `ssh devops`
- **prod** (167.114.2.32) — Pharmia production (canary). SSH: `ssh prod`
- **orange** (51.222.136.243) — Orange client
- **agents** (149.56.13.177) — shared agent/dev box: Coder OSS control plane (code.bentostudio.io, per-user/shared workspaces, PocketID OIDC) + capped `bento-agents` user. SSH: `ssh agents` (admins only). NOT a prod-traffic box.

### Bento Instance — Dev/Staging + Internal Tools

- Pharmia environments: pharmia-dev (admin.dev.pharmia.ca), pharmia-qa (admin.qa.pharmia.ca)
- PocketID SSO (auth.bentostudio.io), Outline (outline.bentostudio.io), Chatwoot (chatwoot.bentostudio.io), Vaultwarden (vaultwarden.bentostudio.io), Nextcloud (nextcloud.bentostudio.io), n8n (n8n.bentostudio.io), LibreChat (ai.bentostudio.io), Twenty CRM (twenty.bentostudio.io), Documenso (documenso.bentostudio.io), LiveKit (livekit.bentostudio.io), Postiz (postiz.bentostudio.io), Kaneo (kaneo.bentostudio.io), Formbricks (formbricks.bentostudio.io), Browserless (browserless.bentostudio.io), Overleaf (overleaf.bentostudio.io), La Suite Meet (meet.bentostudio.io), CrowdSec (crowdsec.bentostudio.io), RSSHub, Rachoon, Authentik (legacy SAML), Capso

### DevOps Instance — Observability & Shared Infra

- Langfuse (langfuse.bentostudio.io), Beszel (beszel.bentostudio.io), Gatus (gatus.bentostudio.io), MinIO (minio.bentostudio.io), Infisical (infisical.bentostudio.io), Kener (status.bentostudio.io), Forgejo (git.bentostudio.io), Uptime Kuma (internal only), Comp AI (LIVE — GRC platform, `comp` CLI), Coder (code.bentostudio.io — browser IDE, bento-workspace template)

### Pharmia Prod Instance

- Pharmia canary (admin.canary.pharmia.ca, api.canary.pharmia.ca) with full LGTM stack
- PocketID SSO (auth.pharmia.ca), Chatwoot (chatwoot.pharmia.ca), Outline (outline.pharmia.ca), MongoDB (internal only)

## Git & CI/CD topology

- **Git origin is Forgejo** (`git.bentostudio.io/Pharmia/PharmaMate`), NOT GitHub — `github.com/BentoStudioIO/PharmaMate` is a **mirror** only. Fleet-wide, Bento services deploy from Dokploy **Gitea (Forgejo) git providers**, not hardcoded GitHub URLs.
- **Push → autodeploy**, no manual deploy for a normal push: `dev`→dev env, `qa`→qa, `canary`→canary (**canary IS prod**), `main`→prod. Validate locally (`check-types` + tests) and confirm fast-forward before any push to a shared branch — a bad push deploys. Per-compose webhook: `/api/deploy/compose/<refreshToken>`.
- **Container registry** = the same Forgejo (`git.bentostudio.io`). Private images only; never push to a public registry.
- Git discipline (no `--force`/`--force-with-lease`/`--no-verify`, fetch + verify fast-forward before push) is in ETHOS → "Linear git history". The one sanctioned exception (CTO-directed canary force-push) is operator-only — agents run prod **read-only**.

## Backups

- **Off-host WORM** — clinical Postgres + mastra + blobs back up to MinIO with **Object Lock** (immutable), least-priv `pharmia-backup-svc` key, ILM 35d.
- **Business DBs** (twenty / comp-ai / autumn / documenso / n8n / authentik / outline / formbricks / pocketid / vaultwarden / mongo) — `pharmia-backup` systemd-daily on bento/devops/prod/orange → WORM `business/` prefix. Dokploy's own backup is **silent-fail**; do not rely on it.
- Open risk: single-MinIO SPOF (no off-host replica yet).

## Critical Rules

1. **ALWAYS deploy via Dokploy** — Never `docker compose up` on the server. Dokploy wraps compose with project naming, Traefik labels, and env injection.
2. **Isolated networks** — Always use isolated network mode for new compose projects. Never use bare service names (`redis`, `postgres`) — use `{appName}-{service}-1` FQCNs.
3. **Never add Traefik labels in compose files** — Dokploy auto-injects them from domain entries.
4. **Bind mounts** — Use ABSOLUTE paths. Relative `./` resolves wrong in Dokploy.
5. **No VPS builds for Bun** — Transfer pre-built images via SSH or Forgejo registry.
6. **Private images only** — Never push to public registries. Use `git.bentostudio.io` or `docker save | ssh docker load`.

## DNS Management

```bash
# Use cfdns CLI (NOT wrangler)
cfdns zones                          # List zones
cfdns ls bentostudio.io              # List records
cfdns add bentostudio.io A myapp 51.222.204.73  # Add record (proxied: false by default)
cfdns find bentostudio.io myapp      # Find record
cfdns rm bentostudio.io <record-id>  # Delete record
```

Always set `proxied: false` for services behind Traefik (Let's Encrypt HTTP challenges).

## Gatus Monitoring

After adding/removing a service, update Gatus:
```bash
# Edit config on devops
ssh devops "cat /etc/dokploy/compose/devops-gatus-v53po5/files/config/config.yaml"
# After edit, restart
ssh devops "docker restart devops-gatus-v53po5-gatus-1"
```

## New Service Deployment Checklist

When deploying a new service, complete ALL steps in order:

1. **Create compose project** — `dokploy <instance> compose create`, then `dokploy <instance> compose update --sourceType raw --composeFile "$compose_file" --json`
2. **Add DNS record** — `cfdns add <zone> A <subdomain> <ip>` (no wildcard — every subdomain needs an explicit record)
3. **Add domain in Dokploy** — `dokploy <instance> domain create --host <host> --path / --https --certificateType letsencrypt --composeId <id> --serviceName <service> --port <port> --json`
4. **Redeploy** — `dokploy <instance> compose deploy --composeId <id> --title "deploy" --json` (Traefik labels are injected at deploy time)
5. **Add to Gatus** — append entry to `/etc/dokploy/compose/devops-gatus-v53po5/files/config/config.yaml` on devops, then `ssh devops "docker restart devops-gatus-v53po5-gatus-1"`
6. **Add to Homepage** — append entry to `/etc/dokploy/compose/bento-homepage-upqrol/files/config/services.yaml` on bento (auto-reloads, no restart needed)

## PocketID API

- **Use the REST API** to create/manage OIDC clients programmatically — do NOT ask the user to create clients manually in the UI
- Base URL: `$POCKETID_URL` (`https://auth.bentostudio.io`)
- Auth: `X-API-Key: $POCKETID_API_KEY` header
- Create client: `POST /api/oidc/clients` (returns client ID)
- Generate secret: `POST /api/oidc/clients/:id/secret` (returns secret, shown once)
- List clients: `GET /api/oidc/clients`
- Client creation requires `name`, `callbackURLs`, `logoutCallbackURLs`, `isPublic` (false), `pkceEnabled`
- Interactive API docs at `https://auth.bentostudio.io/docs/api`

## Key Compose IDs

### Bento
- pharmia-dev, pharmia-qa
- Auth: `bento-studio-authentik-wbcrpt`, CrowdSec: `bcb0EI_RXgUwou2fftb6a`

### DevOps
- Langfuse: `Q7QAWIE96wLjBstUif9fN` / `devops-langfuse-qruiwo`
- Forgejo: `zlzk2FnmNsHtYhh2L81l7`
- Formbricks: `L0hlbCqiYIUaHa0zKM00e`
- Gatus: `devops-gatus-v53po5`

### Prod
- Pharmia canary: `aJZ7Nr83ddA1gux9p6cEE`
- Autumn: `qpUZGFtk7heX0Exx8KW47`

## OVH VPS Management

```bash
ovhcloud vps list                              # List all VPS
ovhcloud vps reboot vps-XXXXXXXX.vps.ovh.ca   # Reboot crashed server (~1-2 min)
```

## Adding a Pharmia Tenant

Use `pharmia-tenant` as the single entrypoint for normal tenant provisioning. Do NOT hand-roll Postgres inserts, DNS records, Dokploy domains, or redeploys for a new tenant; the CLI already provisions DNS + Dokploy domain + DB tenant/user/membership and writes an audit log.

```bash
pharmia-tenant status --env qa --slug <slug>
pharmia-tenant create --env qa --slug <slug> \
  --company-name "<Company>" \
  --owner-email <email> \
  --owner-first-name <first> \
  --owner-last-name <last> \
  --template-tenant <existing-slug> \
  --dry-run --check-live
pharmia-tenant create --env qa --slug <slug> \
  --company-name "<Company>" \
  --owner-email <email> \
  --owner-first-name <first> \
  --owner-last-name <last> \
  --template-tenant <existing-slug>
```

For prod/canary tenant provisioning, use `--env prod`; every mutating prod command MUST include `--confirm-prod`. `--env qa` creates `<slug>.qa.pharmia.ca`; `--env prod` creates `<slug>.pharmia.ca`.

Use `pg`, `cfdns`, or `dokploy` directly only when `pharmia-tenant status` or `create` reports a partial/failure state that the wrapper cannot repair. In that case, run `pharmia-tenant status --env <env> --slug <slug> --debug` first and make the smallest idempotent repair to the missing subsystem only.

## Troubleshooting

- **Compose file updates**: Use `dokploy <instance> compose update --composeId "..." --composeFile "$compose_file" --sourceType raw --json`
- **Registry auth**: Call `dokploy <instance> registry test-registry-by-id --registryId <id> --json` to force `docker login` before deploying private images
- **Dokploy strips** `mem_limit`/`cpus` from compose YAML — use host-mount configs or `docker update` post-deploy
- **Swap on devops**: 12GB total (`/swapfile` 4GB + `/swapfile2` 8GB), 7.6GB RAM
