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

## Write authorization (read first)

- **Interactive / batch / destructive writes** — operator-run triage, cohort
  reconcile, `reward:attach`, cohort claw-back, deletes: **confirm before
  writing.** Read-only classification and lookups never need confirmation.
- **Autonomous watch** — a single signup/booking trigger enriching ONE record
  via `twenty person upsert` + `twenty note add` (idempotent by design): write
  WITHOUT per-record confirm. This is the only autonomous-write exception.

The field/enum model, the `twenty` subcommands, and the ownership +
identity-enrichment procedure are in
[`references/twenty-entity-rules.md`](references/twenty-entity-rules.md). This
skill is runtime-self-contained — it does NOT depend on `~/.claude/rules/`.

## The Loop

### 1. CLASSIFY — OPQ repertoire

Resolve the name/license against the live OPQ repertoire → student | licensed | unknown.

- If `opq-verify` is installed: `opq-verify classify "<name-or-license>" --json` (authoritative class + confidence).
- Otherwise (e.g. the agents-VPS runtime — `opq-verify` is NOT there): use the raw OPQ index — see the OPQ block in [`references/twenty-entity-rules.md`](references/twenty-entity-rules.md).

A weak/unknown match means you do **not** have a confident match — an empty OPQ
result is NOT "not a pharmacist". Run the identity-enrichment procedure (LinkedIn
/ web / alt ordres, in the references file) before deciding; never auto-write on a
weak match without enrichment.

### 2. ENRICH + WRITE — `twenty`

With the class in hand, enrich (ownership detection + identity enrichment — both
MANDATORY, procedures in the references file) and write via the high-level
`twenty` subcommands (never raw gql, never hand-crafted UUIDs):

```bash
twenty person get <email|phone|name> --json          # lookup/dedupe FIRST
twenty person upsert --email X --first .. --last .. --phone +1.. --city .. \
  --job-title ".." --source <enum> --tenant <slug> --group <enum> \
  --pharmia-user-id <ba_user.id>     # CRM<->app link → marks them an Atlas user.
                                     # Set whenever they have a Pharmia account; get
                                     # id via `pg canary app "SELECT id FROM ba_user
                                     # WHERE lower(email)='<email>'"`. No scheduled sync
                                     # sets this — pharmia-twenty-atlas-sync is a manual
                                     # helper that fills pharmiaUserId only; set it yourself.
twenty opportunity get --person <id>                 # dedupe before creating
twenty opportunity create --name ".." --stage MEETING --close-date <ISO> --person <id>
twenty note add --title ".." --md ".." --link person:<id> [--link opportunity:<id>]
```

**Entity model, enums, ownership detection, identity enrichment (OPQ-empty),
name-splitting, and Note structure → [`references/twenty-entity-rules.md`](references/twenty-entity-rules.md)** (runtime-self-contained).
Key rules: `source`=origin vs `group`=persona (distinct); owner-operators are the
top cohort (detect, never skip); always `person get`/`opportunity get` before
create (dedupe). Flag any discrepancy (claims licensed, OPQ says student/unknown)
before writing.

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

- CRM entity model, enums, ownership/identity procedures, write-authorization → [`references/twenty-entity-rules.md`](references/twenty-entity-rules.md) (the runtime SSOT; keep in sync with the human-side `~/.claude/rules/twenty-crm.md`)
- OPQ index → raw curl (in the references file); `opq-verify` if installed
- Reward / cohort definitions + Autumn surface → `autumn --help`
