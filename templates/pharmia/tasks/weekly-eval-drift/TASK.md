---
name: "Weekly Eval Drift"
project: "pharmamate"
assignee: "ai-product-observer"
recurring: true
description: >
  Weekly eval drift detector for judge deltas, goal-achievement regressions, and
  USD-cost movement versus the latest accepted baseline.
---

Run the WEEKLY EVAL DRIFT CHECK now.

## Scope

1. Compare the latest eval outputs against the last accepted baseline for Atlas, patient chat, and coordinator flows where available.
2. Flag material movement in score, goal achievement, runtime, fallback rate, and estimated cost.
3. Separate real model/product drift from evaluator, fixture, or infrastructure noise.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including Paperclip task/skill SSOT, CLI wrappers, prompt/model/eval changes, deploys, or live config — goes through model-config-gate with before/after evidence and must be listed under **Needs approval**. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/eval-drift-$(date +%F).md`:
- Header: `# Eval Drift <date> - GREEN | N issue(s)`
- Signals: `score delta · goal delta · cost delta · infra noise`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed eval/model/prompt fix.

Then PushNotification: `Eval drift <date>: GREEN` or `Eval drift <date>: N issues - <worst>`.
