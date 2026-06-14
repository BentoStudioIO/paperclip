# bento-docs — Bento Studio durable knowledge (local copy)

**Local path:** `/home/agent/bento-docs` (standing read-only reference; refreshed daily
via cron from Forgejo `git.bentostudio.io/BentoStudio/bento-docs`, branch `main`).

bento-docs is Bento Studio's **SSOT for durable legal / compliance / regulatory
knowledge** — held as **verbatim primary sources** and **frozen-in-time evidence**.
It is the authoritative, distrust-resistant source for any legal/compliance/TGV claim.
Read it (and quote it) BEFORE asserting what a law, regulation, certification, or
official guidance says — verbatim source over derived analysis, summaries, or TODOs.

## What is actually here (current `main`)

- `sources/legal/` — verbatim primary statutes & official guidance, sha256-pinned in
  `MANIFEST.yaml`. Subtrees: `law25/`, `pipeda/`, `bill3-r22-1/`, `soc2/`, `tgv/`,
  `general/`. **Immutable** — never modify; `./verify.sh hash` checks integrity.
- `derived/legal/tgv/` — frozen TGV (Quebec MSSS) submission **evidence** blobs, each
  with a capture date. See `derived/legal/tgv/AGENTS.md` for the TGV SSOT contract.
- `_audit/legal/` — frozen reconciliation archives (`<date>-<topic>/`).
- `README.md`, `AGENTS.md` — the repo's own trust contract. **Read `AGENTS.md` first**;
  it is the authority on what belongs here vs Comp AI.

> NOTE: this repo is currently **legal/compliance-only**. There is no top-level
> `pharmacy/` or `design/` content in `main` today — do not cite paths that don't exist.
> Pharmacy/design knowledge lives elsewhere (Outline; Paperclip pharmia templates).

## When to consult it

- Before answering "what does <law/reg/cert> say" (Law 25, PIPEDA, Bill 3 / R-22.1,
  SOC 2, TGV/MSSS) — open the verbatim file under `sources/legal/<area>/` and quote it.
- Before recommending compliance/regulatory scope, or citing TGV evidence.
- Treat it verbatim-first: quote the source file before any derived recommendation.

## What is NOT here — Comp AI (the GRC platform)

Authored, lifecycle content (current-state claims, policies DOC-*, control statuses,
per-criterion narratives, attestations) lives in **Comp AI**, NOT bento-docs. Query it:

    comp policies search "<terms>"     # find a policy
    comp policies show <id-or-title>   # render the authored policy
    comp controls list --framework tgv # per-framework control status

Rule of thumb: **verbatim external source or frozen evidence → bento-docs; anything
authored with a lifecycle/status → Comp AI.**
