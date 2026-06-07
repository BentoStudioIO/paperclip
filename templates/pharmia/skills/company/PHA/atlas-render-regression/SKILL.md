---
name: "atlas-render-regression"
description: "Codified pitfall catalog + repro harness for Atlas's markdown / json-render rendering pipeline (mermaid, KaTeX, cite/source/act tags, spec fences, tables). Use when an Atlas answer renders wrong — broken diagram, escaped tag, mangled math, cramped table, uppercase leakage — or before fixing any render bug."
slug: "atlas-render-regression"
metadata:
  paperclip:
    slug: "atlas-render-regression"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-render-regression"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-render-regression"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-render-regression"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/atlas-render-regression"
---

# Atlas Render Regression — Pitfall Catalog & Repro Harness

Atlas streams **model-emitted markdown + custom HTML-ish tags** through a
Streamdown pipeline. The model is unreliable: it doubles brackets, drops closes,
mid-stream-truncates tags, emits unquoted mermaid labels, and writes fr-CA prose
that collides with markdown grammar. Almost every "Atlas rendered garbage" bug is
ONE of the classes below — match the symptom first, write a failing repro second,
fix third.

## Where Everything Lives

- **Orchestrator:** `apps/web/src/components/atlas/AtlasMarkdown.tsx`
  (`CustomMarkdownRenderer` → text menders → `ProseMarkdown` → `<Streamdown>`).
  The mender pipe order is load-bearing (`AtlasMarkdown.tsx:327-333`):
  `tightenMathDecimals(escapeCurrencyDollars(escapeCitePipes(stripStraySourcesClose(collapseDoubledSourceOpens(markdown)))))`.
- **web-next copy:** `apps/web-next/src/components/atlas/AtlasMarkdown.tsx` — a
  PARTIAL duplicate (the math/mermaid/sanitize helper files are NOT mirrored
  there). Any fix to a shared mender must be applied to BOTH files; they drift.
- **Sanitize schema (SSOT):** `apps/web/src/components/atlas/atlasSanitizeSchema.ts`
  — adds the custom tags (`cite`, `pharmia-act`, `pharmia-source`, `rx*`,
  `reference-chip`…) + attrs to `hast-util-sanitize`. Imported by the math harness
  so a schema change can't silently break math.
- **Mermaid sanitizer:** `apps/web/src/components/atlas/markdown/sanitizeMermaidSource.ts`.
- **Act-leaf repair (rehype):** `apps/web/src/components/atlas/markdown/acts/rehypeUnwrapActLeaves.ts`.
- **Spec fence (reload render):** `apps/web/src/components/atlas/markdown/AtlasSpecFenceRenderer.tsx`;
  **backend extractor:** `packages/api/src/routes/shared/specFenceExtractor.ts`.
- **Citation chip:** `apps/web/src/components/atlas/markdown/CitationMark.tsx`.

## Pitfall Classes (symptom → cause → fix → file)

### 1. Mermaid parse failure (diagram → error card + "view source")
- **Symptom:** clinical flowchart fails to render; falls back to the error card.
- **Cause:** mermaid v11 rejects UNQUOTED special chars in flowchart labels —
  clinical parens `A[Patient (88yo)]`, `B{Decision (urgent)}`, edge labels
  `A -->|see (note)| B`.
- **Fix:** `sanitizeMermaidSource` quotes label interiors that contain
  `[():&,;<>#"]` (`sanitizeMermaidSource.ts:42`). The transform is, in order:
  **flowchart-only** (non-`graph`/`flowchart` returned unchanged), **line-aware**
  (skips frontmatter, `%%` directives/comments, and STRUCTURAL lines
  `classDef|class|style|linkStyle|click` — `:42-46`; `subgraph` is NOT skipped,
  its `[title]` is a real label), and **shape-aware** via one non-overlapping
  `SHAPE_SCAN` regex (`:117-137`) whose alternation order matters: doubled/compound
  shapes (cylinder `[(…)]`, stadium `([…])`, subroutine `[[…]]`, hexagon `{{…}}`)
  are matched BEFORE single `[…]`/`{…}` so `String.replace` consumes them first and
  a single-delimiter matcher can never re-scan inside them.
- **Known-recurring traps:** (a) cylinder flattening — a single-`[]` matcher
  eating `[(…)]` (fixed `8a061b43`, the non-overlapping single-scan); (b) directive
  lines like `%%{init: {"theme":"base"}}%%` getting rewritten (fixed `5360647f`,
  line-aware skip). **Deliberately UNHANDLED** (degrade to error card, NOT
  corrupted): round `A(Start (now))`, double-circle `A(((…)))`, asymmetric
  `A>Flag]` — quoting round `(…)` collides with shape grammar.
