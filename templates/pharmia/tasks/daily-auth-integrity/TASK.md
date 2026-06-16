---
name: "Daily Auth Integrity"
project: "pharmamate"
assignee: "security-agent"
recurring: true
description: >
  Daily auth integrity detector for audit-log coverage, tenant isolation signals,
  and 401/403 spikes that should reach Grafana.
---

Run the DAILY AUTH INTEGRITY CHECK now, against canary.

## Scope

1. Verify auth/audit-log controls still emit expected records for sensitive routes.
2. Check 401/403 and cross-tenant denial signals for the last 24h.
3. Confirm alerting coverage exists for meaningful spikes and silent auth failures.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local health-report files.
- For any code/config/tooling change — including `PharmaMate`, Paperclip task/skill SSOT, CLI wrappers, routers, auth, audit logs, alert rules, deploys, or live config — list the exact file/change and validation under **Needs approval**. Do not push a branch, open a PR, deploy, or mutate live config.

## Output

Write `~/.cache/pharmia-health/auth-$(date +%F).md`:
- Header: `# Auth Integrity <date> - GREEN | N issue(s)`
- Signals: `audit ok|gap · 401/403 normal|spike · tenant checks ok|gap · alerts ok|gap`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed fix.

Then PushNotification: `Auth <date>: GREEN` or `Auth <date>: N issues - <worst>`.
