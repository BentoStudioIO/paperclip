---
name: agent-memory
description: Durable cross-task shared memory via the team Outline. Recall prior context at task start; record durable decisions/facts at task end.
---

# Agent Shared Memory (Outline-backed)

Persistent, team-shared, human-readable memory that survives **across tasks and agents** — stored in the Outline collection **"Paperclip Agent Memory"** (`8d616970-8aa5-4de9-a84a-ce532eda68e5`) via the pre-authed `ol` CLI. Your per-run workspace is ephemeral, so anything worth remembering MUST go here.

## At task START — recall
- Search: `ol search "<topic / entity / error>" --collection 8d616970-8aa5-4de9-a84a-ce532eda68e5`
- Read a hit: `ol doc get <id> --raw`
- Browse if unsure: `ol doc list --collection 8d616970-8aa5-4de9-a84a-ce532eda68e5 --short`
- Apply what you find. If a prior decision covers your task, follow it — don't re-litigate.

## During/after the task — record durable knowledge
Persist what a future task (yours or another agent's) would want: decisions + why, resolved bugs + root cause, durable facts (IDs, endpoints, owners), gotchas, project-state changes. Do NOT record transient per-task chatter.
- **One doc per topic/entity** — search first; UPDATE the existing doc, don't duplicate.
- **Update:** `ol doc get <id> --raw > /tmp/mem.md`, append a dated bullet to `/tmp/mem.md`, then `ol doc update <id> --file /tmp/mem.md`.
- **Create** (none exists): write `/tmp/mem.md`, then `ol doc create --collection 8d616970-8aa5-4de9-a84a-ce532eda68e5 --title "<Topic>" --file /tmp/mem.md`.
- **Title** = the searchable topic/entity (e.g. "Atlas tool health", "Forgejo registry ops").
- **Entry format:** `- YYYY-MM-DD (<your agent name>): <fact / decision / why>`. Keep concise; link related docs by their Outline URL.

## Rules
- Never store secrets, credentials, or PHI in memory docs.
- Edit via a temp local file (above) — never rewrite a doc from memory.
- Supersede stale info with a new dated line; don't delete history.
