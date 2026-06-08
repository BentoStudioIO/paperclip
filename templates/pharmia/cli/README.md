# Pharmia / Bento CLI toolkit

**Source of truth** for the custom Pharmia + infra CLIs used by humans **and** agents.
Migrated out of `~/.local/bin` so they are versioned, shared, and bakeable into the
Daytona agent sandbox. (Compiled binaries — `gh`, `bx`, `oha`, `gitleaks`, `maverick`,
etc. — and personal tools — `yt2mp3`, `sp2mp3`, `gcal` — are intentionally **not** here;
install those normally. The agent image bakes `gh`/`bx`/`oha`/`gitleaks` as binaries plus the
Camoufox browser server via the Dockerfile; the `camofox` CLI wrapper ships here in the toolkit.)

## Edit / install / bake workflow

- **Edit a CLI → edit the file in `bin/` here.** This is the SSOT. The old "fix it
  directly in `~/.local/bin`" rule now means "fix it here, then re-install."
- **Humans:** `sh install.sh` symlinks every `bin/*` into `~/.local/bin` (idempotent;
  backs up any prior real file once into `~/.local/bin/.cli-backup/`). It also runs
  automatically on `git pull` via the `.githooks/post-merge` + `post-checkout` hooks —
  same harness as agents/skills. One-time per clone: `git config core.hooksPath .githooks`.
- **Daytona / sandbox image:** `CLI_INSTALL_DIR=/usr/local/bin sh install.sh` in the
  build (see Dockerfile snippet below).

## Credentials & the dev↔prod boundary (important)

The scripts contain **no secrets** — they read creds from `~/.config/<tool>/`. Those
config files are **not** in this repo. On a dev box they already exist; in a sandbox
they are injected from **Vaultwarden, dev/qa-scoped only**.

Several CLIs are **prod-capable** and must get **no prod creds** in an agent sandbox
(give them only dev/qa config, or omit the config entirely):

- `cfdns` — Cloudflare DNS (omit from agents unless a dev-only token is scoped)
- `dokploy` — only the `bento` (dev/qa) instance config; never `prod`/`devops`
- `pg` — only dev/qa tunnels; never `canary`/`prod`
- `comp`, `pharmia-tenant` — prod-capable; omit creds for agents

## CLI reference

Observability:
- `loki <env> search|errors|count|warnings ...` — log queries (LogQL). Scope `{service_name="pharmia-api"}`.
- `tempo` — distributed trace search / lookup.
- `prom <env> ...` — PromQL, alerts, `grafana-alerts`, `grafana-history`.
- `pyro` — continuous profiling (CPU/heap/wall).
- `langfuse api ...` — AI traces/datasets/scores (`--limit` required; `observations-v2s`).

Pharmia dev / ops:
- `threads <admin-url>` or `threads <env> <id>` — agent-thread inspector (RCA-grade);
  modes `--rca` `--summary` `--tools` `--last` `--raw` `--json`; `modelmix <env>`. Backed by `pg <env> mastra`.
- `pg <env> <db>` — Postgres over SSH tunnel (dev/qa/canary).
- `pharmia-git` — git/release workflow (`topology`, `extra`, `ff-all`, `confine`, `deploy-status`).
- `pharmia-rc` — host Remote Control (systemd `claude-rc-pharmamate`): `status`/`up`/`restart`/`doctor`.
- `pharmia-tenant create --env qa|prod ...` — tenant provisioning. **prod-capable.**
- `dokploy <instance> ...` — Dokploy ops (`apps`, `status`, `logs`, `env-set`/`env-backup`/`env-rollback`). **prod/devops instances are prod-capable.**
- `dokploy-audit` — Dokploy config drift audit.

Knowledge / compliance:
- `ol ...` — Outline wiki (`search`, `doc get|update|create|list`, `verify`, `linkcheck`, `collections`, `tree`).
- `ol-verify` — Outline doc validator (URL liveness, shallow-url, cross-refs); companion to `ol verify`.
- `comp ...` — Comp AI GRC (policies/controls/frameworks/tasks/evidence; `sql` escape hatch). **prod-capable.**
- `opq-verify` — OPQ/RAMQ primary-source verifier.

Services / misc:
- `twenty gql '...'` / `twenty objects|fields` — Twenty CRM (auto-JWT).
- `autumn` — Autumn billing (customers/products/features/check/track/attach).
- `shlink` — Shlink short links + visit analytics + QR.
- `cfdns` — Cloudflare DNS (always `proxied:false`). **prod-capable.**
- `search-ai-sessions "query"` — search prior Claude/OpenCode sessions.
- `camofox` — anti-detect Firefox (Camoufox) REST wrapper (`start`/`tab`/`snap`/`click`/`screenshot`). Honors `$CAMOFOX_DIR` (the agent image sets it to the baked `/opt/camofox-browser`).

## Daytona image bake (snippet)

```dockerfile
# runtime deps the scripts need
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash curl jq git openssh-client postgresql-client ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*
# the toolkit (SSOT) → onto PATH
COPY templates/pharmia/cli /opt/bento-cli
RUN CLI_INSTALL_DIR=/usr/local/bin sh /opt/bento-cli/install.sh
# creds (~/.config/<tool>/) are NOT baked — injected at runtime from Vaultwarden (dev/qa-scoped)
```
