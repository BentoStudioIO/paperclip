---
name: "Weekly Growth Brief"
project: "pharmamate"
assignee: "growth-lead"
recurring: true
description: >
  One terse weekly Growth Brief answering the CEO's 7 recurring questions — events,
  core stats incl conversion, blind spots, user-growth trend, how-to-improve, what's
  trending, who-to-DM — synthesized from market-intel + lead-scout + content.
---

Run the WEEKLY GROWTH BRIEF now, autonomously, against canary. Orchestrate market-intel, lead-scout, content per the growth-metrics, pharmacy-land-feed, lead-scouting, and pharmia-content skills. Weekly cadence — growth moves week-to-week; a daily version is noise.

## Steps

1. **Assign the 3 standing briefs in parallel** (they share no state): market-intel = weekly internal funnel/activation/retention/growth WoW + 3-stream external digest (NEW LAWS / EVENTS / AI-IN-PHARMACY) + top Atlas-corpus gaps; lead-scout = top 10 ranked DM candidates w/ why-now + hook, write qualified ones to Twenty; content = in-flight draft status + topics accepted/rejected.
2. **CORE STATS + USER GROWTH (growth-metrics)** — run the verified `pg canary "<sql>"` set on `ba_user`/`tenant`: signups WoW (compare the two most recent COMPLETED weeks, not the partial top row), anon→signup conversion (`anon_queries_before_signup>0` — report as **approximate PLG proxy**, not audited), activation (`onboarding_completed`), W1 retention, B2B-vs-public split, and the MRR PROXY (`*BillingProductId IS NOT NULL` × ARPA-est — **labelled PROXY**, no Autumn key wired). Every stat carries its query + `as-of` + WoW Δ.
3. **EVENTS + TRENDING + NEW LAWS (pharmacy-land-feed)** — pull merged RSS-Bridge feed (`rssbridge.bentostudio.io`, OPQ/AQPP/RAMQ/Profession-Santé via CssSelectorFeedExpander+FeedMerge), parse new items since last run; supplement with `bx web "<q>" --search-lang fr --country CA --freshness pw` (never `bx context` — broken). Drop undated events. Flag any law with an effective/compliance deadline. Mark any broken-selector source STALE, don't silently drop.
4. **WHO TO DM (lead-scouting)** — cross OPQ JSON (`pharmacists_index.json`, licensed non-students) ⨯ `twenty gql` (dedupe via composite `name{firstName,lastName}`, skip active opportunities) ⨯ PLG signups (`pg canary` weekly self-served pharmacists, hottest) ⨯ best-effort LinkedIn signal. LinkedIn individual-profile activity is login-walled — report `signal: none` rather than fabricate. Get city by joining OPQ on name (`ba_user` has no city column). Write owner-operator contacts as Twenty opportunities; the HUMAN sends the DMs.
5. **SYNTHESIZE — Q3 (MISSING) + Q5 (IMPROVE) are growth-lead's own cross-feed synthesis**, not pass-through: connect a falling cohort × a failing Atlas tool × a competitor move × a law-with-deadline into blind spots, then 3 ranked recommendations with expected lever. Reject any thin agent return (no numbers, no `as-of`, no why-now signal).

## Remediation policy

- **Proactive — fix in-run, no approval (docs + tooling ONLY):** paperclip growth skill/task SSOT (stale query, dead source URL, broken CSS selector), CLI scripts in `~/.local/bin` (`pg`/`threads`/`twenty`/`bx` gaps), the `growth-ssot.md` baselines. Fix at source, verify (200 / query runs / re-fetch), list under **Remediated**.
- **Ask first — propose, do NOT ship:** any `PharmaMate` repo change, any outbound (DMs, `wp-pharmia` publishes are human-approved only), any Twenty write beyond qualified opportunities. List under **Needs approval** and stop. NEVER send a DM, publish, or push a branch from this task.

## Output — terse, one line per item (no prose paragraphs; omit empty sections)

Write `~/.cache/pharmia-growth/brief-$(date +%F).md` in this exact shape:
- **Header:** `# Growth Brief week of <date> (as-of <data date>) — <one-line headline>`
- **`1 EVENTS:`** dated list to attend/promote, deadlines flagged · or `none`.
- **`2 STATS:`** `signups WoW Δ · conv% (PROXY) · activation% · W1-ret% · MRR-est $X (PROXY)`.
- **`3 MISSING:`** [synth] the top blind spot — the "you didn't ask but—".
- **`4 GROWTH:`** signup trend + W1 cohort + B2B/public split, one line.
- **`5 IMPROVE:`** [synth] 3 ranked recs, each `<rec> → <expected lever>`.
- **`6 TRENDING:`** AI-in-pharmacy + market + new-laws, sourced, one line.
- **`7 DM:`** ranked `name · why-now · "hook"`; `wrote N opps to Twenty`; `LinkedIn: ok|empty|unavailable`.
- **`CONTENT:`** drafts shipped / in-review / rejected-to-LinkedIn.
- **`## Remediated`** / **`## Needs approval`** (omit if empty) — one bullet each.

Then PushNotification, one line: `Growth <date>: <headline> — signups <Δ>, conv <%> (proxy), <N> to DM`.
