---
name: "crm-triage"
description: "Standardized signup → CRM triage loop for Pharmia pharmacist signups. Classify (OPQ) → enrich + write (Twenty) → reconcile cohorts (Autumn). Owns only the SEQUENCE — each step points at its tool's home. User-invocable."
slug: "crm-triage"
metadata:
  paperclip:
    slug: "crm-triage"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/crm-triage"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/crm-triage"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/crm-triage"
  user-invocable: true
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/crm-triage"
---

# CRM Triage

## When This Applies

A new pharmacist (or batch of pharmacists) has signed up / shown up and needs to
land in the CRM correctly: classified against the OPQ repertoire, enriched, and
its trial/reward cohort kept in sync. Use for one-off signup triage **or** a
periodic batch reconcile.

This skill owns **only the sequence**. Every rule, schema, and entity convention
lives in the tool's home doc — this file points there and never restates it.

## Hard Rule (read first)

**Confirm before any CRM write.** Never run a `twenty gql '<mutation>'` write,
attach a reward, or claw back a cohort grant without explicit team/operator
confirmation of the enriched record. This is rule #4 of the OPQ research protocol
in `~/.claude/rules/twenty-crm.md` — surfaced here because it is non-negotiable
and easy to skip in a batch loop. Read-only classification and lookups need no
confirmation; writes do.

## The Loop

### 1. CLASSIFY — `opq-verify`

The single classification primitive. Resolves a name or license number against
the live OPQ repertoire and returns the canonical class.

```bash
opq-verify classify "<name-or-license>" --json
```

Returns JSON: `{ "class": "...", "licenseNumber": "...", "city": "...", "matchConfidence": "..." }`
where `class` is `student` | `licensed` | `unknown`. Add `--human` for a
one-line stdout summary, `--refresh` to force-refetch the OPQ index.

Do **not** restate classification rules here — `opq-verify` is the source of
truth for what counts as student vs licensed and how confidence is scored. Treat
its output as authoritative. A `weak` / low `matchConfidence` or `unknown` class
means you do **not** have a confident match — escalate to the enrich step's
web/OPQ cross-reference before deciding, and never auto-write on a weak match.

### 2. ENRICH + WRITE — `twenty`

With the class in hand, enrich (web search + OPQ cross-reference for title,
pharmacy affiliation, ownership status, city) and write the record to Twenty CRM.

```bash
twenty gql '<mutation>'    # let GraphQL generate UUIDs; never hand-craft them
```

Never use raw SQL for writes — all writes go through GraphQL.

**All entity rules live in `~/.claude/rules/twenty-crm.md` — do not duplicate
them here.** Read it for:

- People / Companies — keep current, enrich title + workplace + affiliations.
- Opportunities — owner-operators / pharmaciens proprietaires → contract path.
- Tasks — strategic moves (VC/partnership intros), not operational to-dos.
- The full OPQ research protocol (verify → web-enrich → confirm → write → flag
  discrepancies) and trial rules.
- The confirm-before-write rule (#4) restated above.

Cross-reference the `opq-verify` result against what the signup/team claims and
**flag any discrepancy** (e.g. claims licensed, OPQ says student/unknown) before
writing.

### 3. COHORT RECONCILE — `autumn`

Reconcile the Autumn trial/reward cohort against the Twenty roster: grant the
right reward to newly-triaged signups, claw back grants for records that fell out
of the cohort.

```bash
autumn customers --since 7d                      # newly-signed cohort (30m|6h|7d|2w | ISO | epoch)
autumn rewards                                   # list reward/coupon definitions
autumn reward:attach <email-or-id> <reward>      # grant (e.g. student free-trial)
autumn cancel <customer> <product> [--now]       # claw back a subscription grant
```

`autumn customers --since <marker>` pulls the new-signup batch to triage;
`autumn rewards` enumerates the grant definitions; `reward:attach` applies one
(student vs licensed gets different rewards — decide from step 1's `class`).
`reward:attach` / `reward:redeem` print the raw Autumn API error verbatim on
failure — read it, don't retry blindly. Run `autumn --help` for the full surface
(`overview`, `debug`, `find`, `anon:clean*`).

Every grant or claw-back is a CRM-affecting write → **confirm before applying**
(hard rule above).

## DRY Pointers (single source of truth)

- Classification rules + OPQ index → `opq-verify` (`opq-verify --help`)
- CRM entity rules, OPQ research protocol, confirm-before-write → `~/.claude/rules/twenty-crm.md`
- Reward / cohort definitions + Autumn surface → `autumn --help`

This skill adds nothing those three own. If a rule here drifts from them, they win.
