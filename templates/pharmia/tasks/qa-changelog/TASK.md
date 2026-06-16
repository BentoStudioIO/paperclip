---
name: "QA Changelog"
project: "pharmamate"
assignee: "content"
recurring: true
description: >
  Fires once per push to a tracked PharmaMate branch (Forgejo webhook). Turns the
  push's commit messages into a concise FR-Québec, pharmacist-facing changelog
  (sections "Ajouté" / "Modifié", zero code internals) and posts it to the matching
  Discord channel. Skips silently when a push carries only internal/refactor commits.
  Reports only — never touches the repo, never invents a change.
---

Write the pharmacist-facing changelog for the ONE push in this webhook payload, then post it to Discord. The Forgejo push hook already did the watching — you do only the translation. This replaces the n8n "Pharmia Github Notifications" workflow; the source remote moved github.com → Forgejo (`git.bentostudio.io`), so the trigger is now a Forgejo webhook (`X-Hub-Signature-256`, GitHub-compatible), not a GitHub OAuth hook.

## Input — the webhook payload (routine variables)

A Forgejo push payload:
- `ref` — e.g. `refs/heads/qa` (the branch that was pushed)
- `commits[]` — each with `.message` (full commit message), `.author`, `.url`
- `repository.full_name` — e.g. `Pharmia/PharmaMate`

Build the working set with the commit messages only: `commits.map(c => "- " + c.message).join("\n")`.

## Branch → channel map (tracked branches only)

- `refs/heads/qa` → Discord **#qa-updates** (`1436126989730975765`, guild `1354213528097132585`).

Only `qa` is tracked today (preserves the live n8n behaviour — the n8n Switch wired ONLY its `qa` output to the changelog; the `dev` and `main` outputs were dead-ends). If the payload `ref` is any other branch, **do nothing and exit** — do not post. Adding `dev`/`canary`/`main` → their own channels is an **ask-first** change (see Remediation policy), not a local decision.

## Steps

1. **Gate the branch.** If `ref` is not in the map above, exit silently (no post).
2. **Collect commit messages** from `commits[]`. If the list is empty, exit silently.
3. **Write the changelog** per the rules below — FR-Québec, functional, pharmacist-facing.
4. **Empty-after-filtering gate.** If every commit is internal/refactor/tooling (nothing user-facing survives the rules), produce NOTHING and exit silently — do not post an empty or filler message.
5. **Post** the markdown changelog to the mapped Discord channel via the bot-REST mechanism in **Output** below. One message per push. No phone ping (a changelog is FYI-level, not an alert).

## Changelog rules (the contract — do not deviate)

- **Do not invent any change.** Only describe what the commit messages actually say. If unsure what a commit does for the user, omit it.
- **French (québécois professional).** Concise, markdown, two sections only: `### Ajouté` and `### Modifié`. Omit a section if it has no entries.
- **Audience = pharmacists, zero code exposure.** No class names, file names, component names, icon names, migration scripts. Translate internal names to plain function (e.g. "ConsultationDrawer" → "le panneau de consultation").
- **Functional only — what changed and how it affects their daily work.** Bugfixes stay one line: what was wrong, what to expect now. No implementation detail.
- **Ignore entirely** (never surface): refactors, reverts, performance/robustness/retry/cache work, try/catch, test changes, migration scripts, small visual/icon tweaks, dependency bumps, CI/tooling.
- **No code blocks** — the output is posted directly as a Discord message.

## Examples (the transform — input commit → desired output)

Input: `feat: enhance magic link functionality with consultation ID support — Updated sendMagicLink to accept an optional consultation_id … Modified the Consultations and Homepage components … Added tests …`
Output:
```
### Modifié
- Prise en charge des **liens magiques spécifiques à une consultation** — le lien magique provenant des tableaux de consultations ouvre désormais directement l'utilisateur dans la consultation.
```

Input: `refactor: fix date not using the correct day — Remove formatDateOnly utility for birthdate formatting … simplifies the transformation logic`
Output:
```
### Modifié
- Correction **d'un bogue d'affichage** des dates — dans la liste des patients, la journée devrait désormais être correcte.
```

## Remediation policy

- **Proactive — fix in-run, no approval (docs/config ONLY):** this TASK.md (rules, channel map clarity). List under **Remediated**.
- **Ask first — propose, do NOT ship:** extending the branch→channel map (new branch or channel), changing tone/sections, or any PharmaMate repo touch. This routine REPORTS. Put the proposal in your run note and stop. NEVER edit the repo, never enable an untracked branch on your own.

## Output

- **Deliver** the FR changelog to #qa-updates (`1436126989730975765`) via the Discord bot REST API. The bot token is injected as `$DISCORD_BOT_TOKEN` (company secret "Discord Bot Token" `b49f78a1…`, bound to this routine's project as `env.DISCORD_BOT_TOKEN` — same mechanism as the project's `env.GH_TOKEN`); the bot already has access to the channel:
  ```bash
  curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$(jq -nc --arg c "<changelog markdown>" '{content:$c}')" \
    "https://discord.com/api/v10/channels/1436126989730975765/messages"
  ```
  Expect `200`. On `401`/`403` the token binding is missing/invalid — report it in your run note, do NOT silently swallow. Use `jq` to JSON-encode (the changelog has newlines/quotes). No phone ping (a changelog is FYI-level).
- If you exited via a gate (untracked branch / empty / all-internal), say so in one line in your run note and post nothing.
