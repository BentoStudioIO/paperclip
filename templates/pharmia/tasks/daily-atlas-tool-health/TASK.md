---
name: "Daily Atlas tool-health"
assignee: "ai-product-observer"
recurring: true
description: >
  Atlas thread/tool-health + capability-gap detection — unrendered tags, fabricated
  data, tool failures, AND missing-info/over-search patterns that warrant a capability
  upgrade. Produces grouped root-cause analysis + concrete action items.
---

Run the DAILY ATLAS HEALTH CHECK now, autonomously, against the canary environment. Use the atlas-rca and atlas-render-regression skills.

## Steps

1. Run `threads modelmix canary --since 24h` for the fleet model/fallback picture.
2. Sample a handful of recent canary Atlas threads via the `threads` CLI and inspect them for: unrendered markup/tags, fabricated or uncited clinical data, and tool failures (esp. getDrugShortages 401-on-stale-token, searchPubmed hard-empty, readUrls junk/403 passthrough, healthCanadaSearch empty). If the `threads` CLI returns no rows for a compound thread id, fall back to `pg canary mastra` on `mastra_messages` (filter `thread_id like '<uuid>%'`).
3. Confirm external clinical tools return the expected shape.
4. **Capability-gap / missing-info detection.** Find turns where Atlas struggled to find the answer: high tool-call counts in a single turn, repeated or low-yield retrieval, and especially webSearch used multiple times as a fallback (a tell that the dedicated clinical tools could not supply the answer — e.g. one real turn fired 5× webSearch + 3× readUrls + 2× searchPubmed = 17 tool calls). For each, diagnose WHAT information was being sought and WHY the existing tools did not supply it, then distinguish: (a) a genuine COVERAGE gap — no tool can answer it → propose a concrete capability upgrade (a new tool, a new/expanded data source or index, a catalog/dedup addition); vs (b) a ROUTING miss — a capable tool exists but was not chosen → propose a prompt/routing fix. Quantify each finding (tool, count, what was sought).

## For every issue

Do NOT stop at detection — investigate the ROOT CAUSE directly: pull the raw turn with `threads <id> --rca` / `--tools` / `--json`, identify the failing layer per atlas-rca (tool / model / render / persistence / coverage), and confirm the mechanism (e.g. an Outline 404, a hallucinated id/cite, an invalid mermaid type, a missing data source). GROUP findings that share one root cause. For each group propose a CONCRETE action item: owner skill/file + the fix + how to validate (an eval scenario, or a failing→green repro in `tooling/`). Cheaply validate a proposed fix when you can (e.g. run `mermaid.parse` from repo root). Render fixes must name a repro harness per atlas-render-regression; model/prompt fixes must route through model-config-gate.

## Output

Write the full findings to `~/.cache/pharmia-health/atlas-$(date +%F).md` with a ROOT-CAUSE ANALYSIS + ACTION ITEMS section and a CAPABILITY UPGRADES subsection (say "all healthy" if nothing found), then call the PushNotification tool with a one-line summary of issues found (or "Atlas health: all green").
