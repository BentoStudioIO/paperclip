# AGENTS.md

Guidance for human and AI contributors working in this repository.

## 1. Purpose

Paperclip is a control plane for AI-agent companies. V1 build contract is `doc/SPEC-implementation.md`.

## 2. Read This First

Before making changes, read in order: `doc/GOAL.md`, `doc/PRODUCT.md`, `doc/SPEC-implementation.md`, `doc/DEVELOPING.md`, `doc/DATABASE.md`. `doc/SPEC.md` is long-horizon context; `doc/SPEC-implementation.md` is the concrete V1 contract.

## 3. Repo Map

- `server/` — Express REST API and orchestration services
- `ui/` — React + Vite board UI
- `packages/db/` — Drizzle schema, migrations, DB clients
- `packages/shared/` — shared types, constants, validators, API path constants
- `packages/adapters/` — agent adapter implementations (Claude, Codex, Cursor, etc.)
- `packages/adapter-utils/` — shared adapter utilities
- `packages/plugins/` — plugin system packages
- `doc/` — operational and product docs

## 4. Dev Setup (Auto DB)

Embedded PGlite is used in dev if `DATABASE_URL` is unset.

```sh
pnpm install && pnpm dev
```

API + UI both served on `http://localhost:3100` (UI via dev middleware). Health: `curl http://localhost:3100/api/health`. Reset local DB: `rm -rf data/pglite && pnpm dev`.

## 5. Core Engineering Rules

1. **Keep changes company-scoped.** Every domain entity is scoped to a company; enforce company boundaries in routes/services.
2. **Keep contracts synchronized.** Schema/API behavior changes must propagate through `packages/db`, `packages/shared`, `server`, and `ui`.
3. **Preserve control-plane invariants.** Single-assignee task model, atomic issue checkout, approval gates for governed actions, budget hard-stop auto-pause, activity logging for mutations.
4. **No wholesale strategic-doc rewrites unless asked.** Prefer additive updates; keep `doc/SPEC.md` and `doc/SPEC-implementation.md` aligned.
5. **Dated plans in `doc/plans/`** as `YYYY-MM-DD-slug.md`. If a Paperclip issue asks for a plan, update the issue `plan` document per the `paperclip` skill instead of creating a repo file.

6. Attach inspectable generated artifacts.
When your task produces a user-inspectable file, follow the Paperclip skill's "Generated Artifacts and Work Products" workflow before final disposition. In this repo, prefer the self-contained skill helper at `skills/paperclip/scripts/paperclip-upload-artifact.sh` so the file is available through the Paperclip API, create/update an artifact work product when the file is the deliverable, link the uploaded artifact in the final issue comment, and then set status. Do not rely on local filesystem paths as the only access path. See `doc/AGENT-ARTIFACTS.md` for `.mp4` and `.webm` examples.

## 6. Database Change Workflow

1. Edit `packages/db/src/schema/*.ts` and export new tables from `packages/db/src/schema/index.ts`.
2. `pnpm db:generate` (compiles `packages/db` first; drizzle reads `dist/schema/*.js`).
3. `pnpm -r typecheck` to validate.

## 7. Verification Before Hand-off

Default: `pnpm test` (Vitest only). Browser suites are opt-in: `pnpm test:e2e`, `pnpm test:release-smoke` — run only when your change touches them or you're verifying CI/release.

For normal issue work, run the smallest relevant check first. Do not default to repo-wide typecheck/build/test on every heartbeat. Before a PR-ready hand-off or for broad changes:

```sh
pnpm -r typecheck && pnpm test:run && pnpm build
```

If anything cannot be run, explicitly report what and why.

## 8. API and Auth Expectations

- Base path: `/api`
- Board access = full-control operator context
- Agent access via bearer API keys (`agent_api_keys`), hashed at rest; keys must not cross companies

When adding endpoints: apply company access checks, enforce actor permissions (board vs agent), write activity log entries for mutations, return consistent HTTP errors (`400/401/403/404/409/422/500`).

## 9. UI Expectations

- Keep routes and nav aligned with available API surface
- Use company selection context for company-scoped pages
- Surface failures clearly; never silently ignore API errors

## 10. Pull Request Requirements

When opening a PR (via `gh pr create` or any other method), read and fill in every section of `.github/PULL_REQUEST_TEMPLATE.md` — do not craft ad-hoc PR bodies. Required sections:

- **Thinking Path** — reasoning from project context to this change (see `CONTRIBUTING.md`)
- **What Changed** — concrete changes
- **Verification** — how a reviewer confirms it works
- **Risks** — what could go wrong
- **Model Used** — AI model (provider, exact ID, context window, capabilities) or "None — human-authored"
- **Checklist** — all items checked

## 11. Definition of Done

1. Behavior matches `doc/SPEC-implementation.md`
2. Typecheck, tests, and build pass
3. Contracts synced across db/shared/server/ui
4. Docs updated when behavior or commands change
5. PR description follows the template with all sections filled in (including Model Used)

## 12. Bento Fork (BentoStudioIO/paperclip)

Bento Studio's fork of `paperclipai/paperclip`, branch `master`. Foundation for Bento's internal AI company and future sellable template. `CLAUDE.md` is a symlink to this file.

