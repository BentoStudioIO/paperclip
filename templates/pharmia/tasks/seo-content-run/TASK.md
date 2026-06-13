---
name: "SEO Content Run"
assignee: "content"
recurring: true
description: >
  Weekly batch that turns new Québec health-news into Pharmia content. Pulls the
  merged QC-health RSS feed, dedups against a local cache, judges each NEW item
  through the content agent's Product-Led-SEO gate, and for the leverage-worthy
  ones produces a WordPress DRAFT article + a LinkedIn DRAFT — posted to Discord
  for human approval. Drafts only; the human approves every publish/post. Replaces
  the 4-workflow n8n SEO pipeline (dispatcher → relevance → SEO+LinkedIn → carousel).
---

Run the SEO CONTENT RUN now, autonomously. Process every NEW relevant QC-health item since the last run in ONE batch, per the `pharmacy-land-feed` (feed pull) and `pharmia-content` (relevance gate, voice, distribution mechanics) skills. You are the **content** agent — your §0 voice contract, §3 SEO-fit gate, §9 self-grade, and draft-by-default/human-approves-every-publish contract all apply; this routine does NOT re-specify them. Weekly batch, not per-item: each fire is a drafting turn that costs tokens and a human review, so cheap polling/dedup stays out of the routine.

This routine is the **content-production engine that feeds the Weekly Growth Brief** — the brief's CONTENT line reports what this run shipped/queued; do not duplicate the brief here.

## Steps

1. **Pull the merged feed + dedup against the local cache.** Fetch the merged QC-health feed from RSS-Bridge (`rssbridge.bentostudio.io`, FeedMerge over the QC health sources) per `pharmacy-land-feed`. The n8n source set is the 7 raw feeds — keep them as the source-of-truth list, prefer the merged RSS-Bridge feed over re-listing them: OPQ (`opq.org/feed`), Le Devoir santé, Radio-Canada santé, INSPQ, quebec.ca fil-de-presse, Journal de Montréal santé, Journal de Québec santé. **Dedup via `~/.cache/pharmia-seo/seen-titles`** — one `source_url` per line (the item `link`, fallback `guid`). Skip any item whose `source_url` is already in the file; this replaces the n8n Postgres `rss_titles` table. Append every item you process (relevant or not) so it is never re-judged. If a source's selector broke (no items), mark it STALE in the output — don't silently drop it.

2. **Judge each NEW item through the Product-Led-SEO gate (FR).** For each new item, apply the content agent's §3 PLG-SEO leverage gate (`pharmia-content/references/product-led-seo.md`) — the **opus content agent IS the judge**, not a separate cheap classifier. Decide: is this news leverageable to sell Pharmia to a pharmacien-propriétaire? Keep the n8n relevance output shape per item, authored in **québécois professional French**:
   - `title` — the item headline
   - `briefSummary` — 2-3 sentences (FR)
   - `relevance` — 1 concise sentence (FR) on how to leverage it to promote Pharmia's features/capabilities
   - `link` — the source URL
   Only **leverage-worthy** items proceed to drafting. Items the gate rejects as no-real-search-demand still route to a LinkedIn draft (founder distribution) per §3 — never silently discard a relevant item; the gate decides the CHANNEL (blog vs LinkedIn), not whether to act. *(Change vs n8n: the n8n `isRelevant?` node dropped any non-relevant item outright; we instead route gate-rejected-but-leverageable items to LinkedIn per §3.)*

3. **Draft the WordPress article (blog channel — DRAFT only).** For each leverage-worthy SEO item, write the long-form FR-Québec article per the agent's §5 (SB7) / §6 (proof hierarchy) and the n8n SEO contract: a logical outline of **15+ headings/subheadings** (H1-H4), 150-200w intro, 300-500w per H2, a "Points clés" takeaways block (5-7 bullets), 200-250w conclusion, **5 FAQs**, and a "Références" section with real source links. SEO-optimized FR title **under 60 chars, NOT title-cased** (French sentence case). Use `bx web` (per `pharmacy-land-feed`) for SERP/competitor and source research — the n8n Exa/Firecrawl/Puppeteer tools are NOT in the paperclip runtime (see capability-gaps). Land it as a WordPress **DRAFT** via `wp` over `ssh momo` (post status `draft`, never publish) — the n8n pipeline also only drafted. **Self-grade §9; block at < 8/10** and return gaps instead of queuing.

