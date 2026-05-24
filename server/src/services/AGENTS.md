# AGENTS.md — `server/src/services/`

Backend service layer. Each file owns one capability (auth, costs, agents,
portability, …). Routes in `server/src/routes/` are thin wrappers around
these services. When editing here, also check the matching route file and the
schema in `packages/db/src/schema/`.

## 1. Company portability pipeline

`company-portability.ts` (4709 lines) is the single source of truth for
parsing template packages and the import/export round-trip. Do not duplicate
its parsing logic elsewhere; extend it in place.

Key functions:

- `parseFrontmatterMarkdown(raw)` (line 2279) — extracts YAML frontmatter
  from any `*.md` file. Returns `{ frontmatter, body }`.
- `readAgentSkillRefs(frontmatter, defaults)` (line 2427) — merges
  frontmatter `skills:` with `defaults.yaml` and applies `excludeSkills:`
  opt-out. Dedup via `Set`.
- `readAgentDefaultSkills(files)` (line 2451) — finds `agents/defaults.yaml`
  and returns the merged baseline list. See `templates/AGENTS.md` for the
  authoring contract.
- `buildManifestFromPackageFiles(files, opts?)` (line 2470) — top-level
  parser. Walks the file tree, parses `COMPANY.md`, every agent's
  `AGENTS.md`, every skill, projects, tasks. Returns the `ResolvedSource`
  the import flow consumes.
- Exporter starts around line 1986 — re-emits the resolved skill list per
  agent (loses `defaults.yaml` DRY structure; see `templates/AGENTS.md` §3).

### Import modes

- `agent_safe` — initiated by a company member via
  `POST /api/companies/:companyId/imports/{preview,apply}`
  (`server/src/routes/companies.ts`). Restricted: cannot replace, cannot
  target another company.
- `instance` — initiated by an instance admin via the CLI. Can replace,
  can target any company.

### Collision strategies (the safe route restrictions)

`server/src/routes/companies.ts:223` (preview) and `:239` (apply) both
throw `forbidden("Safe import route does not allow replace collision
strategy")`. So in `agent_safe` mode only `skip` and `rename` work. Replace
is reserved for instance-mode imports. See the `paperclip-loader` skill
for the full collision matrix.

## 2. Board auth tier

`board-auth.ts` (359 lines). Board access = full-control operator context;
distinct from agent API keys.

- Token format: `pcp_board_<48 hex>` (`createBoardApiToken`, line 29).
- Storage: `keyHash` column on `board_api_keys` (schema:
  `packages/db/src/schema/board_api_keys.ts`). Plaintext is never stored.
  Hashing via `hashBearerToken` at line 19 = `sha256(token).digest("hex")`.
- TTL: `BOARD_API_KEY_TTL_MS = 30 * 24 * 60 * 60 * 1000` (line 14). Compute
  expiry with `boardApiKeyExpiresAt(nowMs)` (line 37).
- **No public mint endpoint exists.** A board key is minted via direct DB
  INSERT — typically the CLI auth challenge flow
  (`createCliAuthChallenge` line 163, `approveCliAuthChallenge` line 257),
  or manual SQL during local bootstrap. When you script a mint:
  1. Generate token via `createBoardApiToken()`.
  2. INSERT `(userId, name, keyHash, expiresAt)` where `keyHash =
     hashBearerToken(token)`.
  3. Escrow the plaintext token out of band; log the `name` (purpose) and
     `userId`.
  4. Set `expiresAt` — never leave NULL on a board key in production.

## 3. Agent-instructions runtime authority

`agent-instructions.ts:6` defines `ENTRY_FILE_DEFAULT = "AGENTS.md"`. The
runtime reads the on-disk file at
`/paperclip/instances/<company>/instructions/<agentSlug>/AGENTS.md`
(resolved through `resolvePaperclipInstanceRoot`).

The `systemPrompt` field on the agent API response is **empty by design**.
The actual prompt is the on-disk `AGENTS.md`. An agent that fetches its own
config over the API and reads `systemPrompt` will see nothing — it must
read the on-disk file (or rely on the adapter to load it for it). UI edits
write to the DB (and, in managed mode, sync to disk via this service); they
do not write back to `templates/`.

Bundle modes (`BundleMode` at line 28): `"managed"` (Paperclip owns the
files; UI edits sync to disk) and `"external"` (the on-disk path is owned
by the operator; the UI is read-only).

## 4. FK delete ordering (cascade audit)

Several delete paths require explicit ordering because not every FK uses
`onDelete: "cascade"`. Recent fix `b34d1b6a` (May 2026): the agent delete
transaction in `agents.ts` deletes `cost_events` (scoped to the agent's
heartbeat runs) **before** `heartbeat_runs`, otherwise the FK constraint
`cost_events_heartbeat_run_id_heartbeat_runs_id_fk` rejects the
transaction for any agent that has incurred costs.

See `packages/db/AGENTS.md` §2 for the full ordering table — keep that
table in sync whenever you add a new operational table that references a
parent without cascade.

## 5. The `X-Paperclip-Run-Id` audit header

Set by every agent on mutating requests. Read in
`server/src/middleware/auth.ts:36` and stored on `req.actor.runId`. Every
mutation in this services directory that runs under an agent actor should
treat the run-id as the audit attribution; pass it through to
`activity_log` inserts where the schema allows. The adapter registry
documents this header to adapters at `server/src/adapters/registry.ts:426`.

## 6. Cron / routine wake-up chain

`cron.ts` (373 lines) is the cron parser + next-run calculator (5-field
cron). Routines stored in the DB use these helpers to compute the next
fire time; the heartbeat scheduler reads them and dispatches a wake-up to
the agent runtime, which in turn invokes the configured adapter. Routines
do not fire `AGENTS.md` directly — they enqueue a heartbeat run, and the
adapter loads instructions from the on-disk path described in §3.
