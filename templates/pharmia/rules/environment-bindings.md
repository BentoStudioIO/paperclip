# Environment Bindings — Pharmia agent sandbox

Tool and CLI bindings available **inside the Daytona agent sandbox**. This is a trimmed
copy of the host `~/.claude/rules/environment-bindings.md` — only the tools that are baked
into the agent-runtime image (or whose creds are injected at runtime) are listed here.
Trading/music/personal host-only tools are intentionally omitted.

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
- **threads** — agent-thread inspector. `threads <admin-url>` (auto-detect env) or `threads <env> <id>`; default RCA-grade; `--rca` `--summary` `--tools` `--last` `--raw` `--json`; `modelmix <env>`. Backed by `pg <env> mastra`.
- **langfuse** — `langfuse api traces list --limit 20 --tags atlas --json`. Always `--limit`/time filters (unfiltered list 422s). Use `--fields core,metrics`; `observations-v2s` not `observations`. No server-side text search — pipe through jq.

Knowledge / compliance:
- **ol** — Outline wiki (`search`, `doc get|update|create|list`, `verify`, `linkcheck`). Quebec docs + agent skills live there.
- **comp** — Comp AI GRC (policies/controls/frameworks/tasks/evidence; `sql` escape hatch). **read-write** in the sandbox.

Services / billing:
- **twenty** — `twenty gql '...'` / `twenty objects|fields` Twenty CRM (auto-JWT).
- **autumn** — Autumn billing (customers/products/check/track/attach). Reads `AUTUMN_SECRET_KEY` from env (live key — read commands only).
- **shlink** — short links + visit analytics + QR.
- **cfdns** — Cloudflare DNS (always `proxied:false`). dev-scoped token only in the sandbox.
- **dokploy** — Dokploy ops (`apps`, `status`, `logs`, `env-set`). Only the bento dev/qa instance config in the sandbox.
- **pharmia-git** — git/release workflow (`topology`, `extra`, `ff-all`, `confine`, `deploy-status`).
- **pharmia-tenant** / **pharmia-rc** — tenant provisioning / host Remote Control (prod-capable; dev/qa-scoped in the sandbox).

Security:
- **gh** — GitHub CLI for issues, PRs, checks, releases, API. Requires `GITHUB_APP_*`/token (injected).
- **gitleaks** — secret scanning. `gitleaks detect --source .` before committing, during security audits.
- **oha** — HTTP load testing. Validate perf fixes / reproduce load issues.

Web / scraping (two browser engines — both baked, do NOT run both heavy in parallel; 4 GB RAM ceiling):
- **bx** — Brave Search CLI. `bx web "query"` (use `web` mode; `context` mode is broken). Requires `BRAVE_SEARCH_API_KEY` (injected). Parse JSON with python3/jq.
- **curl_cffi** — Python (`from curl_cffi.requests import Session`) forging TLS fingerprints to bypass WAF/Cloudflare. `Session(impersonate='chrome136')`. Try before a headless browser — faster, zero RAM overhead.
- **camofox** — anti-detect Firefox (Camoufox), the **anti-detect browser** for bot-protected sites (Cloudflare/Akamai/DataDome). `camofox start`, `camofox tab <url>`, `camofox snap <tabId>`, `camofox click <tabId> <ref>`, `camofox screenshot <tabId>`, `camofox stop`. Uses Xvfb for full anti-detection.
- **agent-browser** — compatibility shim that **delegates to `camofox`** (no separate binary). Use camofox directly when you can; agent-browser exists for callers that use its verb names.
- **playwright / chromium** — baked for e2e (PharmaMate's pinned version). Use for the app's Playwright suite, NOT for evading anti-bot systems (use camofox for that).
