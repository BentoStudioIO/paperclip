# Pharmia agent runtime

The deterministic image agents run in (Daytona snapshot). It bakes the toolchain +
the [CLI toolkit](../cli/README.md) + the coding agents; **credentials are injected at
runtime**, never baked.

## Access set (all agents identical — locked 2026-06-08, "option B + comp")

One shared set for every agent (simple now; tier later if needed):

- **dev / qa** — read-write. Agents **push `dev`/`qa` directly** → Dokploy auto-deploys (fast test loop, no merge wait).
- **prod** — **read-only**: DB via a dedicated read-only Postgres role (no redaction), and observability (`loki`/`prom`/`tempo`/`pyro` canary tokens).
- **comp AI (GRC/legal)** — **read-write** (no product/clinical blast radius).
- **Autumn billing** — the **LIVE** secret (`am_sk_live`) is injected so `market-intel` can read real MRR/active-subs/churn (added 2026-06-08 for the growth dept). The key is rw-capable (`customer:create/delete`); agents are scoped by convention to read commands only — tighten to an Autumn read-scoped key if/when one exists.
- **NOT given to agents** (humans/devops for now): `cfdns` write, `dokploy` prod write, prod DB write.
- **main / canary deploy** — gated by the repo's `.husky/pre-push` CONFIRM hook (`CONFIRM_DEPLOY=<branch>`). Agents never set it, so they cannot ship prod/canary. The hook arms when the clone runs `npm install` (husky `prepare`) — the runtime must do that before pushing.

> Note (parked Law 25): prod DB read-only means patient data can enter agent/LLM context; accepted for now (no redaction). Keep the LLM on the ZDR model.

## Injected at runtime (not baked)

`GITHUB_APP_*` (or git token, repo-wide write — main/canary held back by the hook),
`ANTHROPIC_API_KEY`, `LOKI_{DEV,QA,CANARY}_TOKEN`, `PG_{DEV,QA}_*` (rw) + `PG_CANARY_*`
(the **read-only** role), and `~/.config/<tool>/` for `ol` / `langfuse` / `twenty` /
`comp` (rw) / `dokploy` (bento dev/qa only), plus **`AUTUMN_SECRET_KEY` (LIVE `am_sk_live`)
+ `AUTUMN_URL`** for real MRR via the `autumn` CLI. The `autumn` script reads
`AUTUMN_SECRET_KEY` from env (precedence over its config file). **The live Autumn key is
billing READ-WRITE** (`customer:create/delete`) — the growth dept's `market-intel` uses
read commands only (`customers` / `customer <id>` / `products`) to compute MRR/active-subs/churn.
Provision the live value (it's in `~/.config/pharmia-env-backups/prod-canary/app.env`) into the
`pharmia-sandbox` Environment's secrets — do NOT bake it. Otherwise no prod-infra creds.

## Build

```sh
docker build -f templates/pharmia/agent-runtime/Dockerfile -t pharmia-agent-runtime templates/pharmia
```

Push the tag to the registry Daytona pulls from, then reference it as the Daytona
snapshot in the single Paperclip Environment (`pharmia-sandbox`).
