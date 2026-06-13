---
title: n8n CRM-enrichment workflows are superseded by lead-scout — retire, don't port
status: accepted
date: 2026-06-13
deciders: amine (CTO)
supersedes:
superseded-by:
---

## Context

The 2026-06-13 n8n → paperclip migration sweep flagged two n8n workflows as "agentic CRM enrichment" candidates:

- **Sheet to Twenty** (`TVyB8GSULVO2ZTqr`, **inactive**) — Google-Sheet row → OpenRouter agent (+ Exa MCP) extracts a pharmacist's phone/email/LinkedIn/site → creates Twenty company/person/opportunity.
- **AI web researcher for sales** (`aQ2VQlxuC9FVmiQI`, **inactive**, 2 sub-workflow refs already broken/null) → schedule + Sheet → OpenAI agent (+ SerpAPI, ScrapingBee) researches a company (domain, pricing, case study, enterprise/free-trial) → writes back to the Sheet.

Both are off. Both do "enrich a pharmacist/company contact, then write to the CRM." The migration question: port them as new paperclip routines?

## Decision

**No new routine.** These are already covered by existing paperclip machinery — retire them on n8n with no paperclip equivalent:

- the **`lead-scout`** agent (`agents/lead-scout/AGENTS.md`) crosses OPQ repertoire ⨯ Twenty ⨯ online-activity signal ⨯ PLG signups into a ranked DM list and **writes qualified opportunities to Twenty** (`lead-scouting` + `crm-triage` skills);
- the **`weekly-growth-brief`** routine already runs lead-scout's WHO-TO-DM step weekly;
- CRM writes go through the `twenty` CLI (high-level `person upsert` / `opportunity create`), not a bespoke workflow.

## Rationale

DRY / single-source-of-truth. lead-scout is the SSOT for "find + qualify + write a pharmacist contact to Twenty." Re-implementing the two n8n flows as routines would duplicate that machinery and split CRM-write policy across two owners. Neither workflow is load-bearing (both inactive; one already broken), so there is nothing live to preserve — the cost of porting is pure duplication with zero capability gained.

## Alternatives considered

- **Port each as a paperclip routine** — rejected: duplicates lead-scout + the growth-brief WHO-TO-DM step; splits the "write to Twenty" contract.
- **Leave them on n8n** — rejected: both inactive, and the directive is to consolidate off the n8n UI; a dead inactive workflow is debt, not capability.
- **Fold the Google-Sheet *ingestion* path into lead-scout** — deferred: only worth it if a live "sheet of prospects to enrich" inbox actually exists. It does not today (workflows inactive). If such an inbox returns, add it as a lead-scout input, not a new routine.

## Consequences

- positive: no duplicate CRM-enrichment machinery; one owner (lead-scout) for all Twenty writes.
- negative / dependency to resolve before *full* n8n decommission: lead-scout's `AGENTS.md` (§ signal source 3) names "the EXISTING n8n + Browserless LinkedIn pipeline" as its online-activity signal. The only **deployed** Browserless use in n8n is **Pharmia Posts** scraping Pharmia's *own* LinkedIn feed — NOT a prospect-activity pipeline. The key-people LinkedIn-activity scraper lead-scout implies corresponds to the **undeployed** community template (`Monitor LinkedIn Posts…`, 30 nodes, never pushed). So lead-scout's LinkedIn signal is currently **aspirational, not wired**. Killing n8n does not remove a real signal source here — but lead-scout's prompt overstates what exists.
- mitigation: correct the lead-scout skill/AGENTS wording to "LinkedIn activity signal = best-effort / not yet wired" (truth-in-prompt), tracked separately. Until then lead-scout already self-reports `LinkedIn: unavailable`, so no fabrication risk.

## Related

- Full inventory + the two-tier routine/plugin model: memory `n8n-estate-and-paperclip-migration`.
- lead-scout: `agents/lead-scout/AGENTS.md`; skills `lead-scouting`, `crm-triage`.