### Fork strategy — keep the delta minimal

Upstream ships breaking changes daily. The fork stays cheap only if customization stays on the edges.

- **Never edit `server/`, `ui/`, or `packages/db/` core.** Customize via the plugin system and external adapter plugins (`~/.paperclip/adapter-plugins.json`).
- Sync `upstream/master` weekly; rebase, never merge; keep history linear.
- Pin a `stable` release tag for anything run in earnest — never track `canary`.
- Current fork delta — keep it this small: PocketID OIDC sign-in, invite-only mode, `claude-local` host-DB-env strip security fix.

### Deployment

- Deployed via Dokploy on the Bento VPS at `paperclip.bentostudio.io`.
- Dokploy builds the image from `docker-compose.yml` (repo `Dockerfile`) and **auto-deploys on every push to `master`** — no registry, no manual image push.
- `.github/workflows/docker.yml` is **manual-only** (`workflow_dispatch`); the ghcr image is no longer consumed — use only for ad-hoc/rollback builds.

### Org-as-code

- A Paperclip company is version-controlled as a canonical markdown package under `templates/<company>/` — `COMPANY.md` + `agents/<slug>/AGENTS.md` + `skills/<slug>/SKILL.md` + `.paperclip.yaml`. Deprecated `paperclip.manifest.json` must not be used.
- Edit the package in git, then apply with `paperclipai company import templates/<company> --target existing --company-id <id> --dry-run`.
- `.paperclip.yaml` is the manifest and source of truth. An `agents/<slug>/AGENTS.md` alone is **invisible** — also register the agent under the `agents:` block (role + adapter config) **and** in `sidebar.agents`.
- **Push + redeploy does NOT sync templates into a running company.** Dokploy rebuilds the server image; the Postgres volume persists; there is no seed/import on boot. Template changes only reach the live company when someone runs `paperclipai company import ... --target existing --company-id <id>`.

### Sources of truth (per agent)

1. **Template** — `templates/<company>/agents/<slug>/AGENTS.md` is the import seed. See `templates/AGENTS.md` for the authoring contract.
2. **Database** — UI edits write here. Survives redeploys. Authority for the running company.
3. **Runtime file** — `/paperclip/instances/<company>/instructions/<slug>/AGENTS.md` is what the adapter actually reads. See `server/src/services/AGENTS.md` §3.

UI edits live only in the DB; they get clobbered by a future `--collisionStrategy replace` import. Decide which side is source of truth per agent.

## 13. Company portability quick map

- `templates/AGENTS.md` — org-as-code authoring (directory layout, `.paperclip.yaml` schema, `defaults.yaml` inheritance, skill key namespacing).
- `server/src/services/AGENTS.md` — portability pipeline, board auth tier, runtime instructions authority, FK delete ordering, `X-Paperclip-Run-Id` audit header.
- `packages/db/AGENTS.md` — schema invariants, FK delete order table, migration workflow, PGlite/Postgres parity.

## 14. Skill directories: who reads what

- `skills/` — runtime skills installed *into agents* (e.g., `paperclip`, `paperclip-dev`). The adapter copies these into the agent's working directory at heartbeat time.
- `.agents/skills/` — *contributor* workflows for working *on* Paperclip itself (release, pr-report, doc-maintenance). Not shipped to agents.
- `.claude/skills/` — Claude Code consumer skills for users running Claude Code locally on this repo. May overlap with the other two; pick the directory by audience.

Decision tree: authoring a skill that runs *inside* a deployed agent → `skills/`. A workflow for editing this repo → `.agents/skills/`. A skill for Claude Code users on the repo → `.claude/skills/`.

## 15. Agent & skill sync (Paperclip → local harnesses)

Paperclip is the single source of truth for agent and skill definitions; `git pull` projects them into your local Claude Code / Codex / OpenCode with no manual step.

- **One-time setup (new clone):** `git config core.hooksPath .githooks` (also needs `node` and network for `npx rulesync`). The `post-merge`/`post-checkout` hooks then run the sync on every pull/checkout.
- **Agents** — `scripts/sync-claude-agents.mjs` extracts the Claude-format frontmatter block + body from `templates/pharmia/agents/<slug>/AGENTS.md` → `~/.claude/agents/<name>.md`, then `rulesync convert --from claudecode --to codexcli,opencode --features subagents --global` mirrors to `~/.codex/agents/` + `~/.config/opencode/agent/`.
- **Skills** — `scripts/sync-claude-skills.mjs` writes `templates/pharmia/skills/company/<co>/<slug>/SKILL.md` (+ support files) to `~/.claude/skills/<name>/` as **real dirs** (portable — no dependency on any shared `~/.agents` store), strips Paperclip-internal keys (`slug`/`metadata`/`key`), normalizes `allowed-tools` to an array, then rulesync mirrors `--features skills` to codex/opencode.
- **Marker = `source: paperclip`** (frontmatter key). It's the prune key: generated files are overwritten/removed on sync; anything without it (hand-authored or skills.sh installs) is never touched.
- Run manually with `node scripts/sync-claude-agents.mjs` / `sync-claude-skills.mjs` (`--dry-run`, `--verbose`, `--no-rulesync` supported).
