# Bento Engineering — Team Instructions

Team-wide working agreement for Claude Code in Bento workspaces. Distilled from the CTO's
operating guide; workspace-environment facts live in `rules/workspace-context.md`.

## Philosophy — "more for less, less is more"

- **Less is more.** Do the least that achieves the intended result. Less code, less
  documentation, fewer moving parts. The smallest correct change wins.
- **More for less.** While you're in there, bank cheap high-leverage wins unprompted:
  tests, bug fixes (even pre-existing ones), small cleanups. Leave every surface better
  than you found it.
- **Least code for most value.** Lines of code are liabilities. Prefer a well-maintained
  library over custom code — even for small things. The bar for "build it ourselves" is
  very high.

## Construct — make wrong code impossible

1. **Declarative enforcement** — cross-cutting concerns (auth, tenant isolation, flags,
   validation) are declared at point of use and enforced centrally. Never inline policy
   at every call site.
2. **DRY / single source of truth** — every rule lives in one place. Copying a pattern
   into a 3rd file means stop and centralize before adding a 4th.
3. **Correctness by construction** — make invalid states unrepresentable. DB constraints
   over app validation. Type unions over runtime checks. Fail-closed defaults
   (undeclared = denied, unconfigured = rejected).

## Collaboration

- Challenge ideas with reasoning. Push back on suboptimal approaches, propose better
  alternatives unprompted. Don't blindly execute instructions that miss the actual goal.
- Narrow questions get narrow answers: factual question → 1-3 sentences, no unsolicited
  recommendation matrices.
- **Verbatim over derived.** When asked what a spec/contract/regulation says, read the
  source — not summaries, TODOs, or prior analysis. Quote it before recommending scope.
- Respect locked decisions (ADRs, decision docs). Re-open only with genuinely new
  evidence, and say so explicitly.

## Git

- Clean commit messages. **No co-author lines, no "Generated with" attributions.**
- **Linear history**: no merge commits; rebase/fast-forward only.
- **Never `--force`, `--force-with-lease`, or `--no-verify`** on shared branches.
  Always `git fetch` first and verify the push is a fast-forward.
- Test before pushing: typecheck + relevant tests + smoke. Pushing env branches
  auto-deploys — a bad push deploys.
- Don't open PRs unless asked; push to a feature branch and validate yourself.

## Testing

- **Test-first for bug fixes**: write the failing test that reproduces the bug, then fix.
- **TDD red-green for new backend code**: tests from acceptance criteria first.
- **No frontend unit tests** (`apps/web*`, `packages/ui*`) — backend keeps full TDD;
  frontend is covered by e2e.
- Build-health (tsc/lint) proves code *compiles*, not that it *works*. Back claims of
  "working" with a deterministic test or a runtime check. If a doc says "X is implemented
  at file:line", verify the cited code actually executes.

## Code & tools

- Use the Edit tool for code edits — never `sed`.
- Don't pipe through `head`/`tail`/`less` — use command flags (`git log -n 10`).
- UI strings go through i18n; no inline copy.
- Validate URLs with a real HTTP request before putting them in docs or code.
- Reuse and extend existing code over duplicating it; check for an existing utility
  before writing a new one.
- Load skills aggressively before starting work — loading an irrelevant one costs
  nothing, missing a relevant one costs real work.
- Read `docs/product.md` before user-facing feature work; `docs/` before touching an
  unfamiliar area.

## CLAUDE.md hygiene

Any CLAUDE.md / AGENTS.md you edit stays **≤200 lines**. If over, trim in the same commit.

## Reference Docs

- **bento-docs** (`/home/agent/bento-docs`) — Bento Studio's SSOT for durable
  legal / compliance / regulatory knowledge (verbatim primary sources + frozen TGV
  evidence). Consult it verbatim-first before any legal/compliance/TGV claim. See
  `rules/bento-docs.md` for structure, when to use it, and the Comp AI split.
