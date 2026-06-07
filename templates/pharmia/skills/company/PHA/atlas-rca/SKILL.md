---
name: "atlas-rca"
description: "Standardized root-cause-analysis sequence for 'why did this Atlas thread behave wrong'. Use when handed an Atlas thread URL or a report of a bad/odd/incomplete/garbled answer. Owns only the investigation SEQUENCE — model facts live in pharmia-agents, render pitfalls in atlas-render-regression."
slug: "atlas-rca"
metadata:
  paperclip:
    slug: "atlas-rca"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-rca"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-rca"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-rca"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-rca"
---

# Atlas RCA — "Why Did This Thread Behave Wrong"

Run this sequence WHENEVER you're given an `admin.{dev,qa,canary}.pharmia.ca/atlas?thread=…`
URL, a share link, or a report of a bad Atlas answer (wrong, incomplete, garbled,
truncated, fabricated citation, missing answer). This skill owns ONLY the
sequence. It does not restate the model ring, per-model prices, or render-mender
internals — those are single-sourced elsewhere (see DRY note at the bottom).

## Step 0 — Known-Cause Check (do this BEFORE investigating)
Most Atlas pathologies are already banked. Grep the memos before spending a single
`threads` call:

```sh
grep -rl '<symptom keyword>' ~/.claude/projects/-home-vortex-Documents-PharmaMate/memory/
```

Match the symptom against these banked failure modes first:
- `atlas-tool-health-canary.md` — tool failures / timeouts / empty tool yields on canary.
- `atlas-disconnect-silent-loss.md` — answer never persisted (client disconnect
  mid-turn flips Mastra's `onFinish` save-gate off → silent loss). Symptom: "the
  answer was there then vanished / the thread ends mid-sentence with nothing saved".
- `atlas-ring-defaultoptions-bug.md` — mixed-provider ring leaked tier-0
  providerOptions to tier-1+ (daily morning Sonnet-rescue spike). Symptom: wrong
  served model at a particular time of day.
- `atlas-cost-om-tool-volume.md` — cost / prefill / OM-threshold questions (cost is
  per-turn tool-result prefill, not depth). Symptom: "why is this thread so
  expensive / so many tokens".

If the symptom matches a banked memo, cite it and jump straight to the VERDICT —
don't re-derive a known root cause.

## Step 1 — Reconstruct The Turn
```sh
threads <admin-or-share-url> --rca
```
RCA mode renders every message part untruncated. Read for:
- **Per-tool yield** — which tools ran, full args + full result, and whether any
  returned empty / errored (a tool that returned nothing is the usual cause of a
  thin or hallucinated answer).
- **Citation → source / fabrication map** — does each `<cite>` / `<pharmia-source>`
  map to a real tool result, or did the model invent one? Unsupported citations =
  model fabrication, not a render bug.
- **Per-turn prefill / OM status** — `data-om-status` (active/buffered window
  tokens), buffering cycles, and inter-message timing deltas explain follow-up
  decisions and cost.
- If `threads --rca` lacked something you had to fetch elsewhere, EXTEND the
  `threads` CLI in the same task (it self-documents this rule).

## Step 2 — Served-Model / Ring Check
Per-turn truth is the structured `[Atlas] stream-result` log (service
`pharmia-api`): `servedProvider` / `servedModel` = what actually answered, plus
`fallbackFired`, `primaryTimedOut` / `primaryErrored` / `guardTripped` for WHY a
fallback fired. Fleet mix in one command:
```sh
threads modelmix <env> [--since DUR]
```
> For WHICH model SHOULD serve, the ring/tier table, and per-model behavior:
> point at the **`pharmia-agents`** skill. Do NOT restate the ring or model table
> here — read it there so the facts can't drift.
>
> Never answer "kimi vs gemini" by grepping model ids in Loki — that count is
> polluted by Loki's own querier logs echoing your search string and by
> ring-config lines that mention every tier. Use `threads modelmix` /
> `[Atlas] stream-result` only.

## Step 3 — Attribution Tree (isolate the failing layer)
Walk down until one branch matches; this picks the fix owner:
- **Tool layer** — a tool errored / timed out / returned empty (Step 1 yield, or
  `atlas-tool-health-canary.md`). → answer is thin/wrong because the model had no
  data. Owner: tool / backend.
- **Model layer** — tools returned good data but the model ignored it,
  fabricated a citation, or the WRONG model served (Step 2). Owner: agent config
  → gate any change through `model-config-gate` + `pharmia-agents`.
- **Render layer** — the data + model output were correct but the answer DISPLAYED
  wrong (broken mermaid, escaped `<cite>`/`<pharmia-source>` tag, mangled fr-CA
  math/currency, cramped table, uppercase leakage, unrendered spec fence).
  → the persisted text is fine, the pipeline mangled it. Point at the
  **`atlas-render-regression`** skill for the exact pitfall class, the file:line,
  and the repro harness — and write a failing repro before fixing.
- **Persistence / disconnect layer** — the answer streamed but was never saved, or
  the thread is non-durable (`atlas-disconnect-silent-loss.md`). Owner: stream
  lifecycle / `onFinish` save-gate.

Disambiguator: if the SAME raw text renders fine in a fresh load but looked wrong
live, it's RENDER (streaming-only mender gap), not model. If the raw text itself is
malformed/fabricated, it's MODEL/TOOL, not render.

## Step 4 — VERDICT (mandatory — always end with this block)
Never stop at "looks like X". Emit:

```
VERDICT
- Root cause: <one sentence, concrete>
- Layer:      <tool | model | render | persistence/disconnect>
- Evidence:   <thread id + the specific log line / tool yield / cite-map / memo>
- Fix owner:  <skill or file to action: pharmia-agents | atlas-render-regression |
               model-config-gate | tool/backend | stream lifecycle>
- Known/new:  <cite the banked memo, OR "new — bank a memo">
```

If it's a NEW failure mode (no Step-0 memo matched), say so and recommend banking a
memo under `~/.claude/projects/-home-vortex-Documents-PharmaMate/memory/` so the
next RCA short-circuits at Step 0.

## DRY — This Skill Owns ONLY The Sequence
- Model defaults, the Atlas ring/tier table, per-model behavior → **`pharmia-agents`**.
- Render pitfalls, mender file:line, repro harnesses → **`atlas-render-regression`**.
- Per-model prices / ZDR / cache boundary → `providerPricingCatalog.ts` via
  `model-config-gate`.
- Banked thread-level failure modes → the `atlas-*` memos (Step 0).

Do not duplicate any of that here. If a fact would belong in one of those, put it
there and link.
