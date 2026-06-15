# Environment Bindings — Pharmia agents-VPS runtime

Tool and CLI bindings available in the **agents-VPS runtime** — where the Paperclip agents run via
SSH (user `agent`, harness `/home/agent/.claude` on the agents box). This is a trimmed copy of the
host `~/.claude/rules/environment-bindings.md` — only the tools present on the agents-VPS runtime (or
whose creds are injected at runtime) are listed here. Trading/music/personal host-only tools are
intentionally omitted.

## CLI Maintenance

The custom CLIs (`loki`, `tempo`, `prom`, `pyro`, `pg`, `twenty`, `ol`, `langfuse`, `comp`,
`autumn`, `threads`, `shlink`, `cfdns`, `dokploy`, `pharmia-*`) are bash/curl/jq wrappers and
**SHOULD be proactively improved** when you hit a rough edge — broken output parsing, missing
flags, auth failures, confusing UX. Their SSOT is `templates/pharmia/cli/bin/` in the Paperclip
repo — fix the file there, not the installed symlink. Always leave the CLI easier to use for the
next zero-context agent (add subcommands, improve help text, fix flag names). Compiled binaries
(`gh`, `bx`, `oha`, `gitleaks`) are NOT editable here — bump their pinned version in the Dockerfile.

**Gap-driven improvement rule.** If you ran a CLI and had to reach for another tool (a raw API
call, raw SQL, web search, …) to answer the question, that's a gap in the first CLI. Fix it in the
same task so the next zero-context agent gets the answer from one invocation. The default
invocation should answer the headline question without follow-up calls.

## Secrets & Vaults

**Never hardcode a secret** in code / a CLI / a compose file — push-protection blocks it. Read from injected env or a vault. Two backends, deliberate split:
- **HashiCorp Vault** (`vault.bentostudio.io`, KV-v2 + AppRole, path-scoped `secret/{agents,dev,paperclip}/*`) = MACHINE / dev / service secrets (API keys, infra tokens, PG passwords). Consume via varlock's `hashicorp-vault` plugin or the `vault` HTTP API.
- **Vaultwarden** (`vaultwarden.bentostudio.io`, SSO-only) = HUMAN / shared logins. The agents' scoped service account reads its org collections (NOT card/bank/tax) → **`vault-pass <item-id>`** fetches one password non-interactively (used by himalaya + varlock `exec()`).
- **varlock** validates + injects env at runtime (`.env.schema` with `@required`/`@sensitive`; `varlock run -- <cmd>` injects + redacts). `process.env` always wins, so Dokploy-injected env keeps working as a fallback.

## Research Toolkit

Priority-ordered sources for investigations. Work top-down, stop when covered.

1. **Internal** — codebase grep/glob, Outline (`ol`), prior sessions.
2. **GitHub** — `gh` CLI for upstream repos, issues, PRs, releases.
3. **Library Docs** — Context7 MCP: `resolve-library-id` then `query-docs`.
4. **Source Cloning** — `git clone --depth 1` to `/tmp/`, grep the source.
5. **Web Search** — `bx web "query"` (Brave), or `curl_cffi` / `camofox` for protected pages — last resort.

## Tools

Observability (prod is READ-ONLY — canary tokens / read-only PG role):
- **loki** — `loki <env> search|errors|warnings|count "text"` (LogQL). Scope `{service_name="pharmia-api"}`. Flags `--since`, `--limit`, `--oldest`, `--service`.
- **tempo** — distributed trace search / lookup (latency, failures, follow a trace id from logs).
- **prom** — PromQL, alerts, scrape targets. Grafana alert triage: `prom <env> grafana-alerts`, `grafana-history`.
- **pyro** — continuous profiling (CPU/wall/heap) for perf/memory/GC investigations.

Pharmia dev / data:
- **pg** — `pg <env> <db>` Postgres over SSH tunnel. dev/qa read-write; canary/prod is the READ-ONLY role.
- **threads** — agent-thread inspector. `threads <admin-url>` (auto-detect env) or `threads <env> <id>`; default RCA-grade, plus `--rca`/`--summary`/`--tools`/per-thread modes and `modelmix <env>` for the fleet model split; see `threads --help`. Backed by `pg <env> mastra`.
- **langfuse** — AI trace inspection. `langfuse api traces list …`; **always** pass `--limit` or a time filter (unfiltered list 422s); no server-side text search — pipe through jq. Output-shaping flags and the `observations-v2s` gotcha: `langfuse --help`.

Knowledge / compliance:
- **ol** — Outline wiki (`search`, `doc get|update|create|list`, `verify`, `linkcheck`). Quebec docs + agent skills live there.
- **comp** — Comp AI GRC (policies/controls/frameworks/tasks/evidence; `sql` escape hatch). **read-write** on this runtime.

Services / billing:
- **twenty** — `twenty gql '...'` / `twenty objects|fields` Twenty CRM (auto-JWT).
- **autumn** — Autumn billing (customers/products/check/track/attach). Reads `AUTUMN_SECRET_KEY` from env (live key — read commands only).
- **shlink** — short links + visit analytics + QR.
- **cfdns** — Cloudflare DNS (always `proxied:false`). dev-scoped token only on this runtime.
- **dokploy** — Dokploy ops (`apps`, `status`, `logs`, `env-set`). Only the bento dev/qa instance config on this runtime.
- **pharmia-git** — git/release workflow (`topology`, `extra`, `ff-all`, `confine`, `deploy-status`).
- **pharmia-tenant** / **pharmia-rc** — tenant provisioning / host Remote Control (prod-capable; dev/qa-scoped on this runtime).

Security:
- **gh** — GitHub CLI for issues, PRs, checks, releases, API. Requires `GITHUB_APP_*`/token (injected).
- **gitleaks** — secret scanning. `gitleaks detect --source .` before committing, during security audits.
- **oha** — HTTP load testing. Validate perf fixes / reproduce load issues.

Web / scraping (two browser engines — both baked, do NOT run both heavy in parallel; 4 GB RAM ceiling):
- **bx** — Brave Search CLI. `bx web "query"`. Requires `BRAVE_SEARCH_API_KEY` (injected). Parse JSON with python3/jq; modes/flags via `bx --help`.
- **curl_cffi** — Python (`from curl_cffi.requests import Session`) forging TLS fingerprints to bypass WAF/Cloudflare. `Session(impersonate='chrome136')`. Try before a headless browser — faster, zero RAM overhead.
- **camofox** — anti-detect Firefox (Camoufox), the **anti-detect browser** for bot-protected sites (Cloudflare/Akamai/DataDome). `camofox start`, `camofox tab <url>`, `camofox snap <tabId>`, `camofox click <tabId> <ref>`, `camofox screenshot <tabId>`, `camofox stop`. Uses Xvfb for full anti-detection.
- **agent-browser** — compatibility shim that **delegates to `camofox`** (no separate binary). Use camofox directly when you can; agent-browser exists for callers that use its verb names.
- **playwright / chromium** — baked for e2e (PharmaMate's pinned version). Use for the app's Playwright suite, NOT for evading anti-bot systems (use camofox for that).