- **Repro:** `tooling/mermaid-sanitizer.test.mjs` — runs the REAL `mermaid.parse()`
  (RED: raw fails; GREEN: sanitized parses).

### 2. KaTeX / math (two recent fr-CA fixes)
The math plugin runs `singleDollarTextMath: true` (`AtlasMarkdown.tsx:289`), so any
two `$` in a message pair as inline math. Two French-locale collisions:
- **Currency `$` collision** (`769dde68`): fr-CA prices `2,45 $ … 73,50 $` (RAMQ
  cost answers) pair up; everything between them — incl. a `</cite>` boundary and
  French prose — renders as italic math. **Fix:** `escapeCurrencyDollars`
  (`AtlasMarkdown.tsx:210-213`) escapes a `$` preceded by digit+whitespace
  (`/(\d[\d.,   ]*[ \t  ])\$/g → \$`). Genuine math never has
  whitespace before its closing `$`. **Known gap:** no-space `50$` is left
  (indistinguishable from a math close `12$`).
- **fr-CA decimal comma tightening** (`e88516c8`): in math mode KaTeX treats a
  bare `,` as punctuation and adds a trailing space → `0,1` renders as ugly
  `0, 1`. **Fix:** `tightenMathDecimals` (`AtlasMarkdown.tsx:227-236`) rewrites a
  digit-comma-digit INSIDE `$…$`/`$$…$$` spans to `{,}` (ordinary atom). Scoped to
  math spans only — `{,}` in prose would render literal braces. Runs AFTER
  `escapeCurrencyDollars` so currency `$` are already `\$`.
- **Schema survival contract:** KaTeX runs AFTER sanitize, so its output is never
  sanitized; sanitize only sees the `language-math` placeholder, which the default
  schema's `/^language-./` allows. NO math-specific schema entry is needed — do not
  add one (verified inert). See `atlasSanitizeSchema.ts:3-22`.
- **mhchem:** `\ce{}` needs the side-effect import
  `katex/dist/contrib/mhchem.mjs` (`AtlasMarkdown.tsx:7`) or it red-errors.
- **Repro:** `tooling/atlas-math.test.mjs` — full remark-math → rehype-katex
  pipeline with the REAL sanitize schema; covers block/inline/mhchem + both fr-CA
  fixes + a parity guard that the shipped regexes haven't drifted from the test
  replicas.

### 3. `<cite>` / `<pharmia-source>` / `<pharmia-act>` tag coherence (the unrendered/escaped-tag class)
The model emits custom tags as raw text; they only become chips/cards if they
parse as elements. Failure mode = the tag leaks as literal text or a chip is
truncated. All menders run in BOTH streaming AND static (reload) renders because
the malformed text is PERSISTED in the message.
- **Doubled `<<`** (`cd69bcef`, Kimi-K2.6): `<<pharmia-source>` → parser treats it
  as text + unknown element, chip never mounts. **Fix:** `collapseDoubledSourceOpens`
  (`AtlasMarkdown.tsx:171-174`) collapses `<{2,}` before a `pharmia-source(s)` tag.
- **Stray container close** (`bd11dc48`): a `</pharmia-sources>` emitted mid-title
  closes the container early, truncating the chip and ejecting the rest. **Fix:**
  `stripStraySourcesClose` (`:154-157`) drops a `</pharmia-sources>` that still has
  source markup after it.
