---
name: paperclip-loader
description: >
  How Paperclip's template loader parses AGENTS.md / SKILL.md / manifests,
  resolves defaults.yaml inheritance, and handles collisions on import.
  Use when editing templates/<company>/ packages, debugging why an agent
  didn't show up after import, or designing a new collision strategy.
allowed-tools: Read, Edit, Bash, Grep
---

# Paperclip template loader

The loader is the bridge between `templates/<company>/` (on disk in this
repo) and the live company in the running platform. It runs every time
`paperclipai company import` executes, and again during preview.

All citations below are line numbers in `server/src/services/company-
portability.ts` and `server/src/routes/companies.ts` as of commit
`76115143` (defaults.yaml inheritance). Re-grep if line numbers drift.

## The loader algorithm

`buildManifestFromPackageFiles(files, opts?)` at line 2470:

1. Find `COMPANY.md` (anywhere in the tree). Throws `unprocessable` if
   absent (line 2482).
2. `parseFrontmatterMarkdown(companyMarkdown)` at line 2279 — strips the
   leading YAML block delimited by `---`, returns `{ frontmatter, body }`.
3. Find `.paperclip.yaml` (the optional extension) and parse it. Read
   `company`, `sidebar`, `agents`, `projects`, `tasks` keys (lines
   2495–2499).
4. Read `agents/defaults.yaml` via `readAgentDefaultSkills(files)` at line
   2451. Returns `string[]` of skill keys.
5. For each agent directory:
   - Parse the agent's `AGENTS.md` → `parseFrontmatterMarkdown` (line
     2597).
   - Compute `skills` via `readAgentSkillRefs(frontmatter,
     agentDefaultSkills)` at line 2427 (call site line 2616).
6. For each skill directory: `parseFrontmatterMarkdown(skillMarkdown)`
   (line 2646) — extracts the `name` + `description` shown to the LLM.
7. For projects (line 2733) and tasks (line 2774): same parse step.
8. Return a `ResolvedSource` the import flow consumes.

## `defaults.yaml` resolution

Lookup pattern (`readAgentDefaultSkills`, line 2454):

```ts
files["agents/defaults.yaml"]  // or any path ending in /agents/defaults.yaml
```

If found:

```yaml
skills:
  - company/<companyKey>/workflow
  - company/<companyKey>/deletion-bias
```

…is merged into every agent's `skills:` frontmatter at import time.
Per-agent opt-out via:

```yaml
---
name: "Some agent"
skills:
  - company/<companyKey>/extra-skill
excludeSkills:
  - company/<companyKey>/deletion-bias
---
```

Merge logic (`readAgentSkillRefs`, line 2427–2443):

1. Start with `defaults`.
2. Append per-agent `frontmatter.skills` (deduped via `Set`).
3. Subtract `frontmatter.excludeSkills`.

## Collision matrix

Two axes: import mode (`agent_safe` vs `instance`) × collision strategy
(`skip` / `rename` / `replace`).

- **`agent_safe + skip`** — keep existing agent/skill, ignore the
  incoming row.
- **`agent_safe + rename`** — duplicate the incoming row with a suffix
  (e.g., `pharmacy-lead-2`).
- **`agent_safe + replace`** — **403 forbidden**. The safe route
  explicitly rejects this strategy at `server/src/routes/companies.ts:223`
  (preview) and `:239` (apply):

  ```ts
  if (req.body.collisionStrategy === "replace") {
    throw forbidden("Safe import route does not allow replace collision strategy");
  }
  ```

- **`instance + skip`** — same as `agent_safe + skip`.
- **`instance + rename`** — same as `agent_safe + rename`.
- **`instance + replace`** — clobbers the existing row. Only available to
  instance admins via the CLI; the HTTP route does not expose this.

## Export materialization round-trip

The exporter (around line 1986) re-emits the **resolved** skill list per
agent — `defaults.yaml` + `excludeSkills` are materialized away. A
round-trip (import → export → re-commit) flattens your DRY structure.

Implication: the live DB is the canonical state post-import. If you want
to preserve `defaults.yaml`, re-author by hand instead of re-exporting on
top of your template.

## `docker cp` fallback

When you can't use `--collision replace` (safe route blocks it) and you
need to push a template edit to a running company in-place:

```sh
# Find the live agent's instructions directory
ssh paperclip-host
docker exec paperclip-server ls /paperclip/instances/<company>/instructions/<slug>/

# Copy the new AGENTS.md straight in
docker cp ./templates/pharmia/agents/<slug>/AGENTS.md \
  paperclip-server:/paperclip/instances/<company>/instructions/<slug>/AGENTS.md
```

This bypasses the import flow, the DB, and the safe-route check. Use only
when you've already validated the change in the template repo and the DB
copy is acceptably stale. See `server/src/services/AGENTS.md` §3 for
the three-source-of-truth model this fallback bends.

## Worked example — pushing a template edit live

Scenario: edit `templates/pharmia/agents/pharmacy-lead/AGENTS.md`, push
to master, expect the change live in the running Pharmia company.

1. Edit the file in this repo. Commit + push to `master`.
2. Dokploy auto-deploys the platform — the new file is now baked into the
   server image. **The running company is unchanged.**
3. SSH to the platform host. Run:

   ```sh
   paperclipai company import templates/pharmia \
     --target existing \
     --company-id 57cd0843-fe5a-42d5-a6f6-c4e896fee84e \
     --collision skip \
     --dry-run
   ```

4. Review the diff. If the target agent already exists, `--collision skip`
   will NOT overwrite the live prompt. To push the new prompt, either:
   - Use `--collision rename` to create a side-by-side copy and migrate
     users, or
   - Use instance-mode + `--collision replace` if you have admin
     credentials, or
   - Use the `docker cp` fallback above for a single agent.
5. Drop `--dry-run` and rerun. Watch for warnings about
   `defaults.yaml` materialization in the output.
6. Verify in the UI that the new prompt is live; confirm the on-disk
   `instructions/<slug>/AGENTS.md` matches.

## Source-file references

- `server/src/services/company-portability.ts` — loader, parser,
  exporter. 4709 lines.
- `server/src/services/agent-instructions.ts:6` — on-disk runtime entry
  file.
- `server/src/routes/companies.ts:223,239` — safe-route replace
  rejection.
- `templates/AGENTS.md` — authoring contract.
- `server/src/services/AGENTS.md` — service-layer overview.
