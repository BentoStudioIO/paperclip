---
name: "pharmia-content"
description: "FR-Québec content composition kit for the content agent: lifted MIT marketing frameworks (positioning, ICP/PVP, SB7, copywriting, stickiness, product-led-SEO) as STRUCTURE-only references, bound to Pharmia's voice contract and §0-§10 workflow."
user-invocable: true
---

# pharmia-content

The framework kit the **content** agent composes from. The English frameworks below are **structure only** —
the words are authored natively in **québécois professional French** (§0 voice contract in the agent file).
All references are lifted from MIT-licensed skill packs; notices retained in `references/`.

## Reference index (in `references/`)
> Only the top-level methodology files are bundled; the deep-dive `patterns/`/`-playbook.md` sub-links inside them are not included.

- **obviously-awesome.md** + **positioning-canvas.md** — April Dunford positioning. Fills §1 (the immutable
  positioning canvas: category, competitive alternatives, unique attributes, value, best-fit customer).
- **one-page-marketing.md** — Allan Dib. ICP + PVP (perceived value proposition). Fills §2 (owner-operator ICP).
- **storybrand-messaging.md** — Donald Miller SB7. Fills §5 (pharmacist = hero, Pharmia = guide; 3-level
  problem; concrete villain; plan; CTA; stakes).
- **copywriting.md** — CRO copywriting (PAS / AIDA, proof hierarchy). Fills §6 (PAS/AIDA + proof hierarchy).
- **made-to-stick.md** + **contagious.md** — Heath SUCCESs + Berger STEPPS. Stickiness/shareability pass on
  any artifact before §9 self-grade.
- **product-led-seo.md** — Eli Schwartz. Decide IF an SEO play fits at all. Fills §3 (the SEO-fit gate —
  may REJECT SEO → route to founder LinkedIn). This is a CONTENT agent, not an SEO agent: this is the gate
  for *whether* to build search pages, not a mandate to.

## How the agent uses them (binding)
1. §1 positioning → read the canvas already committed in `growth-ssot.md`; if a topic conflicts, flag
   growth-lead. Use obviously-awesome only to *audit* consistency, never to silently re-position per piece.
2. §3 intake → for each market-intel topic, run the Product-Led SEO fit gate (product-led-seo.md). No real
   search demand for the owner-operator audience → **REJECT SEO, route to founder LinkedIn**.
3. §5 long-form → SB7 (storybrand). §6 short-form → PAS/AIDA + proof hierarchy (copywriting).
4. Stickiness pass → SUCCESs / STEPPS before grading.
5. §9 → self-grade on the relevant rubric (each reference has a 0-10 rubric). **Block publish < 8/10.**

## Voice (do not lose across translation)
- Author in québécois French; frameworks are scaffolding. Banned anglo-hype words listed in the agent §0.
- Two distribution voices, ONE positioning: blog (posé, pédagogique) vs founder LinkedIn (direct, je).
- Clinical/regulatory claims → route to **quebec-legal** (verbatim source) BEFORE writing around them.

## Publish (human-approved only)
WordPress via `wp` over `ssh momo`: SCP HTML → `wp post update <ID> /tmp/file.html` (positional arg, never
`--post_content`, never pipe HTML through shell) → touch `post_modified` to trigger Next.js ISR. Draft by
default; the human approves every publish.