4. **Draft the LinkedIn post (DRAFT only).** For each item (both SEO items and gate-rejected-to-LinkedIn items), write a founder LinkedIn post per §6: FR, **"nous"** voice (never first-person singular), engaging with tasteful emojis + relevant hashtags, **≤ 1500 characters**, no invented statistics (keep wording vague where unsourced). This is a **DRAFT for the human** — do NOT auto-schedule or auto-post (drop the n8n Postiz +3-day auto-schedule entirely; see capability-gaps for the absent posting mechanism).

5. **Post candidates to Discord for approval + write the cache summary.** For each item, post one approval candidate to the content Discord channel (preserve the n8n "Wait for approval" pattern): the `title`, **Résumé** (`briefSummary`), **Pertinence** (`relevance`), the WordPress draft link/id, the LinkedIn draft text, and the self-grade. The human approves every publish/post. Then write the terse `~/.cache/pharmia-seo/run-$(date +%F).md` summary (one line per item) and PushNotification once.

6. **(OPTIONAL — capability-gap) LinkedIn carousel render.** If `TEMPLATED_API_KEY` is wired AND a render helper exists, generate the 2-page FR carousel JSON (page 1 `main-title` in bold caps; tags ≤15 chars, 2 per page; bullets begin with `•`) and render it via `POST https://api.templated.io/v1/render` (Bearer auth), attaching the image to the Discord candidate. **If the key or helper is absent, skip this step cleanly — never block the run on it.** See capability-gaps.

## Remediation policy

- **Proactive — fix in-run, no approval (docs + tooling ONLY):** the paperclip SEO skill/task SSOT (a stale feed URL, a broken CSS selector, a dead `bx`/`wp` query), CLI scripts in `~/.local/bin`. Fix at source, verify (200 / feed parses / query runs), list under **Remediated**.
- **Ask first — propose, do NOT ship:** any `wp` publish (anything beyond a DRAFT), any LinkedIn post, any `PharmaMate` repo change. List under **Needs approval** and stop. NEVER publish, post, or push a branch from this task — every artifact this routine creates is a draft awaiting the human.

## Output — Discord candidates + a terse cache summary

Post per item to the content Discord channel (one approval candidate each):
```
### {title}

**Résumé**
{briefSummary}

**Pertinence**
{relevance}

Brouillon blog: WordPress draft #{id} · auto-grade {X}/10
Brouillon LinkedIn:
{linkedin draft text}

Voir plus: {link}
```
Then write `~/.cache/pharmia-seo/run-$(date +%F).md`, one line per item:
- **Header:** `# SEO Content Run <date> — <N> new items, <M> drafted, <K> rejected-to-LinkedIn`
- per item: `<title> · <blog-draft|linkedin-only> · grade X/10 · <discord-posted|blocked<8>>`
- **`STALE:`** any source whose feed/selector broke this run (omit if none).
- **`## Remediated`** / **`## Needs approval`** (omit if empty) — one bullet each.

Then PushNotification, one line: `SEO content <date>: <N> new · <M> drafts queued for approval`.

## Capability-gaps (the deployed content agent will hit these — do not pretend otherwise)

- **Carousel render (Templated.io)** — `https://api.templated.io/v1/render` needs `TEMPLATED_API_KEY` (Bearer), NOT wired in the runtime, and no render helper exists. Step 6 is optional and skips cleanly when absent.
- **LinkedIn posting** — there is NO Postiz/LinkedIn API path in the paperclip runtime; the n8n Postiz draft node does not exist here. This routine produces LinkedIn DRAFT TEXT only; the human posts.
- **SERP/scrape research tools** — the n8n SEO agent's Exa + Firecrawl + Puppeteer MCPs are absent. Use `bx web` (Brave, per `pharmacy-land-feed`) for SERP/competitor/source research; depth of competitive analysis is lower than the n8n version.
- **`wp` / `ssh momo` reachability** — the article-draft step assumes `wp` over `ssh momo` from the agent runtime (per the content agent §8). Verify the `momo` SSH host + `wp` are reachable from the DEPLOYED runtime; if not, downgrade Step 3 to "emit the article HTML to `~/.cache/pharmia-seo/` and queue under Needs approval" rather than failing the run.
- **n8n manual `formTrigger` not ported (deliberate)** — the n8n dispatcher had a second entry-point: an on-demand "write an article on this topic now" form (Topic / Keywords / Content / Sources) feeding a one-off straight into drafting. This scheduled batch routine intentionally omits it — invoke the `content` agent directly for ad-hoc one-off pieces.
