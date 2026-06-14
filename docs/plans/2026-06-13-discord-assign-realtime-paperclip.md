# Real-Time Discord → Agent Assignment on Paperclip (port of vortex `/assign`)

> **For agentic workers:** Implement with subagent-driven-development (fresh subagent per task + two-stage review). Steps use checkbox (`- [ ]`) syntax. Implementers commit locally only — never push/install to the live container without the cutover gate.

**Goal:** Wake a Paperclip agent in real-time when a Discord message matches a stored channel+regex assignment (vortex `/assign` parity), make assignments editable via a `/clip assign` slash command, give the awoken agent read-only canary `app`+`mastra` access, then migrate the 3 live vortex watchers and unwire vortex's watchers.

**Architecture:** Fork the third-party `paperclip-plugin-discord` (v0.9.1) into Forgejo, extend its already-real-time gateway `handleMessageCreate` to evaluate stored assignments and `ctx.agents.invoke` the mapped agent with the FULL serialized message + the assignment's verbatim prompt; add `/clip assign|unassign|assignments` subcommands persisting to `plugin_state`; create `signup-ingest` + `booking-ingest` + `translate-fr` agents (verbatim vortex prompts); add a `discord-post` CLI + canary-RO `pg`/`threads` to the agent runtime so the awoken agent can read canary and post its result back. Cut over on one real signup, then `/clip unassign` the vortex watchers.

**Tech Stack:** TypeScript (plugin, `@paperclipai/plugin-sdk`), Discord Gateway v10 + REST, Paperclip org-as-code agents (AGENTS.md), bash CLIs, Postgres `plugin_state`, SSH forced-command RO Postgres.

---

## DECISIONS (CTO, 2026-06-14) — resolve the plan's open questions

1. **Channel (resolves Q2/Law-25):** REUSE the existing channel `1485869100952588309` for signups — do NOT create a new channel and do NOT change the relay. The bot's gateway will receive all messages on that channel, but the engine MUST wake an agent / persist / forward ONLY on a regex-matched assignment (the signup embed); non-matching messages (incl. clinical Atlas Q&A) are dropped in-handler, never persisted, never sent to an agent. Verify+grant the bot View Channel + Read History on `1485869100952588309` (Discord perms) before Phase 6. CTO accepts the gateway *receiving* (not processing) clinical content on this channel.
2. **Migrate ALL 3 watchers (resolves Q3 / Task 4.4):** Build the Arabic→French translator on Paperclip too — use the Task 4.4 fallback `translate-fr` agent with the verbatim "Arabic" prompt. Phase 6 removes ALL 3 vortex watchers (signup + booking + arabic). vortex stays running for `/ask` only. The translator agent reads the Atlas Q&A on `1485869100952588309` (consistent with decision 1 — the bot is on that channel).
3. **Mastra RO (resolves Q1 / Task 5.1):** APPROVED — extend the `pharmia_readonly` role + `prod-ro` forced-command to the canary mastra container, read-only (SELECT-only, NOSUPERUSER), per Task 5.1. The agent must read canary `app` AND `mastra` (threads), read-only, no superuser, no write.

---

## Context

**Current vortex `/assign` (being replaced).** `~/vortex-claude/src/bot.ts`:
- `/assign` (`:1352`) / `/unassign` (`:1387`) write to SQLite `assignments(channel_id, pattern, prompt, created_by, created_at)` via `store.setAssignment` (`src/sessions.ts:365`).
- Real-time dispatch: gateway `MESSAGE_CREATE` → `index.ts:733`/`:550` → `store.getAssignments(channelId)` → `handleAssignedMessage(d, assignments)` (`bot.ts:1650`).
- `handleAssignedMessage`: first assignment whose `pattern` (case-insensitive substring over content+embeds) matches wins; serializes embeds in FULL (`serializeEmbeds`, `bot.ts:1632`, NO truncation); injects the assignment's verbatim prompt as a context prefix; runs the agent; posts the result back to the channel via `ChannelPoster`.
- 3 live assignments (verbatim prompts captured below in Tasks) in `~/vortex-claude/sessions.db`:
  - `1485869100952588309` pattern `New signup` → enrich/create Twenty Person + ownership detection + signup Note.
  - `1423469520437252157` pattern `New Booking` → Twenty Opportunity.
  - `1485869100952588309` pattern `ا` (Arabic char) → translate last Atlas Q&A embed (pure LLM).

**Paperclip deployed plugin (`paperclip-plugin-discord` v0.9.1, author mvanhorn).** Container `paperclip-vyblt8-server-1` on `bento`; source at `/paperclip/.paperclip/plugins/node_modules/paperclip-plugin-discord/dist/`. Public repo `github.com/mvanhorn/paperclip-plugin-discord`. Bot `1515174537153482843`. SDK `@paperclipai/plugin-sdk` (source in this repo at `packages/plugins/sdk/`).
- **Gateway is ALREADY real-time** (`dist/gateway.js`): op-0 `MESSAGE_CREATE` → `onMessage` callback, with full reconnect/heartbeat/resume + `gatewayReconnections` metric. Intents include `GUILD_MESSAGES` + `MESSAGE_CONTENT` when `listenForMessages`/`includeMessageContent` are set.
- **`handleMessageCreate`** (`dist/worker.js:211`) is wired as `onMessage` (`:295-300`) but currently only routes REPLIES to escalation/issue mappings. It is gated behind `gatewayNeedsMessages` (`:289`) = true if any of inbound/media/customCommands/proactive/intelligence enabled. **This is the single extension point for real-time assignments.**
- **`register_watch`/`check-watches`** (`dist/proactive-suggestions.js`) are INSUFFICIENT and will NOT be used: `check-watches` is a cron scanning last 50 msgs (20-min window); the custom prompt (`responseTemplate`) only fills the embed, never reaches the agent — the agent gets a HARDCODED generic prompt (`proactive-suggestions.js:137`); message truncated to 300 chars; gated by `enableProactiveSuggestions`.
- **`ctx.agents.invoke(agentId, companyId, { prompt, reason })`** returns `{ runId }` — **FIRE-AND-FORGET** (`packages/plugins/sdk/src/types.ts:1487`). The awoken agent runs async on the agents VPS; its output does NOT return to Discord automatically. **The agent must post its own result back** (vortex did this via `ChannelPoster`; Paperclip agents currently have NO discord-post tool — see Phase 4).
- **Slash commands** are subcommands of one top-level `/clip` command (`dist/commands.js:15` `SLASH_COMMANDS`, `type:1` subcommands). Dispatch: gateway `INTERACTION_CREATE` → `handleInteraction` (`commands.js:282`) → `handleSlashCommand` switch (`:320`). `cmdCtx` carries `{ baseUrl, companyId, token, paperclipBoardApiKey, defaultChannelId, pluginCtx }` (`worker.js:189`). Commands are (re)registered with Discord at startup (`worker.js:200-209`, `registerSlashCommands`).
- **State**: `ctx.state.get/set({ scopeKind, scopeId, stateKey }, value)` → table `plugin_state(plugin_id, scope_kind, scope_id, namespace, state_key, value_json)`, unique on `(plugin_id,scope_kind,scope_id,namespace,state_key)`. Company `Pharmia` = `57cd0843-fe5a-42d5-a6f6-c4e896fee84e`. No watches/assignments stored yet.
- Config: `plugin_config.config_json` keyed by plugin UUID. `resolveCompanyId(ctx)` resolves lazily.

**Deployed values (verified live in `paperclip-vyblt8-db-1`).** Plugin UUID `88682096-ad88-49e3-adf1-fd7c5f598ec8`; bot-token secret-ref `b49f78a1-98c3-4c0d-a3f6-ad4d565a5ffa`; board-API-key ref `911765f3-b768-4d56-a211-09e4446756f2` (authenticated mode); `defaultGuildId` `1354213528097132585`. Current `config_json` has `enableInbound:true` + `enableIntelligence:true` => **`gatewayNeedsMessages` is ALREADY true - the gateway already receives `MESSAGE_CREATE` for in-scope channels today**, so the real-time substrate is live (we only add assignment evaluation). `enableProactiveSuggestions:false`. Critically, `intelligenceChannelIds` ALREADY includes the booking channel `1423469520437252157` but NOT the signup/clinical channel `1485869100952588309` - the bot may currently lack View/Send there; verify+grant before Phase 6 (see Risks/Dependencies). Assignment matching must NOT depend on `intelligenceChannelIds`: once message intents are on the gateway delivers ALL guild messages, and `handleMessageCreate` filters by the assignment's `channelId`.

