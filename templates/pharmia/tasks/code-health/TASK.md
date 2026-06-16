---
name: "Code Health"
project: "pharmamate"
assignee: "code-health"
recurring: true
description: >
  Weekly diff-scoped code-health — coverage drops / new-code-at-0%, i18n gaps on
  changed files, dashboard-config drift, and ready-now dead-code. Scoped to recent
  change so it stays signal, not a daily repeat of slow-moving findings.
---

Run the WEEKLY CODE-HEALTH CHECK now, autonomously, on `PharmaMate`. Use the deletion-bias, testing-intelligence, and duplication-detect skills. Read `~/.claude/rules/environment-bindings.md` for tools.

**Scope to the week's change** — `git -C ~/Documents/PharmaMate log --since='7 days ago' --oneline` and `git diff --stat <7d-ago-sha>..HEAD`. The four dimensions below are kept BECAUSE they move week-to-week and tie to a diff. The standing architectural scans (DRY/coupling/blast-radius/extensibility/construction-defects) are DROPPED from this routine — they are slow-moving and repeat as noise at frequency; run them ON-DEMAND only (when explicitly asked or via the `nightly` skill), not on a recurring cadence.

## Steps (scoped to the last 7 days of commits)

1. **Coverage on changed code** — run `cd packages/api && npm run test:once` (backend only; no frontend unit tests per repo rule). Flag new/changed `packages/api/**` source landing at 0% coverage, any >10% coverage drop on a touched module, and new tests that are flaky or inflate suite duration. Cite file + the missing case.
2. **i18n gaps on changed files** — on files touched this week under `apps/web*`/`packages/ui*`, grep for hardcoded user-facing strings bypassing `t()` (raw JSX text, `label="…"`/`placeholder="…"` with human copy), keys present in one locale but missing in another, and orphaned keys added this week but never referenced. Cite file:line + the string.
3. **Dashboard-config drift** — diff dashboard-as-code (`tooling/grafana/**`, `grr`) and alert `rules.yaml` against reality: services/metrics referenced that no longer exist (esp. OTel metric renames that silently NoData — cross-check with `prom <env>` that the series exists). Cite the dashboard/rule + the dead metric.
4. **Ready-now dead-code** — code deletable RIGHT NOW: unused exports/imports/deps introduced or orphaned this week, compatibility shims for a now-completed migration, permanently on/off feature flags, defensive code for impossible states. Prefer deletion; a util used in only 1–2 places is premature abstraction — inline it. Cite file + line count removable.

## For every finding

Score by `severity × confidence`; surface only high-confidence. GROUP findings sharing one root cause. For each, name the owner file + the fix + how to validate (a failing→green test, a re-run of `test:once`, or `prom`/`promtool` for dashboard drift). Auto-fix only the safe class below.

## Remediation policy

- **Fix in-run, no approval (docs ONLY):** local report files and non-code runbook notes. List under **Remediated**.
- **Ask first — propose, do NOT ship (code/config/tooling):** any repo, source, test, i18n, alert `rules.yaml`, dashboard-as-code, CLI wrapper, Paperclip task/skill SSOT, prompt/model, deploy, or live-config change. Back with a failing→green repro; route alert edits through alert-rule-change-validator, model/prompt edits through model-config-gate. List under **Needs approval** and stop. NEVER push a branch, open a PR, deploy, or mutate live config from this task.

## Output — terse, one line per item (no prose paragraphs; omit empty sections)

Write `~/.cache/pharmia-health/code-$(date +%F).md` in this exact shape:
- **Header:** `# Code Health <date> — <GREEN | N issue(s)> (<N> commits, week scope)`
- **One-liner:** `Signals:` coverage · i18n · dashboard · dead-code — each `ok` or a count.
- **`## Issues`** (omit if none) — one bullet each: `[coverage|i18n|dashboard|dead-code] <symptom @ file:line> — RC <root cause>. → REMEDIATED <what> | ASK <pharmia file>`
- **`## Remediated`** — one bullet each: `<file|dashboard|cli>: <what> (verified <how>)`
- **`## Needs approval`** — one bullet each: `<file>: <fix> — validate <repro/test>`

Then PushNotification, one line: `Code <date>: GREEN` — or `Code <date>: N issues, k remediated, j need approval — <worst one-liner>`.
