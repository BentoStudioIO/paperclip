---
name: "pharmacy-land-feed"
description: "Runnable EXTERNAL feed spec for market-intel: RSS-Bridge (CssSelectorFeedExpander + FeedMerge) over QC pharmacy sources, plus bx (Brave) digest. Three priority streams: NEW LAWS, EVENTS, AI-IN-PHARMACY."
user-invocable: true
---

# pharmacy-land-feed

The EXTERNAL engine for market-intel. Two tools: **RSS-Bridge** (self-hosted, turns scrapeable pages into
feeds) at `https://rssbridge.bentostudio.io`, and **`bx`** (Brave Search CLI) for fresh news/laws/events.
All source URLs below were validated 200 (2026-06-08).

## RSS-Bridge — pharmacy sources (per-source, then merged)
Each source becomes a feed via **`CssSelectorFeedExpanderBridge`**, then all are combined with
**`FeedMergeBridge`**. Pattern (URL-encode values):
```
# Single source → feed:
https://rssbridge.bentostudio.io/?action=display&bridge=CssSelectorFeedExpander
  &feed=<list-page-url>
  &content_selector=<article-body-css>
  &limit=15&format=Atom

# Merge N source-feeds into one:
https://rssbridge.bentostudio.io/?action=display&bridge=FeedMerge
  &feed_1=<encoded-source-feed-1>&feed_2=<...>&feed_name=PharmacyLand&limit=40&format=Atom
```
Sources to wire (list page → feed):
- **OPQ** — `https://www.opq.org/nouvelles/`
- **AQPP** — `https://www.aqpp.qc.ca/` (actualités section)
- **RAMQ pharmaciens infolettres** — the RAMQ "infolettres pharmaciens" listing page
- **Profession Santé** — pharmacie section

Fetch the merged feed each cycle; parse new items since last run by `<updated>`. If a source's CSS
selector breaks (site redesign), report the source as STALE — don't silently drop it.

## bx — fresh digest (news/laws/events RSS-Bridge can't surface)
`bx web "<q>" --search-lang fr --country CA --freshness pw` (past-week). Parse JSON with python3/jq. Use
`bx news` for time-sensitive. **`bx context` mode is broken — always `bx web`.**

## The three priority streams (market-intel's required output)
1. **NEW LAWS** — regulatory changes affecting pharmacist practice/scope/billing.
   - RSS-Bridge: OPQ + RAMQ infolettres (above).
   - `bx web "Loi pharmacie Québec P-10 modification" --freshness pw`
   - `bx web "LegisQuébec P-10 pharmacien" ` / `bx web "Assemblée nationale projet de loi pharmacie"`
   - **Flag anything with a compliance deadline** (effective date) for the Growth Brief.
2. **EVENTS** — congresses/conferences to attend or promote.
   - `bx web "congrès pharmacie Québec 2026" --freshness pm`
   - `bx web "AQPP OPQ événement formation pharmacien" --freshness pm`
   - Output each with **date + city + attend|promote**. Drop undated items.
3. **AI-IN-PHARMACY** — competitor moves, new tooling, AI-in-clinical signals.
   - `bx web "intelligence artificielle pharmacie Canada" --freshness pw`
   - `bx web "AI pharmacist clinical assistant" --freshness pw`
   - Profession Santé feed (RSS-Bridge) cross-check.

## Output to market-intel
```
NEW LAWS: <item · source URL · effective/deadline date?>
EVENTS:   <item · date · city · attend|promote>
TRENDING: <AI-in-pharmacy + market, 3-5 sourced bullets>
STALE:    <any source whose selector/feed broke this run>
```

## Discipline
- Every item carries a source URL. No unsourced claims.
- Validate any new source URL with `curl -sL -o /dev/null -w "%{http_code}"` (must be 200) before wiring.
- LinkedIn is OUT — login-walled; jina/camofox can't read it. That's lead-scout's n8n pipeline.
