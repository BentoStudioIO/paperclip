---
name: "Weekly Consent Compliance Drift"
project: "pharmamate"
assignee: "clinical-flow-observer"
recurring: true
description: >
  Weekly consent/compliance drift detector for consent re-prompt coverage,
  audit writes, and clinical-flow privacy guardrails.
---

Run the WEEKLY CONSENT COMPLIANCE DRIFT CHECK now.

## Scope

1. Verify consent prompts and re-prompts still appear on the flows where policy requires them.
2. Confirm consent decisions and sensitive accesses write audit evidence.
3. Flag stale copy, missing audit rows, and flow bypasses.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including `PharmaMate`, Paperclip task/skill SSOT, CLI wrappers, consent, audit, prompt, legal copy, deploys, or live config — must be listed under **Needs approval** with validation steps. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/consent-$(date +%F).md`:
- Header: `# Consent Compliance Drift <date> - GREEN | N issue(s)`
- Signals: `prompts ok|gap · audit ok|gap · bypass none|N`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed fix.

Then PushNotification: `Consent <date>: GREEN` or `Consent <date>: N issues - <worst>`.
