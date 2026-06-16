---
name: "Weekly Model Ring Review"
project: "pharmamate"
assignee: "ai-product-observer"
recurring: true
description: >
  Weekly Atlas model-ring review for breaker/park/rescue behavior, fallback
  reasons, and provider mix drift.
---

Run the WEEKLY MODEL RING REVIEW now, against canary.

## Scope

1. Use `threads modelmix canary --since 7d` and structured Atlas stream-result logs to measure provider mix, fallback rate, and fallback reasons.
2. Check breaker, park, rescue, timeout, and guard-trip behavior against the intended Atlas ring.
3. Identify any ring drift that needs eval-backed model-config-gate review.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including Paperclip task/skill SSOT, CLI wrappers, model, provider, timeout, routing, prompt, deploy, or live config — must be listed under **Needs approval** with the required eval evidence. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/model-ring-$(date +%F).md`:
- Header: `# Model Ring Review <date> - GREEN | N issue(s)`
- Signals: `provider mix · fallback% · timeout% · guard trips · rescue count`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed model/routing fix.

Then PushNotification: `Model ring <date>: GREEN` or `Model ring <date>: N issues - <worst>`.
