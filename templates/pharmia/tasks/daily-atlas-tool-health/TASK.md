---
name: "Daily Atlas tool-health"
project: "pharmamate"
assignee: "devops"
recurring: true
description: >
  Host detector for Atlas quality — user-dissatisfaction signal
  (atlas_message_reaction dislikes + question-chain pushback), then
  tool/render/citation correctness + capability-gap detection. Collect evidence,
  write the health report, and route confirmed follow-ups without blocking the
  recurring detector issue.
---

Run the DAILY ATLAS HEALTH CHECK now, autonomously, against canary. You are the
host detector: collect the CLI-backed evidence first, then write the health
report. Use the atlas-rca and atlas-render-regression skills; consult the
[[atlas-tool-health-canary]] memo for known failure modes instead of re-deriving
them.

Detect by PRINCIPLE, not by matching past incidents — the examples in the memos are illustrations of a class, not the whole class. A new failure that doesn't match a banked one still counts.

## Steps

1. **User satisfaction FIRST — the most direct quality signal.** `threads chains canary --since 30h` and READ the chains. (30h, not 24h: rolling window + once-daily cadence → ~6h overlap so no thread is missed if a run drifts late; the dedup below absorbs it. Prior run skipped / >1d ago → widen to 48h+.) It dumps each thread's user turns verbatim and folds in `atlas_message_reaction` dislikes (`[DISLIKE]`). You are the judge — no regex: flag any chain where a follow-up implies the prior answer **missed** — the user re-asks the same thing, demands a better/stronger source, corrects or disputes a fact, re-narrows because the answer was too vague, or abandons the topic. (Dislikes are rare, ~single-digits/month — sweep with `--since 7d` periodically.) Cross-check yesterday's `~/.cache/pharmia-health/atlas-*.md` and SKIP already-actioned chains. For each flagged chain, open it (`threads canary <id> --rca`), run the atlas-rca tree, and route by layer: source/quality demand → citation or coverage; "not what I asked" / re-ask → routing or comprehension; disputed fact → fabrication or stale corpus; user-flagged dead URL → Step 5. Triage every one; leave none.

2. **Fleet.** `threads modelmix canary --since 24h` — provider mix, fallback %, why it fired. Note material drift vs the prior run.

3. **Sample threads for correctness.** Inspect a handful of recent threads for three classes: unrendered/leaked markup (per atlas-render-regression), fabricated or uncited clinical claims, and any tool returning an error / an empty result where data should exist / stale or junk passthrough. (`threads <url>` handles compound ids; no rows on a very fresh thread = flush race → retry, or `pg canary mastra` on `mastra_messages` `thread_id like '<uuid>%'`.)

4. **Capability gap vs routing.** Find turns where Atlas struggled: many tool calls in one turn, repeated low-yield retrieval, or webSearch leaned on as a fallback. Diagnose what was sought and why the tools didn't supply it, then classify — **(a) COVERAGE** (no tool/source can answer → propose a concrete capability upgrade) vs **(b) ROUTING** (a capable tool/doc exists but wasn't chosen → propose a prompt/routing fix). **Before calling anything COVERAGE, VERIFY ABSENCE — never infer a missing doc from "it webSearched a lot":** `ol search` the corpus (a doc exists ⇒ not coverage); read the thread's `readClinicalReferences` documentIds (read-but-overrode ⇒ routing); re-probe the failing tool live (resolves on retry ⇒ transient/retry-fix). See [[feedback_verify_absence_before_claiming_gap]]. Quantify each finding (tool, count, what was sought).

5. **Citation-URL validation + standing corpus linkcheck.** From the sampled threads, curl each emitted `<pharmia-source>` URL (`curl -sL -o /dev/null -w '%{http_code}'`); any 4xx/5xx → trace provenance and fix the right layer: stale URL in an Outline doc → fix at the Outline source; readUrls/webSearch passed a broken link → grounding fix; model invented the URL → citation-contract fix. **Every run** (background it early, read it late): `ol linkcheck --collection 50a7902d-439f-479a-9469-43926a4206a5 --json`. TRIAGE BY STATUS — most flags are anti-bot FALSE POSITIVES: `401/403/429` and any `3xx→000` are live-behind-a-bot — re-verify with a browser UA / `curl_cffi impersonate='chrome136'` before believing dead. Only `404/410/500` and hard `000` (no redirect) are REAL dead. Fix real-dead at the Outline source (`ol doc get <id> --raw` → atomic, count-verified python replace → `ol doc update <id> --file … --no-link-check`; verify 200); no live equivalent → drop the URL, keep the citation text. Group identical dead URLs, fix all siblings in one pass.

## For every issue

Don't stop at detection — root-cause it (`threads <id> --rca`/`--tools`/`--json`), name the failing layer (tool/model/render/persist/coverage), confirm the mechanism. GROUP findings that share one root cause. Each group → ONE concrete action item: owner file/skill + fix + how to validate. Validate cheaply when you can. Render fixes name a repro harness (atlas-render-regression); model/prompt fixes route through model-config-gate.

If a finding needs observer/product/clinical judgment after evidence collection,
create a child issue for AI Product Observer or Pharmacy Lead with the report
and raw evidence pointers. Do not block this recurring detector issue on that
follow-up; mark this issue done after the report is posted and any follow-up
issues are created.

## Remediation policy

- **Fix in-run, no approval (docs ONLY):** Outline/corpus docs and local health-report files. Fix at source, verify, list under **Remediated**.
- **Ask first — propose, do NOT ship (code/config/tooling):** any repo, script, CLI wrapper, dashboard, prompt/model/routing, eval, render mender, deploy, or app change — including `PharmaMate`, Paperclip SSOT, and `~/.local/bin`. Back with a failing→green repro/eval, list under **Needs approval**, stop. NEVER push a branch, open a PR, deploy, or mutate live config from this task.

## Output — STANDARD + CONCISE

Write `~/.cache/pharmia-health/atlas-$(date +%F).md`. HARD rules: one line per item; no prose paragraphs; no multi-sentence bullets; omit empty sections. **If GREEN, emit ONLY the header + the four signal lines** — nothing else.

- **Header:** `# Atlas Health <date> — GREEN | N issue(s)`
- **Four signal lines** (always, this order, each ≤1 line):
  - `Satisfaction:` chains read · # dissatisfaction · dominant kind (source-demand | not-what-asked | wrong-fact | abandon) — or `ok`
  - `Fleet:` provider mix · fallback% · drift vs prior (benign?)
  - `Signals:` tools · render · citations · URLs — each `ok` or a count
  - `Capability:` `none` | `tool×count: what was sought → coverage|routing`
- **`## Issues`** (omit if none) — one line each, fixed grammar:
  `[tool|model|render|persist|coverage] <symptom ≤12 words> — RC <one clause> → REMEDIATED <doc/cli> | ASK <file> | SHIPPED <sha> | RETRACTED <why>`
- **`## Remediated`** (omit if none) — `<doc-id|cli|url>: <what> (verified <how>)`
- **`## Needs approval`** (omit if none) — `<file>: <fix> — validate <repro/eval>`

Then PushNotification, one line: `Atlas <date>: GREEN` — or `Atlas <date>: N issues, k remediated, j ask — <worst ≤10 words>`.
