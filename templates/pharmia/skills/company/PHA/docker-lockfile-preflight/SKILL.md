---
name: "docker-lockfile-preflight"
description: "Reproduce the prod Docker install resolution locally BEFORE pushing any package.json / package-lock.json / Dockerfile change. Pharmia auto-deploys on push, so a lockfile gap deploys a broken build. Concrete commands for the node:24 + npm ci --legacy-peer-deps path, plus @mastra/* sibling-pin sanity. Host node_modules reuse hides the gap — this forces a clean resolve."
slug: "docker-lockfile-preflight"
metadata:
  paperclip:
    slug: "docker-lockfile-preflight"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/docker-lockfile-preflight"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/docker-lockfile-preflight"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/docker-lockfile-preflight"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/docker-lockfile-preflight"
---

# Docker Lockfile Preflight

Run this BEFORE pushing any change to `package.json`, `package-lock.json`, a
`Dockerfile*`, an npm script, or a postinstall hook. Pushing a branch
auto-deploys to its env (Dokploy git webhook) — a lockfile that doesn't resolve
under the prod install flags turns the remote build into a slow guess-and-check
loop that blocks everyone. Host `check-types` / `npm ls` REUSE existing
`node_modules` and will pass while the clean Docker install fails. Reproduce the
clean resolve locally.

## Environment — Verified Node 24 / npm 11 (NOT 22)
The repo is **Node 24 / npm 11** (root `package.json` `engines: node 24.x /
npm 11.x`). All prod Dockerfiles are `node:24`:
- `apps/api/Dockerfile.prod` → `node:24-trixie` (installer) / `node:24-trixie-slim`
  (runner)
- `apps/web/Dockerfile.prod` → `node:24-alpine`

> The older "`nvm use 22` for Pharmia lockfiles" guidance (global CLAUDE.md and
> some memos) is STALE — Node 22 now fails `EBADENGINE`. Regenerate the lockfile
> on Node 24.

```sh
nvm use 24
node -v   # expect v24.x
npm -v    # expect 11.x
```

## Match the Prod `npm ci` Flags EXACTLY
The flags differ per app — a `--dry-run` with the wrong flags is a false pass:
- **api** (`apps/api/Dockerfile.prod`):
  `npm ci --include=dev --legacy-peer-deps --prefer-offline --no-audit --fund=false`
  (and a second `--omit=dev` install for the runner stage).
- **web** (`apps/web/Dockerfile.prod`): `npm ci --legacy-peer-deps`

## Tier 1 — Fast Smoke (clean resolve, no node_modules write)
Surfaces "Missing: X from lock file" / peer-dep conflicts in seconds:
```sh
nvm use 24
npm ci --legacy-peer-deps --dry-run
```
If you changed deps, regenerate the lock cleanly first (don't hand-edit it):
```sh
nvm use 24 && npm install --legacy-peer-deps   # regenerates package-lock.json
git diff --stat package-lock.json
```

## Tier 2 — Gold Standard (build the affected stage)
The only thing that actually proves the prod build resolves is building the stage
that installs:
```sh
docker build --target installer -f apps/api/Dockerfile.prod .
docker build --target installer -f apps/web/Dockerfile.prod .
# designer ships its own pruned image — build that too if touched:
docker build --target installer -f apps/designer/Dockerfile.prod .
```
Drop the `--mount=type=cache` lines mentally — a clean build context is the test.

## `@mastra/*` Sibling-Pin Sanity (the recurring trap)
Mastra packages are version-locked siblings. `@mastra/core` is pinned in root
`package.json` `overrides` (currently `1.37.1`) AND listed at the same version in
`packages/api/package.json`. The other `@mastra/*` deps
(`memory`, `pg`, `langfuse`, `observability`, `otel-bridge`, `rag`, `s3`,
`auth-better-auth`, `loggers`) must be mutually compatible with that core.
- [ ] If you bump ANY `@mastra/*`, confirm `@mastra/core` in the root `overrides`
  and `packages/api/package.json` still agree, and that no sibling pulls a
  different transitive `@mastra/core` (`npm ls @mastra/core` after a clean
  install should show ONE version).
- [ ] Never bump one mastra package alone "to fix a type error" — bump the set.

## Checklist
- [ ] On Node 24 (`nvm use 24`), not 22.
- [ ] Lockfile regenerated with `npm install`, not hand-edited.
- [ ] `npm ci --legacy-peer-deps --dry-run` clean (Tier 1).
- [ ] `docker build --target installer` of each affected app succeeds (Tier 2).
- [ ] `npm ls @mastra/core` resolves to a single pinned version.
- [ ] Only THEN push (and on shared branches `git fetch` + confirm fast-forward).

The pre-push schema-drift hook checks DB shape only — it does NOT catch install
failures. Don't rely on it.

## DRY
Deploy mechanics / Dokploy compose ids → **`pharmia-infra`**. Model/agent config
changes → **`model-config-gate`**. This skill owns ONLY the pre-push build
reproduction.