- **Pipes inside `<cite>` in a table cell** (`3048ed8c`): `original=` carries
  verbatim source text, and clinical sources are markdown tables, so `original=`
  contains `|`; remark-gfm splits the cell on it and fractures the tag. **Fix:**
  `escapeCitePipes` (`:189-194`) encodes `|`→`&#124;` inside the cite OPENING tag
  (quote-aware so `>` in an attr value doesn't truncate); rehype-raw decodes it
  back so `CitationMark` still gets verbatim `original`.
- **Incomplete cite during stream:** `mendCiteTags` (`:126-142`, streaming mode
  only) strips an unterminated opening `<cite` or auto-closes a dangling
  `</cite>` so partial HTML doesn't flash as raw text.
- **Tag must be in BOTH the sanitize allow-list AND the component map** or it
  silently renders as a bare element: `markdownComponents` (`AtlasMarkdown.tsx:85-99`)
  ↔ `sanitizeSchema.tagNames` (`atlasSanitizeSchema.ts:26-41`). Adding a tag in one
  but not the other is a recurring footgun.

### 4. Uppercase / style leakage (act tree mis-nest)
- **Symptom:** "2nd act summary renders bold ALL-CAPS / oversized mid-stream, fixes
  itself on completion."
- **Cause** (`e30a7f2a`): an unclosed text-leaf act tag (e.g. `<act-condition>`
  with no `</act-condition>`) makes parse5 nest every following sibling (summary,
  rx rows) INSIDE it until `</pharmia-act>` force-closes — and `<act-condition>`
  carries `uppercase` + `font-semibold` + `tracking-wide`, all INHERITED CSS, so
  the swallowed nodes render bold all-caps.
- **Fix:** `rehypeUnwrapActLeaves` (`rehypeUnwrapActLeaves.ts`) hoists any act-tag
  element wrongly nested inside a `LEAF_ACT_TAGS` node back to sibling position;
  index-based loop repairs deeper mis-nests one level/pass. `<cite>` and non-act
  children are deliberately NOT hoisted. Runs last in `rehypePlugins`
  (`AtlasMarkdown.tsx:101-114`), in streaming AND static.
- **Repro:** `apps/web/src/components/atlas/markdown/acts/rehypeUnwrapActLeaves.test.tsx`.

### 5. Spec fence (json-render) streaming
- `spec` fences carry json-render JSONL. Backend extraction:
  `packages/api/src/routes/shared/specFenceExtractor.ts` — accepts **3+ backtick**
  fences (`1db03131`) because Gemini occasionally over-fences. Reload render:
  `AtlasSpecFenceRenderer.tsx` replays `parseSpecStreamLine` → `applySpecPatch`
  and `dedupeStateArrays` the state before mounting the `Renderer`.
- `sources` fences are split out client-side by `splitSourcesFences`
  (`AtlasMarkdown.tsx:238-275`), which also handles the bare ` ``` ` + `{"title":`
  form and an INCOMPLETE (mid-stream) fence (`sourcesIncomplete`).
- For the json-render catalog / compiler API itself, defer to the
  `json-render-core` / `json-render-react` skills — do NOT restate it here.

### 6. Table sizing / cramping
- Wide chat tables overflow the bubble. **Do NOT wrap in a Radix `ScrollArea`**
  (tried `14ff309b`, reverted) — the fix is pure CSS horizontal scroll
  (`83c8a595`): `apps/web/src/index.css` table rules + `controls={{ table, code }}`
  (`AtlasMarkdown.tsx:291-294`). Symptom of regression: table either clips or
  forces a nested scrollbar.

## How To Reproduce A Render Bug (write the failing repro FIRST)
1. **Get the raw persisted text**, not a screenshot — that text is the input.
   From a thread: `threads <admin-or-share-url> --raw` (or `--tools` for tool
   parts) and copy the assistant message text VERBATIM (the doubled `<<`, the
   stray close, the unquoted mermaid label live in there).
2. **Pick the harness for the layer:**
   - math/KaTeX/currency/decimal → add a case to `tooling/atlas-math.test.mjs`
     (runs the real remark-math→rehype-katex pipeline + real sanitize schema).
   - mermaid → `tooling/mermaid-sanitizer.test.mjs` (runs the real
     `mermaid.parse()` — RED on raw, GREEN on sanitized).
   - act mis-nest / uppercase → `rehypeUnwrapActLeaves.test.tsx`.
   - cite/source menders → assert the mender's string transform directly (they
     are pure functions in `AtlasMarkdown.tsx`); mirror the parity-guard pattern
     the math harness uses so a `.mjs` replica can't drift from the shipped regex.
3. **Run node harnesses with node 24** (type-stripping imports the real `.ts`),
   from repo root so it resolves root `node_modules`:
   `source ~/.nvm/nvm.sh && nvm use 24 && node tooling/atlas-math.test.mjs`
   (same for `tooling/mermaid-sanitizer.test.mjs`).
4. **Confirm RED** (reproduces the garbage) → write the minimal mender/sanitizer
   rule → **confirm GREEN** + the existing cases stay green (no regression).
5. **Mender invariants:** keep the menders pure string transforms, idempotent,
   and safe in BOTH streaming and static modes (persisted text re-renders on
   reload). Apply shared menders to the web-next copy too.

## Hard Rules
- A render fix without a failing repro in one of the harnesses above does not
  ship. "Looks right in the UI" is not evidence — the model emits a different
  malformation next thread.
- Never add a custom tag to the component map without also adding it to
  `sanitizeSchema` (and vice-versa) — fail-closed: an un-allow-listed tag is
  stripped, an un-mapped tag renders bare.
- Don't reach for a heavier tool (Radix ScrollArea for tables, a schema entry for
  math) when a CSS rule or a pure mender already solved it — both were tried and
  reverted.
