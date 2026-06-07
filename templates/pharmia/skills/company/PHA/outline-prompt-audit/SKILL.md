---
name: "outline-prompt-audit"
description: "Audit a runtime Outline-hosted Pharmia agent prompt (skill) for binding strength — verify doc references resolve, classify each instruction as enforced vs passive, and tighten what should bind. Use when asked 'is this prompt clear/enforced enough' or 'did we lose content'."
slug: "outline-prompt-audit"
metadata:
  paperclip:
    slug: "outline-prompt-audit"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/outline-prompt-audit"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/outline-prompt-audit"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/outline-prompt-audit"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/outline-prompt-audit"
---

# Outline Prompt Audit

## What This Owns

Pharmia loads part of its agent prompts (skills) from the Outline **Agent Skills**
collection at RUNTIME — `OutlineFilesystem` → Mastra workspace, **15s cache TTL**
(see `~/Documents/PharmaMate/.claude/rules/mastra-development.md`). These are live
prompts: edit the Outline doc and the agent's instructions change within ~15s, no
deploy. The recurring CTO question is *"is this Outline-hosted prompt clear / is this
instruction actually enforced / did we lose content?"*

This skill owns the **audit SEQUENCE** for a runtime Outline prompt: does it still
resolve, and do its rules actually BIND. It is DISTINCT from `claude-prompting`
(that skill is about *writing* prompt craft) — this one judges whether an
already-deployed runtime prompt's instructions structurally compel the agent.

Not owned here (point at the home, don't restate):

- `ol` CLI usage → `~/.claude/tools/documentation.md` + env-bindings.
- Prompt-writing craft (phrasing, examples, structure) → `claude-prompting`.
- Which collections are agent-facing → `outline-quebec-documents-ssot`.

## Collection IDs (agent-facing, cite from memory)

- **Agent Skills** (runtime skills/prompts): `628c21f7-ad81-4381-85de-c76814c98744`
- **Quebec Documents** (SSOT for OPQ/RAMQ/AQPP/regulatory docs prompts ground in):
  `50a7902d-439f-479a-9469-43926a4206a5` (short: `50a7902d`)

Content outside these two collections is invisible to agents even if high quality —
so a prompt that references a doc living elsewhere is silently broken.

## 4-Step Sequence

### 1. Locate the doc

Find the runtime prompt you're auditing. `ol` does the work — see its home for
syntax; the load-bearing calls:

```bash
ol search "<topic>"                         # find candidate docs
ol doc get <id> --raw > /tmp/audit-<slug>.md   # pull verbatim source to a local file
```

Always audit the **verbatim raw source**, never a rendered/derived view — escaped
tags, fences, and link targets only survive in `--raw`.

### 2. Extract & verify every reference

Walk the prompt and pull EVERY outbound grounding clause: inline links, `see X`,
cited doc IDs/titles, "as defined in …", collection references. For each, confirm it
still resolves at runtime — a broken ref is **silent prompt degradation** (the agent
keeps answering, just ungrounded):

```bash
ol doc get <referenced-id> --raw | head -n 3   # exists + reachable?
ol search "<referenced title>"                 # confirm it's the live doc, not a stale dupe
```

Flag any referenced doc that: is missing, lives **outside** the two agent-facing
collections above (invisible to the agent), or is a stale duplicate. Also flag
content the prompt *claims* to ground in but never actually links ("did we lose
content").

### 3. Classify each instruction — ENFORCED vs PASSIVE

For every directive in the prompt, decide which it is:

- **ENFORCED** — the agent is structurally compelled. The instruction is backed by
  a tool gate (must call tool X before answering), an output schema / contract the
  response is validated against, a required tag/format the renderer or downstream
  parser depends on, or a refusal/guard the model cannot route around.
- **PASSIVE** — advisory prose ("always be concise", "prefer the official source",
  "never speculate") that the model is free to ignore turn-to-turn. No mechanism
  forces it.

The recurring failure: a clause everyone treats as a "rule" is actually PASSIVE
prose — it reads authoritative but nothing binds it, so the agent silently drifts.
Produce a per-instruction list: text → ENFORCED / PASSIVE → (if PASSIVE) does it
*need* to bind? Passive is fine for taste/tone; flag passive only where correctness,
safety, grounding, or output-contract depends on it.

### 4. Propose & apply concrete rewrites

For each finding, give a concrete fix, not a vibe:

- Passive-but-should-bind → propose the enforcement: route it through a tool gate,
  an output-schema field, a required tag, or a refusal clause. If it genuinely can't
  be structurally enforced from the prompt alone, say so and name what code change
  (Mastra tool / schema) would.
- Broken / off-collection / stale ref → fix the link or move the doc into an
  agent-facing collection (§Collection IDs).

When editing the live doc, follow the global Outline rule — **never rewrite remote
content from memory**:

```bash
ol doc get <id> --raw > /tmp/audit-<slug>.md   # 1. pull verbatim
# 2. edit /tmp/audit-<slug>.md with the Edit tool (targeted diffs, not a rewrite)
ol doc update <id> --file /tmp/audit-<slug>.md # 3. push back
```

Because the cache TTL is 15s, the change is live almost immediately — re-`ol doc get`
to confirm the update landed, and (where possible) exercise the agent to confirm the
now-enforced rule actually fires.

## Output of an Audit

Report, per prompt:

- **References:** N total → M resolve, list each broken/off-collection/stale one.
- **Binding:** per-instruction ENFORCED/PASSIVE table; call out every passive clause
  that gates correctness/safety/grounding/output.
- **Fixes:** concrete rewrite or enforcement per finding, with the doc IDs touched.
