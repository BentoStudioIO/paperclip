---
name: "Weekly Autumn Billing Drift"
project: "pharmamate"
assignee: "security-agent"
recurring: true
description: >
  Weekly billing drift detector comparing deployed Autumn/customer state against
  Pharmia billing config and quota expectations.
---

Run the WEEKLY AUTUMN BILLING DRIFT CHECK now.

## Scope

1. Compare deployed Autumn products, entitlements, and checkout behavior against the Pharmia billing config.
2. Check recent signup and quota events for stale billing state or delayed refresh.
3. Flag mismatches that could overgrant, undergrant, or confuse pharmacists.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including Paperclip task/skill SSOT, CLI wrappers, Autumn config pushes, Pharmia code changes, deploys, live config, or production billing mutations — must be listed under **Needs approval** with validation steps. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/autumn-$(date +%F).md`:
- Header: `# Autumn Billing Drift <date> - GREEN | N issue(s)`
- Signals: `products ok|drift · entitlements ok|drift · quota refresh ok|lag`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed fix.

Then PushNotification: `Autumn <date>: GREEN` or `Autumn <date>: N issues - <worst>`.
