# AGENTS.md — `templates/`

Org-as-code authoring contract. Editing anything under `templates/<company>/`
goes through this file's rules. The Pharmia-specific authoring README at
`templates/pharmia/agents/_README.md` extends this with company-specific keys
(companyId, sidebar order, etc.) — read both when working in that subtree.

## 1. Directory layout

A Paperclip company is a canonical markdown package:

```
templates/<company>/
  COMPANY.md                       # company-wide context (frontmatter + body)
  ETHOS.md                         # values/operating principles (optional)
  .paperclip.yaml                  # manifest — source of truth, NOT *.json
  agents/
    defaults.yaml                  # universal skills merged into every agent
    <slug>/
      AGENTS.md                    # the agent's instructions (LLM reads this)
      README.md                    # optional human-facing description
  skills/
    <key-path>/
      SKILL.md                     # one skill prose file per directory
  tasks/                           # optional seed tasks
  decisions/                       # optional ADRs / decision records
```

The deprecated `paperclip.manifest.json` MUST NOT be used. Anything that lives
only in JSON is invisible to the current loader; rewrite it as
`.paperclip.yaml` keys.

## 2. `.paperclip.yaml` keys the loader recognizes

The loader schema is enforced by `server/src/services/company-portability.ts`
(`buildManifestFromPackageFiles` at line 2470, `parseFrontmatterMarkdown` at
line 2279). Keys it consumes:

- `company.{name, description, brandColor, …}` — overrides for `COMPANY.md`
  frontmatter.
- `agents.<slug>.{role, icon, adapter, runtime, permissions, metadata,
  budgetMonthlyCents}` — non-prompt agent config. The prompt lives in the
  per-agent `AGENTS.md`.
- `sidebar.agents` — explicit ordered list of agent slugs. **An agent
  directory not listed here is invisible in the UI sidebar.** Always register
  new agents in both `agents:` and `sidebar.agents`.
- `projects`, `tasks` — seed objects.

If your change adds a new key, the loader will silently drop it until
`company-portability.ts` learns the shape. Cite that file as the schema
authority when in doubt.

## 3. `defaults.yaml` — DRY skill inheritance

Added in commit `76115143`. Place `agents/defaults.yaml` next to the agent
directories:

```yaml
skills:
  - company/<companyKey>/workflow
  - company/<companyKey>/deletion-bias
```

At import time the loader merges this list into every agent's `skills:`
frontmatter (`readAgentSkillRefs` at line 2427, `readAgentDefaultSkills` at
line 2451). Per-agent opt-out:

```yaml
---
name: "Some agent"
skills:
  - company/<companyKey>/extra-skill
excludeSkills:
  - company/<companyKey>/deletion-bias
---
```

Dedup is via `Set` and per-agent frontmatter is added on top of defaults.

**Round-trip caveat.** The exporter (line ~1986) materializes the full
resolved skill list back into each agent's frontmatter, so a re-export loses
the DRY structure: defaults.yaml + excludeSkills is an import-time
convenience, not a persistent representation. The live DB is the canonical
state once import has run. If you re-export and re-commit, you will flatten
your own defaults — re-author by hand instead.

## 4. Skill key namespacing

Skills are referenced by full key `<scope>/<companyKey>/<skill-slug>` — e.g.
`company/PHA/dispatching-parallel-agents`. The company key is embedded in
every reference. Consequences:

- Splitting a company later (e.g., Pharmia → Pharmia + Bento) requires
  rewriting skill refs across every agent file.
- A bare slug (`dispatching-parallel-agents`) without scope+company will not
  resolve.

When adding a new skill, place it at `skills/<scope>/<companyKey>/<slug>/
SKILL.md` and reference it by the full key everywhere.

## 5. Frontmatter schemas per artifact

### Agent (`agents/<slug>/AGENTS.md`)

Required: `name`, `title`, `slug`, `kind: agent`. Optional: `reportsTo`,
`skills:`, `excludeSkills:`. Everything else (adapter, runtime, permissions,
budget) belongs in `.paperclip.yaml` under `agents.<slug>` — not in
frontmatter.

### Skill (`skills/<key-path>/SKILL.md`)

Required: `name`, `description` (the `description` is what the LLM sees when
deciding to invoke; write it as a dispatch hint, not a marketing blurb).
Optional: `compatibility:`, `metadata:`, `allowed-tools:` (Anthropic-skills
convention).

### Task / Decision

Frontmatter is minimal — `title`, `status`, `createdAt`. Body holds the
content.

## 6. The tri-source-of-truth (template / DB / runtime file)

Once a template is imported into a live company, three copies exist:

1. **Template** (this repo) — the import seed. Editing this file alone does
   nothing to a running company.
2. **Database** — `agents` table holds the resolved frontmatter; UI edits
   write here. The DB is authority for the running company.
3. **Runtime instructions file** —
   `/paperclip/instances/<company>/instructions/AGENTS.md`. The on-disk file
   the agent process actually reads at heartbeat time. This is the runtime
   authority (`server/src/services/agent-instructions.ts:6` —
   `ENTRY_FILE_DEFAULT = "AGENTS.md"`).

Mismatch rules:

- UI edits update the DB; they do not write back to this repo.
- `paperclipai company import --collision skip` keeps the DB; new template
  changes are ignored for existing agents.
- `--collision rename` creates duplicate agents with a suffix.
- `--collision replace` is **blocked** by the safe-import route
  (`server/src/routes/companies.ts:223` and `:239` — both throw `forbidden`).
  Use instance-mode import or `docker cp` for in-place runtime updates.

## 7. References

The agents.md convention: <https://agents.md>. Inspiration for the
template + per-instance override semantics: Backstage `catalog-info.yaml`
and Argo CD ApplicationSets.