**Agent identity / canary RO (memory `paperclip-agent-identity`).** Agents run as capped `agent@149.56.13.177` (SSH driver, harness `bento-agent-runtime`). Toolkit baked at `/opt/bento-cli` from `templates/pharmia/cli` (twenty, bx, autumn, curl, gh present). `~/.zshenv` has `PG_DEV_*`/`PG_QA_*` (rw) but **NOT** `PG_CANARY_*`. Canary RO path EXISTS but is **app-DB only**: role `pharmia_readonly` (SELECT-only, NOSUPERUSER) on `pharmia-canary-46uhia-db-1`, reachable via SSH alias `prod-ro` → forced-command `sudo /usr/local/bin/canary-pg-ro-query` (rejects psql `\` metacommands; RO password in root-only file) + helper `pgro "SELECT…"`. The `pg` CLI's `canary` mode instead uses `ssh prod → sudo docker exec → psql -U postgres` (**PROD SUPERUSER — must NOT be granted to the agent**). `threads` shells out to `pg <env> mastra`/`app`, so it inherits the same gap. Provisioning SSOT: `templates/pharmia/agent-runtime/provision-agent-identity.sh`.

## Requirements

1. REQ-001: A Discord message matching a stored (channelId, regex) assignment wakes the mapped agent in real-time (gateway, not cron), with the FULL message (content + all embeds serialized, no truncation) and the assignment's verbatim prompt.
2. REQ-002: Multiple assignments may coexist on one channel; first matching regex wins (vortex parity); non-matching messages are ignored; bot/webhook authors are allowed (signup/booking embeds are posted by webhooks); the bot's OWN messages are excluded to avoid loops.
3. REQ-003: Per-(channel,pattern) cooldown prevents duplicate wakes on the same logical event; dedupe on message id.
4. REQ-004: Assignments are created/listed/removed via Discord slash subcommands (`/clip assign`, `/clip assignments`, `/clip unassign`) with no redeploy, persisted to `plugin_state`. Mutating subcommands are permission-gated.
5. REQ-005: An awoken agent can post its result back to the triggering Discord channel.
6. REQ-006: An awoken agent can read canary `app` AND `mastra` DBs READ-ONLY (`pg canary app`, `pg canary mastra`, `threads <canary…>`) with NO superuser and NO prod write.
7. REQ-007: `signup-ingest` and `booking-ingest` agents exist (org-as-code) carrying the verbatim vortex enrichment/ownership/Twenty-write logic, adapted only so input = the real-time message context; Twenty writes are idempotent (email upsert).
8. REQ-008: After end-to-end proof on ONE real signup (or controlled test post), the 3 vortex watchers are removed; vortex `/ask` stays.
9. REQ-009: No new hardcoded secrets; the bot token stays a secret-ref; the agent's canary access stays read-only/fail-closed; any prod-side grant is flagged for explicit CTO approval before applying.

## File Structure (created/modified)

**Forked plugin** (new Forgejo repo `BentoStudioIO/paperclip-plugin-discord`, clone of mvanhorn@v0.9.1):
- `src/assignments.ts` (NEW) — assignment data model + `plugin_state` CRUD + regex match.
- `src/worker.ts` (MODIFY) — extend `handleMessageCreate` to evaluate assignments; ensure `gatewayNeedsMessages` true; gateway liveness metric/log.
- `src/commands.ts` (MODIFY) — add `assign`/`assignments`/`unassign` to `SLASH_COMMANDS` + handlers in `handleSlashCommand`.
- `src/constants.ts` (MODIFY) — bump version; add `assignmentChannelIds` config default + an `assignmentsCooldownMinutes` default; add metric names.
- `src/manifest.ts` (MODIFY) — add config props for assignment channels + a `enableAssignments` toggle (default true).
- `test/assignments.test.ts` (NEW) — unit tests for match/CRUD/cooldown (uses SDK `testing.ts` harness).

**Agent runtime** (`templates/pharmia/agent-runtime/`):
- `cli/bin/discord-post` (NEW, under `templates/pharmia/cli/bin/`) — post a message to a Discord channel via bot token.
- `provision-agent-identity.sh` (MODIFY) — wire canary RO (`pgro`/`pg canary`/`threads`) for app+mastra; add `DISCORD_BOT_TOKEN` for `discord-post`.

**Canary-RO `pg`/`threads`** (`templates/pharmia/cli/bin/`):
- `pg` (MODIFY) — when targeting `canary`, use the `prod-ro` forced-command RO path (app+mastra) instead of `ssh prod → docker exec psql -U postgres`.

**Agents** (org-as-code, `templates/pharmia/agents/`):
- `signup-ingest/AGENTS.md` (NEW) — verbatim "New signup" prompt, input-adapted.
- `booking-ingest/AGENTS.md` (NEW) — verbatim "New Booking" prompt, input-adapted.
- `translate-fr/AGENTS.md` (NEW) — verbatim "Arabic" prompt (Atlas Q&A → FR), input-adapted; pure-LLM, no canary/Twenty tools.

**Prod-side (flag for CTO, see Phase 5):** extend `/usr/local/bin/canary-pg-ro-query` + `pharmia_readonly` role to the canary mastra container `pharmia-canary-46uhia-mastra_db-1`.

---

## Chunk 1: Architecture decision + plugin fork scaffold

### Decision: FORK-AND-EXTEND (not a companion plugin)
- **Rationale.** A second plugin would open a SECOND Discord gateway connection on the SAME bot token. Discord allows it but it doubles `IDENTIFY`/heartbeat load and both connections receive every `MESSAGE_CREATE` — duplicate wakes unless deduped cross-process, and the two share no `plugin_state` namespace cleanly. The fork reuses the existing live gateway, dedupe, metrics, slash-command registration, and `plugin_state` — minimal new surface, single source of truth. Cost: we own a fork (track upstream).
- The fork's real-time path is essentially already built (op-0 `MESSAGE_CREATE` → `handleMessageCreate`); we add ~one function call + a module. This is the smallest correct change.

### Task 1.1: Fork the plugin into Forgejo
**Files:** new repo `git.bentostudio.io/BentoStudioIO/paperclip-plugin-discord`.
- [ ] Clone upstream at the EXACT deployed version: `git clone --branch v0.9.1 https://github.com/mvanhorn/paperclip-plugin-discord /tmp/ppd-fork` (if no v0.9.1 tag, clone default and `git checkout` the commit whose `package.json` version is `0.9.1`; verify `dist/` matches the container by diffing `dist/worker.js` against `/tmp/pcd/worker.js`).
- [ ] Create the Forgejo repo via `bentoadmin` token; push as `origin`, add `upstream` remote = the github URL.
- [ ] In `package.json`: set `name` to `@bento/paperclip-plugin-discord` (scoped, avoids npm-name collision), bump `version` to `0.9.1-bento.1`, keep `dependencies: {}` (it has none) and `peerDependencies`/`devDependencies` for `@paperclipai/plugin-sdk` + TS.
- [ ] Confirm build: `npm install --legacy-peer-deps && npm run build` produces `dist/` (the plugin compiles TS → `dist/*.js`). Record the build command.
- [ ] **AC:** Forked repo builds clean; `dist/worker.js` byte-diff vs the running container's worker.js is empty (proves we forked the deployed version, not a drifted one).

### Task 1.2: Verify the SDK contract assumptions in the fork's own test harness
**Files:** `test/assignments.test.ts` (scaffold only here).
- [ ] Write a smoke test importing `createTestHarness` (or equivalent) from `@paperclipai/plugin-sdk` `testing.ts` (this repo: `packages/plugins/sdk/src/testing.ts`, which has a mock `agents.invoke` requiring `agents.invoke` capability at `:1629`).
- [ ] Assert `ctx.state.set` then `ctx.state.get` round-trips a JSON value for `{scopeKind:'company', scopeId:'c1', stateKey:'assignments'}`.
- [ ] Assert `ctx.agents.invoke('a1','c1',{prompt:'x',reason:'y'})` resolves to `{runId: string}`.
- [ ] **AC:** Both assertions pass — confirms state + invoke shapes before building on them.

---

## Chunk 2: Assignment data model + real-time engine

### Data model (`plugin_state`)
Stored as ONE row per company: `scopeKind:"company", scopeId:<companyId>, stateKey:"assignments", value_json: { assignments: Assignment[] }`.

```ts
// src/assignments.ts
export interface Assignment {
  id: string;            // `asn_<ts>_<rand>`
  channelId: string;     // Discord channel snowflake (normalized, digits only)
  pattern: string;       // regex source, "" = catch-all (matched case-insensitively)
  agentId: string;       // Paperclip agent UUID to invoke
  prompt: string;        // verbatim assignment instructions injected into the wake prompt
  cooldownSeconds: number; // min gap between wakes for THIS assignment (default 120)
  enabled: boolean;
  createdBy: string;     // discord username
  createdAt: string;     // ISO
  lastTriggeredAt?: string;
}
```
Extensible without redeploy: a new assignment is one `/clip assign` call (append to the array). `agentId`+`prompt` decouple routing from agent definition.

### Task 2.1: assignment module (CRUD + match) — TDD
**Files:** Create `src/assignments.ts`; Test `test/assignments.test.ts`.
- [ ] **Step 1 (test, fails):** `getAssignments(ctx,companyId)` returns `[]` when unset; `addAssignment` then `getAssignments` returns the row; `removeAssignment(byId)` removes it; `findMatch(assignments, channelId, fullText)` returns the FIRST enabled assignment whose `channelId` matches and whose `new RegExp(pattern,'i').test(fullText)` is true (empty pattern = catch-all); invalid regex in `addAssignment` returns an error (mirror `proactive-suggestions.js:27` validation).
- [ ] **Step 2:** Run `npx vitest run test/assignments.test.ts` — expect FAIL (module missing).
- [ ] **Step 3 (impl):** Implement `getAssignments`/`saveAssignments`/`addAssignment`/`removeAssignment`/`listAssignments`/`findMatch`/`isOnCooldown(a,now)` using `ctx.state.get/set` with the schema above. Use the same `scopeKind:"company"` pattern as `proactive-suggestions.js` `getWatches`/`saveWatches` for consistency.
- [ ] **Step 4:** Run vitest — expect PASS.
- [ ] **Step 5:** Commit `feat(assign): assignment data model + match/CRUD`.
- [ ] **AC:** All assignment-module unit tests pass; matching is `new RegExp(pattern,'i').test(fullText)` (case-insensitive regex over content+embeds), FIRST enabled match wins, empty pattern = catch-all. NOTE: this is REGEX, not vortex's case-insensitive **substring** (`bot.ts:1666`) — the CTO chose regex. The 3 migrated patterns are verified regex-metacharacter-free, so each behaves identically to a substring match: `New signup` and `New Booking` contain only `[A-Za-z ]`, and `ا` is a single non-meta Arabic codepoint. `addAssignment` rejects a pattern that fails to compile (mirror `proactive-suggestions.js:27`).

### Task 2.2: real-time evaluation in `handleMessageCreate` — TDD
**Files:** Modify `src/worker.ts` (the `handleMessageCreate` at deployed `worker.js:211`); Modify `src/constants.ts` (cooldown default, metric names); Test extends `test/assignments.test.ts`.
- [ ] **Step 1 (test, fails):** A test that, given a fake `MESSAGE_CREATE` payload from a webhook author on an assigned channel with matching content+embeds, the handler (a) serializes embeds in full, (b) calls `ctx.agents.invoke(assignment.agentId, companyId, { prompt: <wakePrompt>, reason })` exactly once, (c) does NOT invoke for the bot's own messages, (d) respects cooldown (second identical message within cooldown → no second invoke), (e) dedupes by message id. Assert `wakePrompt` CONTAINS the verbatim `assignment.prompt`, the full serialized embed text (no `slice(0,300)`), and the Discord context (channelId, messageId, author, "post your result back to this channel").
- [ ] **Step 2:** vitest — FAIL.
- [ ] **Step 3 (impl):** In `handleMessageCreate`, AFTER the existing reply-routing block, add:
  - **Self-loop guard (exact source):** skip if `message.author?.id === botUserId`, where `botUserId` is captured from the gateway **READY payload's `client.user.id`** (`gateway.js` op-0 `READY` handler — the `payload.d.user.id` field on the `READY` event; the fork already destructures `ready = payload.d` at `gateway.js:111`). Plumb `client.user.id` out of the gateway into `worker.ts` (e.g. an `onReady(botUser)` callback or a shared ref set at READY) and read it in `handleMessageCreate`. Do NOT hardcode the application/bot snowflake as a constant — read it from READY so a token swap can't desync it. Do NOT skip other bots/webhooks (signup/booking embeds are webhook-posted).
  - `const companyId = await resolveCompanyId(ctx);` `const assignments = await getAssignments(ctx, companyId);` filter to `message.channel_id`; if none, return.
  - Build `fullText` = `message.content` + serialized embeds (port vortex `serializeEmbeds` — author/title/description/fields/footer/timestamp; NO truncation). `const match = findMatch(assignments, message.channel_id, fullText);` if none, return.
  - Dedupe by `message.id` (reuse the plugin's existing dedup set/state if present; else a bounded in-memory `Set`).
  - Cooldown: if `isOnCooldown(match, Date.now())` return; else set `lastTriggeredAt=now` and `saveAssignments`.
  - Compose `wakePrompt`:
    ```
    [Channel assignment — real-time trigger]
    [Assignment instructions]
    <match.prompt>
    [End of assignment instructions]

    [Discord context: channelId=<id>, messageId=<id>, author=<username><" (webhook/bot)" if bot>]
    After completing the task, POST your final result to this Discord channel with: `discord-post <channelId> "<message>"`. Post exactly ONE message; do not narrate steps.

    [Triggering message]
    <message.content (if any)>
    <serialized embeds>
    ```
  - `await ctx.agents.invoke(match.agentId, companyId, { prompt: wakePrompt, reason: `Discord assignment ${match.id} on #${message.channel_id}` });` write `METRIC_NAMES.assignmentsTriggered`. Wrap in try/catch + `ctx.logger`.
  - **PHI-safe logging (Law-25, applies to EVERY assignment, mandatory):** the engine's `ctx.logger.*` calls in this handler MUST log ONLY `{ channelId, assignmentId, assignmentPattern, agentId, runId, messageId }` — **NEVER** `message.content`, embeds, `fullText`, or `wakePrompt`. Decision-1's drop-path guarantee (clinical content never logged) is upheld here for signup/booking; for translate-fr the clinical body still goes to the agent (see PHI subsection) but must never enter logs. Add a unit assertion that a spy over `ctx.logger.info/warn/error` receives no call whose args contain the embed body text.
  - Ensure `gatewayNeedsMessages` (`worker.js:289`) includes assignments: add `|| config.enableAssignments !== false` so the gateway listens even if all other features are off.
- [ ] **Step 4:** vitest — PASS.
- [ ] **Step 5:** Commit `feat(assign): real-time wake on matching message via handleMessageCreate`.
- [ ] **AC:** REQ-001/002/003 satisfied by passing tests; the agent is invoked with the verbatim prompt + full embeds + a back-post instruction; self-messages never trigger; cooldown + id-dedupe hold.

### Task 2.3: gateway liveness (the flap that broke vortex)
**Files:** Modify `src/worker.ts`; `src/constants.ts`.
- [ ] The fork's `gateway.js` already has reconnect/heartbeat/backoff + a `gatewayReconnections` metric. ADD a lightweight liveness signal: on each `READY`/`RESUMED`, write `ctx.state.set({scopeKind:'instance',stateKey:'gateway_last_ready'}, {at: ISO})`; register a `ctx.jobs` job `assign-gateway-liveness` (hourly) that reads it and, if `> 15 min` stale, emits a `ctx.logger.error` + `assignmentsGatewayStale` metric (Grafana can alert on it). Do NOT auto-restart (the gateway self-reconnects).
- [ ] **AC:** A stale `gateway_last_ready` produces an error log + metric; a fresh one is silent. (Unit-test the staleness predicate.)

---

## Chunk 3: `/clip assign` slash command

### Task 3.1: command definitions + permission gate — TDD
**Files:** Modify `src/commands.ts` (`SLASH_COMMANDS` `:15`, `handleSlashCommand` switch `:320`); reuse `getGuildRoles` (`discord-api.js:167`) for role gating.
- [ ] **Step 1 (test, fails):** `handleSlashCommand` for `assign` with options `channel`, `prompt`, `agent`, optional `pattern`, optional `cooldown` → calls `addAssignment` and returns an ephemeral confirm; `assignments` → lists rows; `unassign` with `id` (or `channel`+optional `pattern`) → removes; a caller lacking the allowed role gets an ephemeral "no access" and NO state change.
- [ ] **Step 2:** vitest — FAIL.
- [ ] **Step 3 (impl):**
  - Add to `SLASH_COMMANDS` under `/clip` three `type:1` subcommands:
    - `assign`: options `channel` (type 7 channel, required), `agent` (type 3 string, required — agent name or UUID), `prompt` (type 3 string, required), `pattern` (type 3, optional), `cooldown` (type 4 integer seconds, optional).
    - `assignments`: no options (list).
    - `unassign`: `id` (type 3, optional) OR `channel` (type 7, optional) + `pattern` (type 3, optional).
  - In the switch, add `case "assign"/"assignments"/"unassign"`. Resolve `agent` name→UUID via `ctx.agents.list({companyId})` (match by name case-insensitively or accept a UUID). **Validate the `pattern` compiles** (`new RegExp(pattern,'i')` inside try/catch) BEFORE calling `addAssignment`; reject an uncompilable pattern with an ephemeral error and write NO state. (An empty `pattern` is allowed = catch-all.)
  - **Permission gate:** mutating subcommands (`assign`/`unassign`) require the caller's `interaction.member.roles` to intersect a configured `assignmentAdminRoleIds` (new config; if empty, fall back to allowing only the guild admins — fail-closed: if unset AND not admin, deny). `assignments` (read) is open. Mirror vortex `ALLOWED_ROLE_IDS` semantics (`bot.ts:1357`).
  - Use `respondToInteraction({type:4, content, ephemeral:true})` for confirms.
- [ ] **Step 4:** vitest — PASS.
- [ ] **Step 5:** Commit `feat(assign): /clip assign|assignments|unassign subcommands with role gate`.
- [ ] **AC:** REQ-004 — assignments are CRUD-able from Discord, persisted to `plugin_state`, mutation gated; commands re-register at startup via the existing `registerSlashCommands` path (no extra wiring).

### Task 3.2: manifest + config
**Files:** Modify `src/manifest.ts`, `src/constants.ts`.
- [ ] Add config props (`instanceConfigSchema`): `enableAssignments` (bool, default true), `assignmentAdminRoleIds` (string, comma-sep snowflakes), `assignmentsDefaultCooldownSeconds` (number, default 120). Add matching `DEFAULT_CONFIG` keys in `constants.ts`.
- [ ] Manifest `capabilities` already include `agents.invoke`, `plugin.state.read/write`, `agent.tools.register`, `jobs.schedule`, `metrics.write` — no new capability needed. Verify `agents.read` is present (needed to resolve agent name→UUID) — it is (`manifest.js:17`).
- [ ] **AC:** `npm run build` clean; manifest validates; defaults fail-closed (assignments on, but mutation denied when no admin role configured and caller not admin).

---

## Chunk 4: Agent back-post + the agents

### Task 4.1: `discord-post` CLI (the back-post gap)
**Files:** Create `templates/pharmia/cli/bin/discord-post`; Modify `provision-agent-identity.sh` to export `DISCORD_BOT_TOKEN`.
- [ ] `discord-post <channelId> "<message>"` → `POST https://discord.com/api/v10/channels/<id>/messages` with `Authorization: Bot $DISCORD_BOT_TOKEN`, body `{content}` (chunk >2000 chars into multiple posts). Read token from `$DISCORD_BOT_TOKEN`; exit non-zero with a clear message if unset. Reference impl: `~/vortex-claude/src/discord-cli.ts` (REST + `Bot` auth at `:80-142`). Keep it ~40 lines bash+curl, jq for escaping.
- [ ] In `provision-agent-identity.sh` step 5, `ensure_secret DISCORD_BOT_TOKEN "${DISCORD_BOT_TOKEN:-}"` (same env-only, never-hardcoded pattern as the other secrets). Document in the header secret list. Use the SAME bot `1515174537153482843` token (so back-posts come from the Paperclip bot).
- [ ] **AC:** REQ-005 — on the agent VPS as `agent`, `discord-post <test-channel> "ping"` posts a message; missing token → clear error; the CLI is baked via the existing `cli` COPY in the runtime Dockerfile (no Dockerfile change needed since it scans `cli/bin`).

### Task 4.2: `signup-ingest` agent (verbatim prompt, input-adapted)
**Files:** Create `templates/pharmia/agents/signup-ingest/AGENTS.md` (+ bound skills if the existing `crm-triage`/`lead-scouting` skills apply — bind them).
- [ ] AGENTS.md body = the VERBATIM vortex "New signup" prompt (captured below), changed ONLY where input differs:
  - Replace "INPUT (l'embed du webhook 'Pharmia Notifications')" framing with: "INPUT: the triggering Discord message is provided in the wake prompt under [Triggering message] (embeds already serialized). Parse the New Signup embed from there."
  - Replace the final "post UN SEUL message dans le channel" mechanic with: "Post your single final message with `discord-post <channelId> \"…\"` (channelId is in the Discord context)."
  - Keep IDENTICAL: all OPQ lookups (`curl … pharmacists_index.json`), the DB lookup (`pg canary app "SELECT …"`), ownership detection (banner sites, REQ, bx web), identity enrichment when OPQ empty (LinkedIn/orders), the `twenty person upsert` write (email-keyed = idempotent), the `createNote`/`createNoteTarget`, the strict 5-line output format, and the "no narration / stop after one message" rules.
  - Verbatim prompt to embed:
    ```
    Nouveau signup Pharmia. Objectif: enrichir/créer le Person dans Twenty CRM, identifier qui il/elle est, détecter si propriétaire, attacher une Note d'inscription.

INPUT (l'embed du webhook "Pharmia Notifications"):
- title: "New Signup"
- description: "<Nom complet> joined in <tenant friendly>."
- fields: Tenant (ex: "Public", "Pharmaprix X"), User (nom), Source (phone/google/etc)

SOURCES DE DONNÉES (en parallèle si possible):
1. DB Pharmia (slug canonique du tenant + détails compte):
   pg canary app "SELECT id, email, given_name, family_name, name, phone_number, tenant, locale, signup_source, referral_source, attribution, role, license_number, \"createdAt\", onboarding_completed FROM ba_user WHERE name ILIKE '%<nom>%' OR (given_name||' '||family_name) ILIKE '%<nom>%' ORDER BY \"createdAt\" DESC LIMIT 3"
   → garde le slug `tenant` (ex: "app", "pjc-254", "brunet-5050") — c'est ce qui va dans pharmiaTenant.
2. OPQ register (licence + ville + statut pharmacien):
   curl -s 'https://www.opq.org/wp-content/uploads/pharmacist-search/pharmacists_index.json' | jq '[.[] | select(.fullName | test("<nom>"; "i"))]'
3. Autumn (si pertinent — billing/subscription):
   autumn customer get <userId-or-email>

DÉTECTION DE PROPRIÉTÉ (OBLIGATOIRE — JAMAIS SKIPPER):
Ne te limite PAS à "OPQ dit licencié donc PHARMACIST". Beaucoup de signups sont des **propriétaires** (Acces Pharma, Proxim, Pharmaprix, Brunet, Familiprix, Jean Coutu, Uniprix) — c'est la cohorte la plus précieuse. Vérifie systématiquement via les sources suivantes (en parallèle):

a) **Bannière du tenant**: si le tenant du signup est "Pharmaprix X", "Proxim Y", "Acces Pharma Z", "Brunet W", etc., le préfixe est la bannière. Cross-référence avec OPQ (le pharmacien du tenant est très probablement le proprio de ce tenant).

b) **Sites des bannières** — chaque chaîne liste ses propriétaires-pharmaciens publiquement:
   - **Acces Pharma**: bx web "<nom> acces pharma site:accespharma.ca" ou bx web "<nom> propriétaire acces pharma"
   - **Pharmaprix**: bx web "<nom> pharmaprix site:pharmaprix.ca" ou bx web "<nom> propriétaire pharmaprix"
   - **Proxim**: bx web "<nom> proxim site:proxim.ca" ou bx web "<nom> proxim propriétaire"
   - **Brunet**: bx web "<nom> brunet site:brunet.ca"
   - **Familiprix**: bx web "<nom> familiprix site:familiprix.com"
   - **Jean Coutu**: bx web "<nom> jean coutu site:jeancoutu.com"
   - **Uniprix**: bx web "<nom> uniprix site:uniprix.com"
   - **Générique**: bx web "<nom> pharmacien propriétaire <ville OPQ>"

c) **Registre des entreprises Québec (REQ)** — registre public des entreprises:
   bx web "<nom> registraire entreprises quebec pharmacie" ou
   curl -sL "https://www.registreentreprises.gouv.qc.ca/RQEntrepriseGRExt/GR/GR03/GR03A2_19A_PIU_RechEnt_PC/PageRechSimple.aspx?Nom=<nom URL-encodé>" (parse pour entreprises pharma où la personne est administrateur/actionnaire).

d) **Signaux contextuels Pharmia**:
   - signup_source / referral_source = "conference", "demo", "sales": très souvent un proprio (les employés s'inscrivent rarement via demo)
   - tenant != "app" et le nom du tenant matche le nom: signature claire d'un proprio qui a son propre tenant

Si AU MOINS UNE source confirme la propriété (nom apparaît comme propriétaire/franchisé/administrateur d'une pharmacie), classe comme **PHARMACIST_OWNER** et capture la/les pharmacie(s) trouvée(s) dans la Note. Si ZÉRO source confirme malgré la recherche, classe PHARMACIST (licencié seul).

ENRICHISSEMENT IDENTITÉ — SI OPQ NE TROUVE RIEN (OBLIGATOIRE):
**Ne jamais conclure "probable non-pharmacien" et s'arrêter.** Si OPQ retourne zéro match malgré la licence renseignée dans le profil, ça veut dire UNE des trois choses: (i) c'est un étudiant (vérifie studentLicenseNumber dans la même API OPQ), (ii) il a un autre rôle (technicien, ATP, infirmier, médecin, vendeur pharma, étudiant en med), (iii) c'est un cadre d'industrie / commercial / patient curieux. Tu DOIS chercher pour savoir QUI c'est avant de finaliser.

Étapes obligatoires quand OPQ vide:
1. **LinkedIn search** (priorité 1 — c'est là que les non-pharmaciens du milieu sont):
   - bx web "<nom complet> linkedin"
   - bx web "<nom complet> linkedin pharma" / "pharmacy" / "pharmaceutique"
   - bx web "<nom complet> linkedin <ville si dispo>"
   Lis les 3-5 premiers résultats LinkedIn. Note le titre/employer ("Sales Rep Pfizer", "ATP CHUM", "Étudiant Pharm.D U Laval", "Infirmière clinicienne", "Représentant Familiprix", etc).

2. **Ordres professionnels alternatifs** si le nom suggère un autre métier de santé:
   - Médecins (CMQ): bx web "<nom> cmq.org" ou "<nom> college des medecins"
   - Infirmières (OIIQ): bx web "<nom> oiiq"
   - Techniciens (OTPQ): bx web "<nom> otpq.qc.ca"
   - Étudiants pharmacie (UdeM/Laval): bx web "<nom> université de montréal pharmacie" / "<nom> université laval pharmacie"

3. **Web général** — bx web "<nom complet>" (sans qualifier) pour profils Facebook publics, sites perso, articles, etc. Lis ce qui sort.

4. **Email/téléphone signaux** — si l'email contient un domaine pro (@<chain>.ca, @<hopital>.qc.ca, @<industrie>.com), c'est un signal fort. Documente.

5. **Tenant Pharmia signal** — si tenant != "app", le signup vient de l'app d'un client pharmacie (donc personne du staff de ce tenant: pharmacien employé, ATP, technicien, gérant). Documente le tenant et leur rôle probable.

CLASSIFICATION QUAND OPQ VIDE:
- Étudiant pharmacie confirmé (LinkedIn ou OPQ student) → group=null, jobTitle="Étudiant(e) en pharmacie - <université>", source=PHARMIA_SIGNUP
- ATP/Technicien confirmé → group=null (pas dans l'enum), jobTitle="ATP" ou "Technicien(ne) en pharmacie", source=PHARMIA_SIGNUP
- Rep pharma / commercial / industrie → group=null (pas dans l'enum), jobTitle="<rôle> chez <entreprise>", source=PHARMIA_SIGNUP. **Très haute valeur** — flag explicitement dans l'output.
- Médecin / infirmière / autre pro santé → group=null, jobTitle="Médecin" ou "Infirmier(e)" + spécialité si trouvé, source=PHARMIA_SIGNUP
- Rien trouvé après recherche exhaustive (LinkedIn, web, ordres) → group=null, jobTitle="Non identifié (recherche exhaustive)", source=PHARMIA_SIGNUP, et **flag dans l'output** "Identité non confirmée — à investiguer manuellement"

JAMAIS écrire "probable non-pharmacien" comme conclusion sans avoir LinkedIn-cherché + web-cherché + au moins un ordre alternatif vérifié.

TWENTY ACTIONS (toujours dans cet ordre):

A. LOOKUP Person (email d'abord, puis téléphone, puis nom):
   twenty gql '{ people(filter: { emails: { primaryEmail: { eq: "<email>" } } }) { edges { node { id name { firstName lastName } emails { primaryEmail } phones { primaryPhoneNumber } city jobTitle source pharmiaTenant group } } } }'

B. CREATE ou UPDATE Person avec ces fields:
   - name: { firstName, lastName } correctement séparés (PAS firstName="Sophya Berrada" lastName="Karim Berrada")
   - emails: { primaryEmail }
   - phones: { primaryPhoneNumber: "+1<E164>" }
   - city: ville OPQ, ville du compte, ville LinkedIn, sinon "Inconnue"
   - jobTitle: voir règles de classification ci-dessus
   - source: PHARMIA_SIGNUP (TOUJOURS — c'est la règle de ce channel)
   - pharmiaTenant: "<slug DB>" (ex "app", PAS "Public")
   - pharmiaUserId: l'`id` de ba_user (de la requête DB étape 1) — c'est l'id better-auth, le LIEN CRM↔app. TOUJOURS le capturer pour un signup: c'est ce qui fait apparaître la personne comme "Atlas user" dans les vues. Ne jamais inventer; prends l'`id` exact de la ligne ba_user qui matche l'email.
   - group: PHARMACIST_OWNER si propriété confirmée, PHARMACIST si licencié seul, null sinon. JAMAIS PHARMIA — group = persona, source = origine.

   Utilise le raccourci `twenty person upsert` (create-or-update par primaryEmail — gère le lookup, le create et l'update en une commande, et écrit le lien app):
   twenty person upsert \
     --email "<email>" --first "<Prénom>" --last "<Nom>" \
     --phone "+1<E164>" --city "<ville>" --job-title "<titre>" \
     --source PHARMIA_SIGNUP --tenant "<slug DB>" \
     --pharmia-user-id "<ba_user.id>" \
     --group <PHARMACIST_OWNER|PHARMACIST|null>
   (Omets un flag si la valeur est inconnue. `--group null` pour effacer/laisser vide. La commande imprime "created <id>" ou "updated <id>".)

C. CREATE Note. bodyV2 est RICH_TEXT_V2 — utilise le sous-champ markdown (PAS `body`, PAS un string direct). Inclus section **Identité** (LinkedIn/web findings), **Propriété** (sources), **Compte**:
   twenty gql 'mutation { createNote(data: { title: "Signup Pharmia - <tenant friendly>", bodyV2: { markdown: "Inscription <YYYY-MM-DD HH:MM> via <signup_source>. Tenant: <friendly> (<slug>). Locale: <fr/en>. Onboarding: <complete/incomplet>.\n\n**OPQ**: <licence #<num>, <ville>, <pharmacien/étudiant/statut> | non-trouvé après recherche>.\n\n**Identité (si OPQ vide)**: <résumé findings LinkedIn/web/ordres avec liens verbatim>.\n\n**Propriété**: <PHARMACIST_OWNER de [Pharmacie X, Pharmacie Y] | non-proprio confirmé après recherche | N/A — pas pharmacien>. source: <bannière site / REQ / web>.\n\n**Compte**: <référence si dispo>, <attribution>.\n\n<Q&A ou contexte additionnel si présent dans l\u0027embed>" } }) { id } }'

D. LINK Note → Person:
   twenty gql 'mutation { createNoteTarget(data: { noteId: "<noteId>", personId: "<personId>" }) { id } }'

OUTPUT (poste UN SEUL message dans le channel après que tout soit écrit):
Format strict, max 5 lignes total:

```
<Prénom> <Nom> — <persona courte: Pharmacien(ne) [propriétaire] | Étudiant(e) | ATP | Rep pharma chez X | Médecin | Non identifié> à <ville>. Twenty: <créé|enrichi>, note attachée.
<Si OPQ confirmé:> OPQ #<licence>, <statut>.
<Si OPQ vide mais identité trouvée:> Trouvé via <LinkedIn/web/ordre>: <résumé 1 ligne avec URL si pertinent>.
<Si propriétaire:> Proprio: <bannière + ville/nom pharmacie>. Source: <bannière site / REQ / web>.
<Si referral notable (conference/demo/sales/rep pharma):> Referral: <source> | Flag: <"high-value rep pharma" si applicable>.
```

RÈGLES STRICTES:
- L'étape DÉTECTION DE PROPRIÉTÉ est OBLIGATOIRE pour les pharmaciens OPQ.
- L'étape ENRICHISSEMENT IDENTITÉ est OBLIGATOIRE quand OPQ retourne vide. JAMAIS dire "probable non-pharmacien" sans LinkedIn + web + un ordre alternatif vérifiés.
- AUCUNE narration d'étapes ("Je vais...", "Maintenant...", "Laisse-moi vérifier..."). Tu fais, tu rapportes.
- AUCUN paragraphe d'explication. Faits seulement.
- Si une étape échoue: une ligne disant quoi a échoué et ce qui est quand même écrit dans Twenty.
- Si la personne est déjà parfaitement à jour: "<Nom> déjà à jour dans Twenty." (une ligne).
- APRÈS le message final unique, TU NE PARLES PLUS dans ce channel — pas de "je continue à surveiller", pas de "je reste en veille", rien. Le watcher ne se commente pas lui-même.
    ```
  - **Idempotency note:** `twenty person upsert --email` is create-or-update by primaryEmail — safe re-run; the `pg canary app` lookup is read-only. Re-trigger on the same signup → "déjà à jour" path.
- [ ] Model/skills: bind `crm-triage` and `lead-scouting` skills (they encode the OPQ→Twenty→Autumn sequence). Set a sane model (match other ingest-class agents in `defaults.yaml`).
- [ ] **AC:** REQ-007 — `paperclipai company import` registers `signup-ingest`; the agent's instructions match vortex semantics; Twenty writes are idempotent.

### Task 4.3: `booking-ingest` agent (verbatim prompt, input-adapted)
**Files:** Create `templates/pharmia/agents/booking-ingest/AGENTS.md`.
- [ ] Same approach: VERBATIM vortex "New Booking" prompt, input/back-post adapted as in 4.2. Keep the Moved/Updated vs New Booking routing, the OPQ/web/REQ sources, the `twenty person upsert` + `createOpportunity` (MEETING) + dual `createNoteTarget`, and the skip-if-already-seen rule (now backed by Twenty lookup, not channel history — note: the agent must do the Twenty existence check since it no longer has vortex's per-session channel history).
  - Verbatim prompt to embed:
    ```
    Nouvelle réservation de meeting via le site Pharmia. Objectif: enrichir le lead dans Twenty et créer/mettre à jour l'Opportunity.

INPUT (embed du bot n8n):
- title: "📅 New Booking: ..." (création) ou "🔄 Moved/Updated: ..." (modif date)
- description: "**Réservé par**\n<Nom complet>\n<EMAIL>"
- fields: Start, End, Organizer, Attendees, Location (lien Meet)

ROUTING:
- "🔄 Moved/Updated" → trouve l'Opportunity existante (stage MEETING ou plus avancé) et mets à jour closeDate + Note. Ne crée PAS de duplicate.
- "📅 New Booking" → flow complet (lookup, create/update Person, create Opportunity).
- Si déjà vu ce booking dans l'historique récent du channel: skip silencieusement.

SOURCES (parallèle):
1. OPQ register:
   curl -s 'https://www.opq.org/wp-content/uploads/pharmacist-search/pharmacists_index.json' | jq '[.[] | select(.fullName | test("<nom>"; "i"))]'
2. Web search pour identifier la pharmacie (chaîne + ville) si le nom du booking l'indique (ex "Proxim Maude Lenoir" → chercher pharmacies Proxim avec ce nom propriétaire).
3. RAMQ / registre des entreprises Québec si besoin de confirmer la propriété d'une pharmacie.

TWENTY ACTIONS:

A. LOOKUP Person par email (extrait de "Réservé par"):
   twenty gql '{ people(filter: { emails: { primaryEmail: { eq: "<email>" } } }) { edges { node { id name { firstName lastName } source group city pointOfContactForOpportunities { id name stage closeDate } } } } }'

B. CREATE/UPDATE Person — utilise le raccourci `twenty person upsert` (create-or-update par email):
   - D'abord vérifie s'ils ont un compte Pharmia ET récupère l'id better-auth: `pg canary app "SELECT id, tenant FROM ba_user WHERE lower(email)='<email>'"`.
   - source: INBOUND_MEETING par défaut (booking via widget). Si la requête ba_user retourne une ligne → ils sont aussi un Atlas user: passe `--pharmia-user-id "<ba_user.id>"` (le lien CRM↔app) et `--tenant "<slug>"`; garde source=INBOUND_MEETING (l'origine de CE contact reste le booking).
   - group: PHARMACIST_OWNER si propriétaire confirmé (OPQ + registre entreprises), PHARMACIST si juste licencié, null sinon.
   - jobTitle: "Pharmacien(ne) propriétaire" si proprio, sinon "Pharmacien(ne)" ou null.
   - city: ville de la pharmacie ou ville OPQ.

   twenty person upsert --email "<email>" --first "<Prénom>" --last "<Nom>" \
     --city "<ville>" --job-title "<titre>" --source INBOUND_MEETING \
     [--pharmia-user-id "<ba_user.id>" --tenant "<slug>"]  --group <enum|null>
   (Les flags entre [] seulement si la personne a un compte Pharmia. La commande imprime "created/updated <id>" — réutilise cet id pour l'Opportunity.)

C. CREATE Opportunity (si pas déjà une active pour ce Person):
   twenty gql 'mutation { createOpportunity(data: { name: "<Prénom Nom> — <pharmacie ou ville>", stage: MEETING, closeDate: "<Start ISO>", pointOfContactId: "<personId>" }) { id name stage closeDate } }'
   Stages possibles: NEW, SCREENING, MEETING, PROPOSAL, CLIENT, DONE, LATER. Pour un booking c'est MEETING.

D. CREATE Note "Meeting <date courte> - <Nom>" avec bodyV2.markdown contenant: datetime, lien Meet, attendees, contexte OPQ, pharmacies identifiées, co-propriétaires.
   Link la note à la fois au Person ET à l'Opportunity:
   twenty gql 'mutation { createNoteTarget(data: { noteId: "<id>", personId: "<id>" }) { id } }'
   twenty gql 'mutation { createNoteTarget(data: { noteId: "<id>", opportunityId: "<id>" }) { id } }'

OUTPUT (UN message dans le channel, max 5 lignes):

```
<Nom> — <Pharmacien(ne) [propriétaire]> à <ville/pharmacie>. Opportunity <créée|mise à jour> (MEETING, <date courte FR>).
<Si OPQ confirmé:> OPQ #<licence>, <ville>.
<Si pharmacies identifiées:> <N> pharmacies <chaîne>: <liste compacte>.
<Si co-propriétaires:> Co-proprios: <noms>.
<Touche de personnalité brève si pertinent.>
```

RÈGLES STRICTES:
- AUCUNE narration ("Je vais checker OPQ...", "Maintenant je crée..."). Tu fais, tu rapportes.
- AUCUN paragraphe. Faits compactés.
- Si Move/Update et rien d'autre à signaler: "<Nom> meeting déplacé au <nouvelle date>, Opportunity mise à jour." (une ligne).
    ```
- [ ] **AC:** REQ-007 — `booking-ingest` imports; opportunity creation is idempotent (lookup existing active opportunity by pointOfContact before create).

### Task 4.4: `translate-fr` agent (verbatim "Arabic" prompt, input-adapted) — TDD
Per Decision 2, the Arabic→French translator IS migrated to Paperclip as a first-class agent with the same rigor as 4.2/4.3. It reads the last Atlas Q&A embed on `1485869100952588309` (CLINICAL) and posts a French translation back — the CTO-accepted Law-25 PHI path (see the PHI subsection at the end of Chunk 4).
- [ ] Create `templates/pharmia/agents/translate-fr/AGENTS.md` whose body = the VERBATIM vortex "Arabic" prompt below, changed ONLY where input/back-post differ from vortex:
  - Replace "Le dernier embed Atlas Q&A dans ce channel" sourcing with: "INPUT: the triggering Discord message (the Atlas Q&A embed) is provided in the wake prompt under [Triggering message], embeds already serialized. Translate THAT embed — do not fetch channel history." (The real-time trigger already delivers the matched Atlas Q&A message, so the agent needs no channel read and needs NO canary/Twenty tooling — pure-LLM.)
  - Replace "OUTPUT (UN seul message...)" mechanic with: "Post your single final message with `discord-post <channelId> \"…\"` (channelId is in the Discord context)."
  - Keep IDENTICAL: the FR-only translation rule, markdown-structure preservation, verbatim monograph/source refs, the medical-term-in-parentheses rule, the strict output format (`**🌐 Traduction FR**` / Question / Réponse), the no-preamble/no-postscript rules, and the `⚠️ Vérifier:` clinical-ambiguity line.
- [ ] Bind NO canary/Twenty skills (pure-LLM); set a model adequate for FR clinical translation (match the lightest ingest-class model in `defaults.yaml` or a translation-suitable tier).
  - Verbatim prompt to embed:
    ```
    Le dernier embed Atlas Q&A dans ce channel contient de l'arabe. Traduis-le en français.

ACTION:
1. Repère le dernier embed Atlas Q&A (title "Atlas Q&A", auteur Pharmia Notifications).
2. Extrais la QUESTION (après "**Question:**" dans le description) et la RÉPONSE (le reste du description + les champs si pertinents).
3. Traduis tout en FRANÇAIS (pas en anglais). Garde la structure markdown (gras, listes, citations) et les références aux monographies/sources verbatim si présentes.
4. Pour la terminologie médicale/pharmaceutique sans équivalent FR standard, garde le terme original entre parenthèses après le terme traduit.

OUTPUT (UN seul message, format strict):

```
**🌐 Traduction FR**

**Question:**
<question traduite en français>

**Réponse:**
<réponse traduite en français, structure originale préservée>
```

RÈGLES:
- Aucun préambule ("Voici la traduction...", "Laisse-moi traduire..."). Direct.
- Aucun commentaire post-traduction.
- Ne reformule pas — traduis fidèlement. Sens clinique intact.
- Si la traduction te semble cliniquement risquée (terminologie ambiguë, contexte manquant), ajoute UNE ligne en fin: "⚠️ Vérifier: <ambiguïté précise>."
    ```
- [ ] **Idempotency:** translation is read-only + a single post; a re-trigger on the same embed re-posts a translation (acceptable, no external mutation). Cooldown (REQ-003) suppresses rapid duplicates.
- [ ] **AC:** REQ-007 — `paperclipai company import` registers `translate-fr`; instructions match the verbatim vortex translator; the agent uses no canary/Twenty tools; output format is byte-identical to vortex's. PHI handling per the Chunk-4 PHI subsection.

### PHI handling for the `translate-fr` path (Law-25) — applies once translate-fr is live
Decision-1's drop-path guarantees (non-matching messages: never sent to an agent, never persisted, never logged) FULLY cover signup + booking and the non-matched traffic on `1485869100952588309`. The `translate-fr` assignment is the ONE deliberate exception: it MATCHES Atlas Q&A and therefore sends clinical content into an agent run and posts a translation back. This subsection bounds that exposure.
- [ ] **(a) No clinical content in logs (engine).** Re-confirm Task 2.2's PHI-safe logging holds for translate-fr: the assignment engine logs only `{channelId, assignmentId, pattern, agentId, runId, messageId}` — never the embed body, `fullText`, or `wakePrompt`. The agent itself MUST NOT echo the clinical body to stdout beyond its single `discord-post` translation (the verbatim prompt's no-narration rule enforces this; add it explicitly to the AGENTS.md).
- [ ] **(b) Agent run-history retention (VERIFY before go-live).** `ctx.agents.invoke` flows into the server's wakeup path (`server/src/services/heartbeat.ts` `enqueueWakeup`), which persists a `contextSnapshot` + wake metadata in `heartbeat_runs` and adapter-invoke events in `heartbeat_run_events`. The `wakePrompt` (containing the clinical Atlas Q&A for translate-fr) will therefore be PERSISTED in agent run-history. The implementer MUST: (i) confirm exactly which column the prompt lands in (`heartbeat_runs.contextSnapshot`/payload and/or `heartbeat_run_events`), and (ii) confirm its retention/TTL. If retention is non-trivial (no short TTL / no purge job), this is a Law-25 implication: clinical PHI sits in the Paperclip control-plane DB indefinitely. **Minimal-retention requirement:** either confirm an existing purge keeps these rows ≤ the Pharmia clinical-log retention (DOC-D15: 1y logs), OR add a purge/redaction for translate-fr run-history, OR keep the clinical body OUT of the persisted snapshot (pass a redacted reason + fetch-on-demand). Pick one and record it before registering the translate-fr assignment in Task 6.2.
- [ ] **(c) CTO Law-25 acceptance (recorded).** Per Decision 2, the CTO explicitly accepts that the translate-fr path processes clinical PHI on Paperclip (clinical content sent to an agent run + a translation posted back to `1485869100952588309`). This is the documented exception to Decision-1's drop-path guarantees; signup/booking remain on the strict drop path.
- [ ] **AC:** REQ-009 (PHI leg) — translate-fr clinical content never enters logs; run-history retention is verified and bounded (one of the three options above chosen); CTO Law-25 acceptance recorded.

---

## Chunk 5: Canary read-only wiring

### Task 5.1: prod-side RO extension to mastra (FLAG FOR CTO — prod change)
**Files:** prod host `167.114.2.32`: `/usr/local/bin/canary-pg-ro-query` (+ a mastra-specific variant or a DB arg), `pharmia_readonly` role on `pharmia-canary-46uhia-mastra_db-1`.
- [ ] **BLOCKING ON CTO APPROVAL — prod-side change.** The existing forced-command reads ONLY the canary app DB container. To satisfy REQ-006 (mastra/threads), extend the SAME role+script pattern to the mastra container (memory `paperclip-agent-identity` explicitly notes this is the supported extension): create `pharmia_readonly` (SELECT-only, NOSUPERUSER, `default_transaction_read_only=on`) on `pharmia-canary-46uhia-mastra_db-1` db `postgres`; make `canary-pg-ro-query` accept a DB target (`app`|`mastra`) on its first stdin line or via a second forced-command script `canary-pg-ro-query-mastra`, still rejecting `\` metacommands, RO password in a root-only file.
- [ ] Verify: as `agent`, `pgro --db mastra "SELECT count(*) FROM mastra_messages"` reads; `CREATE TABLE` → "read-only transaction"; `\! id` rejected.
- [ ] **AC:** REQ-006 (mastra leg) — canary mastra readable RO, no superuser, no write; CTO sign-off recorded before applying.

### Task 5.2: route `pg canary` through the RO path for the agent
**Files:** Modify `templates/pharmia/cli/bin/pg`.
- [ ] When `ENV=canary`, instead of `ssh prod → sudo docker exec → psql -U postgres`, use the `prod-ro` forced-command: pipe the (prelude-prepended, already read-only) SQL via `ssh prod-ro` (which runs `sudo /usr/local/bin/canary-pg-ro-query [--db app|mastra]`). Map `DB=app→app`, `DB=mastra→mastra`. Keep dev/qa unchanged. Since the forced-command is inherently read-only, `--write` on canary must hard-error ("canary is read-only via the RO path"). Preserve the base64-over-SSH literal-byte behavior (the forced-command reads stdin SQL).
  - **Human-operator impact — DECISION (pick one, stated):** removing the `ssh prod → docker exec → psql -U postgres` path changes `pg canary …` behavior for HUMAN operators too, not just the agent (today a human with full `prod` access can `pg canary app --write`). **CHOSEN: gate by context, keep superuser for humans.** When the `prod-ro` host alias resolves (the agent VPS has it; human boxes do not, per memory `paperclip-agent-identity` — agent `~/.ssh/config` has `prod-ro` but NOT `prod`, humans have `prod`), route canary through `prod-ro` (RO, app+mastra) and hard-error on `--write`. When only the full `prod` alias resolves (human box), keep the existing superuser path UNCHANGED so human canary workflows (incl. the sanctioned canary writes / migrations done by ops) are not broken. Rationale for NOT making it RO-for-everyone: the `pg --write canary` superuser path is used by human ops for hotfixes/data-fixes on the live box; silently removing it would break those workflows with no migration. The agent never has the `prod` alias, so it is structurally confined to RO regardless. Implement as: `if ssh-alias prod-ro resolves AND prod does not → RO path; elif prod resolves → legacy superuser path`.
- [ ] `threads` needs no change — it shells `pg canary mastra/app` and inherits the RO path.
- [ ] **AC:** REQ-006 — on the agent VPS (`prod-ro` resolves, `prod` does not): `pg canary app/mastra "SELECT …"` + `threads <canary url>` work, no superuser, `--write` refused. On a human box (`prod` resolves): legacy superuser path unchanged, no human workflow broken. The signup agent's `pg canary app "SELECT … FROM ba_user …"` works RO.

### Task 5.3: bake canary RO + bot token into provisioning
**Files:** Modify `provision-agent-identity.sh`.
- [ ] Document in the header secret list and ensure the `prod-ro` outbound key + `~/.ssh/config` `prod-ro` alias + the `pgro` helper are part of the restored-from-escrow identity (they already are per memory; assert/verify in the script comments). Add `ensure_secret DISCORD_BOT_TOKEN`. Do NOT add `PG_CANARY_*` (the RO path needs no client-side canary password — password lives root-only on prod).
- [ ] **AC:** A fresh re-provision converges to: agent can `pg canary app/mastra` RO + `discord-post`, still no canary write, no superuser.

---

## Chunk 6: Build, install, cutover, rollback

### Task 6.1: Build + install the fork durably
**Files:** the fork repo; container `/paperclip/.paperclip/plugins/`.
- [ ] Build the fork (`npm ci --legacy-peer-deps && npm run build`).
- [ ] Install via the runtime path (memory `paperclip-plugin-system`): `POST /api/plugins/install` with the local path / packed tarball, OR replace the in-container `node_modules/paperclip-plugin-discord` package with the fork (persisted in the `/paperclip` volume). Prefer the documented install API so it survives. Set the plugin instance config (`plugin_config.config_json`) with `enableAssignments:true`, `assignmentAdminRoleIds`, default channels.
- [ ] Restart the plugin worker (plugin install/replace requires container restart per memory). Verify the gateway connects (READY log) and `/clip` shows the new subcommands in Discord.
- [ ] **AC:** Plugin running from the fork; `/clip assignments` returns (empty) without error; gateway `READY` logged; liveness state written.

### Task 6.2: Register the 3 assignments via `/clip assign`
- [ ] `/clip assign channel:#<1485869100952588309> agent:signup-ingest prompt:"<verbatim signup prompt>" pattern:New signup`
- [ ] `/clip assign channel:#<1423469520437252157> agent:booking-ingest prompt:"<verbatim booking prompt>" pattern:New Booking`
- [ ] `/clip assign channel:#<1485869100952588309> agent:translate-fr prompt:"<verbatim arabic prompt>" pattern:ا` (Decision 2 — migrated). Bot must have View Channel + Read History on `1485869100952588309` (Dependencies).
- [ ] **PER-WATCHER cutover ordering (REQ-008, see Task 6.4):** register each Paperclip assignment on its LIVE channel only as part of the paired hand-off in Task 6.4 (unassign the matching vortex watcher in the same step), to avoid a simultaneous-active window. For the booking + signup proofs do the dry run on a TEST channel first (Task 6.3); the translate-fr proof is read-only so it may be exercised directly.
- [ ] **AC:** `/clip assignments` lists all 3 rows (signup, booking, arabic) with correct channel/pattern/agent.

### Task 6.3: End-to-end proof on ONE event
- [ ] Trigger ONE controlled event: either wait for one real signup, OR post a controlled test embed mimicking the "New Signup" webhook embed into a NON-clinical test channel with a temporary test assignment (preferred for PHI safety — proves the path without touching the clinical feed). The embed must contain a real-but-test name resolvable in OPQ.
- [ ] Verify the chain: gateway receives `MESSAGE_CREATE` → `handleMessageCreate` matches → `agents.invoke` returns a `runId` (check `plugin_logs`/`agent_runtime_state`) → the `signup-ingest` agent run starts on the agent VPS → it runs `pg canary app` (RO) + OPQ + `twenty person upsert` → it `discord-post`s ONE result message to the channel.
- [ ] Proof checks: (a) `assignmentsTriggered` metric incremented; (b) a `runId` row exists; (c) the Twenty Person exists/updated (`twenty gql` lookup by email) with `source=PHARMIA_SIGNUP` + `pharmiaUserId` set; (d) exactly ONE bot message posted back; (e) no duplicate wake on the same message id; (f) cooldown holds on an immediate repost.
- [ ] **Booking proof (REQ-007, non-idempotent writes):** repeat the controlled-test-channel proof for `booking-ingest`: post a controlled "📅 New Booking" embed (real-but-test name) to a TEST channel with a temporary booking assignment → verify the agent creates exactly ONE Twenty Opportunity (stage MEETING) + Note + dual NoteTarget, and that a re-post within cooldown does NOT create a second Opportunity (the agent's "lookup active opportunity before create" + engine cooldown). This proves the non-idempotent create path BEFORE it goes live.
- [ ] **translate-fr proof:** post a controlled Arabic-containing Atlas-Q&A-shaped embed to a TEST channel with a temporary `pattern:ا` assignment → verify exactly ONE `**🌐 Traduction FR**` message posted back, format-correct, no canary/Twenty calls, and PHI-safe logs (no embed body in logs).
- [ ] **AC:** REQ-001/005/006/007 proven end-to-end for signup AND booking AND translate-fr on controlled events.

### Task 6.4: Cut over — PER-WATCHER hand-off (no simultaneous-active window)
**Files:** vortex `~/vortex-claude` (via its `/unassign`) + Paperclip `/clip assign`, NOT a code change.
**Why per-watcher:** `twenty person upsert` is email-idempotent, but `createOpportunity`/`createNote`/`createNoteTarget` are NOT, and the booking agent's "skip if active opportunity" is a read-then-write race. If both vortex AND Paperclip are active on the same live channel, a single `New Booking` embed fires both → duplicate Opportunity + Notes. So switch ONE watcher at a time, with NO overlap: for each watcher, `/unassign` vortex and `/clip assign` Paperclip on the SAME live channel back-to-back (ideally during a lull; the brief gap risks at most a missed event, never a double-write — preferred over an overlap that risks duplicates).
- [ ] **Booking (highest risk — non-idempotent):** vortex `/unassign channel:#1423469520437252157 pattern:New Booking` (`bot.ts:1387`), THEN immediately `/clip assign channel:#<1423469520437252157> agent:booking-ingest prompt:"<verbatim booking prompt>" pattern:New Booking`. Verify no booking embed was processed by both during the swap.
- [ ] **Signup:** vortex `/unassign channel:#1485869100952588309 pattern:New signup`, THEN `/clip assign channel:#<1485869100952588309> agent:signup-ingest prompt:"<verbatim signup prompt>" pattern:New signup`.
- [ ] **Arabic (read-only, lowest risk):** vortex `/unassign channel:#1485869100952588309 pattern:ا`, THEN `/clip assign channel:#<1485869100952588309> agent:translate-fr prompt:"<verbatim arabic prompt>" pattern:ا`.
- [ ] After each hand-off, post a controlled test on that channel → exactly ONE bot reply and, for booking/signup, exactly ONE Twenty mutation (no duplicate Opportunity/Note).
- [ ] Leave ALL of vortex `/ask` intact (only the 3 watchers move).
- [ ] **AC:** REQ-008 — all 3 vortex watchers (signup + booking + arabic) removed and replaced by Paperclip assignments with no simultaneous-active window; vortex `/ask` still works; no double-processing observed.

### Task 6.5: Rollback
- [ ] Rollback = re-run vortex `/assign` with the THREE verbatim prompts (signup, booking, arabic — they remain in `~/vortex-claude/sessions.db` until explicitly deleted; do NOT delete them during cutover) AND `/clip unassign` the matching Paperclip assignment(s). Roll back PER-WATCHER (same no-overlap discipline as 6.4, reversed). Document the three vortex `/assign` command lines verbatim so rollback is copy-paste. Keep the prior plugin version tarball for plugin-level rollback (reinstall v0.9.1 upstream).
- [ ] **AC:** A single documented sequence restores vortex handling within minutes.

---

## Dependencies
- `@paperclipai/plugin-sdk` (this repo `packages/plugins/sdk`) — `agents.invoke`, `ctx.state`, `ctx.jobs`, `ctx.metrics`, gateway helpers. No new npm deps for the plugin (upstream has `dependencies:{}`).
- Forgejo `bentoadmin` token (repo create/push).
- Paperclip plugin install API + container restart (memory `paperclip-plugin-system`).
- `paperclipai company import` for the 3 new agents (signup-ingest, booking-ingest, translate-fr).
- Prod-side RO grant on the mastra container (Task 5.1) — CTO approval.
- Discord bot perms: View Channel + Send Messages on `1485869100952588309` (signup + arabic) and `1423469520437252157` (booking); Send needed for `discord-post`. **View Channel + Read History on `1485869100952588309` ARE required** (Decision 2 migrates the translator, which reads Atlas Q&A there; also per Decision 1 the bot must be on that channel). Send is likely already present (the bot posts notifications) — verify View + Read-History explicitly before Phase 6 (this channel is NOT in `intelligenceChannelIds` today).

## Risks
- **Law-25 / PHI (clinical channel) — resolved by Decisions 1+2, bounded by the Chunk-4 PHI subsection.** Channel `1485869100952588309` carries non-clinical signup embeds AND clinical Atlas Q&A. The gateway delivers EVERY message on it to `handleMessageCreate`. TWO distinct exposures: (1) **non-matching / signup traffic** — Decision-1 drop path: never sent to an agent, never persisted, never logged; the specific `New signup` regex means Atlas Q&A never triggers the signup agent. (2) **translate-fr** — the ONE deliberate clinical path (matches Atlas Q&A by `ا`, sends the clinical body to an agent run, posts a FR translation back): CTO-accepted (Decision 2). Mitigations for (2): PHI-safe engine logging (no clinical body in logs — Task 2.2 + PHI subsection (a)); verified+bounded run-history retention (PHI subsection (b) — the clinical wakePrompt persists in `heartbeat_runs`/events; implementer must confirm + bound the TTL or keep the body out of the snapshot); recorded CTO Law-25 acceptance (PHI subsection (c)). Residual: a regex that broadens `ا`/`New signup` could route clinical content to the wrong agent — mitigated by the metacharacter-free pattern check (Task 2.1 AC) + compile-on-store validation (Task 3.1).
- **Shared Claude rate limit (per-event runs on CTO token).** Each match spawns a full agent run on the gateway/CTO creds. A burst of signups → burst of runs. Mitigations: per-assignment cooldown (REQ-003), id-dedupe, and the agents are short single-shot. Monitor via `assignmentsTriggered` + run counts; add a per-assignment max-per-hour if needed (YAGNI until observed).
- **Gateway flap (the vortex failure mode).** The fork's gateway has reconnect/heartbeat/backoff + resume, strictly better than relying on a lone WS. Residual risk: silent dead socket. Mitigation: Task 2.3 liveness metric/log → Grafana alert. Unlike vortex (single process), Paperclip's worker restarts independently.
- **Bot perms.** If the bot lacks Send on a channel, `discord-post` 403s; if it lacks View/Read-History on `1485869100952588309`, translate-fr never sees the Atlas Q&A. Verify View + Send + Read-History on both channels before Phase 6.
- **Fork drift.** We own a fork; track `upstream`. Low churn risk; the changes are additive modules + one handler hook.
- **Idempotency / double-processing during cutover (booking is the real hazard).** If both systems are active on the same live channel, one embed fires both. `twenty person upsert` is email-idempotent (no dup Person), but `createOpportunity`/`createNote`/`createNoteTarget` are NOT → duplicate Opportunity/Notes for booking, and the booking agent's "skip if active opportunity" is a read-then-write race. Mitigation: **per-watcher hand-off with no simultaneous-active window** (Task 6.4 — `/unassign` vortex then `/clip assign` Paperclip back-to-back per channel, booking first); prove the non-idempotent booking path on a TEST channel first (Task 6.3). The brief gap risks at most a missed event (recoverable), never a double-write.

## Security Checklist
- [x] No new secrets hardcoded — bot token stays a secret-ref in plugin config; `DISCORD_BOT_TOKEN`/canary RO via env-only `ensure_secret`.
- [x] Auth checks — `/clip assign|unassign` role-gated (fail-closed when no admin role configured and caller not admin).
- [x] Input validation — regex patterns validated before store (reject invalid); agent name→UUID resolved against `agents.list` (no arbitrary invoke target).
- [x] Least privilege — agent canary access is SELECT-only via forced-command (no superuser, no write, no shell escape); no `PG_CANARY_*` client secret on the agent.
- [x] No injection — SQL the agent runs is read-only (RO transaction enforced server-side); `discord-post` escapes content via jq; prompt content is data, agent treats triggering message as untrusted input.
- [x] PHI — signup/booking: Decision-1 drop path (clinical content never sent/persisted/logged) + specific metacharacter-free regexes. translate-fr (CTO-accepted clinical path): PHI-safe engine logging (no clinical body in logs), verified+bounded agent run-history retention, recorded CTO Law-25 acceptance (Chunk-4 PHI subsection). No clinical content in any `ctx.logger` call for ANY assignment.

## Open Questions
All prior open questions are RESOLVED by the DECISIONS (CTO, 2026-06-14) section above and propagated through the body:
- Q1 (mastra RO) — RESOLVED: APPROVED (Decision 3 / Task 5.1). Read-only via the existing `pharmia_readonly`+forced-command pattern extended to the mastra container.
- Q2 (Law-25 / channel) — RESOLVED: REUSE `1485869100952588309`, no new channel / no relay change (Decision 1). Non-matching/clinical traffic dropped in-handler; CTO accepts the gateway receiving clinical content there. translate-fr's deliberate clinical path is bounded by the Chunk-4 PHI subsection.
- Q3 (Arabic) — RESOLVED: MIGRATE as first-class `translate-fr` (Decision 2 / Task 4.4); all 3 vortex watchers removed in Task 6.4.

No unresolved blockers remain.
