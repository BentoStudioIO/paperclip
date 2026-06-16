# Authoring a new agent

This README is the onboarding contract for adding an agent to the Pharmia
Paperclip company. Read it once before creating a new `agents/<slug>/`
directory, and again before opening a pull request.

## Required files

```
agents/<slug>/
  AGENTS.md           # the agent's instructions (this is what the LLM reads)
```

Optional but recommended:

```
agents/<slug>/
  README.md           # short human-facing description; sidebar tooltip
```

## AGENTS.md frontmatter

Two frontmatter blocks separated by a blank line. The outer block is the
Paperclip routing metadata; the inner block is the agent's runtime config.

```yaml
---
name: "Pharmacy Lead"        # display name (sidebar, mentions)
title: "Pharmacy Lead"       # short role label
reportsTo: "engineering-lead" # parent slug; omit for top-level agents
skills:                      # full skill keys this agent has access to
  - "company/<companyId>/workflow"
  - "company/<companyId>/deletion-bias"
  # ...
---

---
name: <slug>                 # lowercase, kebab-case, matches dir name
description: <one-line dispatch hint — when to delegate here>
model: gpt-5.5
disallowedTools: Edit, Write, NotebookEdit  # optional, omit if the agent edits files
author: <name>
---

<body of the prompt>
```

The `companyId` for Pharmia is `57cd0843-fe5a-42d5-a6f6-c4e896fee84e`. Skills
are referenced by their full key (`company/<companyId>/<skill-slug>`) — the
slug alone will not resolve.

## Registering the agent

Two registrations in `.paperclip.yaml`:

1. Under `agents:` — adapter config (model, permissions).
2. Under `sidebar.agents:` — display order in the company UI.

An agent directory that is not in both lists is invisible at runtime. The
manifest is the source of truth; the directory is the content.

## Skill bindings

Every agent should include the universal set unless there is a clear reason
to exclude one. These encode the company's baseline operating rules:

- `workflow` — SDD pipeline
- `deletion-bias` — minimal code, library-first
- `verification-before-completion` — evidence before assertion
- `clarification-gate` — surface ambiguity before planning

Function-specific skills layer on top. A planner gets `spec-miner` and
`pragmatic-programmer`. A reviewer gets `review-protocol` and
`receiving-code-review`. An implementer gets `testing-intelligence` and
`vitest`. Keep the binding list tight — every skill is context tokens at
runtime.

## Prose conventions

The body of `AGENTS.md` should follow this shape:

1. **Prime directive at the top.** One paragraph stating the agent's job
   in absolute terms. The reader should know within five seconds what this
   agent is and is not for.
2. **Critical rules.** Numbered list, ≤ 10 items, each a hard constraint.
3. **Procedure(s).** Step-by-step workflows for the agent's recurring tasks.
   Use checklists where the order matters.
4. **Anti-pattern catalog.** At least three concrete failure modes the
   agent should recognize and avoid. Each anti-pattern names the pattern,
   not the incident that surfaced it.
5. **Citations and references.** Point to skills, decision records, and
   `sources/` files rather than restating their content.

## Where content lives

When in doubt about where to put a directive, use this map:

- Behavior of one agent → that agent's `AGENTS.md`
- Reusable procedure usable by multiple agents → a skill under
  `skills/company/PHA/<slug>/SKILL.md`
- Durable cross-cutting principle → `ETHOS.md`
- One-shot architectural choice with rationale → `decisions/<date>-<slug>.md`
- Task handoff schema → `tasks/TEMPLATE.md`

Do not duplicate a directive across two locations. If something is in
`ETHOS.md`, the agent references it; it does not restate it.

## Sources vs derived

When citing legal, regulatory, or contractual facts, point to
`bento-docs/sources/<file>`. Never paraphrase a primary in the agent
prompt — paraphrases drift, primaries do not. If the relevant content is
authored interpretation, point to `bento-docs/derived/<file>` and make the
provisional nature explicit.

## Definition of done for a new agent

A new agent is shippable when all of the following hold:

- [ ] `agents/<slug>/AGENTS.md` exists with both frontmatter blocks and a
      body of at least 80 lines.
- [ ] `.paperclip.yaml` lists the agent under both `agents:` and
      `sidebar.agents:`.
- [ ] The skills list includes the universal set (`workflow`,
      `deletion-bias`, `verification-before-completion`,
      `clarification-gate`) unless explicitly justified.
- [ ] The prompt body has a prime directive, at least one procedure block,
      and at least three concrete anti-patterns.
- [ ] No content is duplicated from `ETHOS.md`, an existing skill, or a
      decision record — references only.
- [ ] If the agent makes regulated, legal, or compliance claims, citations
      point to `bento-docs/sources/` not to memory.
- [ ] After `paperclipai company import`, the agent appears in the live
      company and the sidebar order is correct.
