---
name: "Weekly Authz Regression Audit"
project: "pharmamate"
assignee: "security-agent"
recurring: true
description: >
  Weekly authz regression audit ensuring routers declare tenant/resource policy
  and recent backend changes did not bypass centralized authorization.
---

Run the WEEKLY AUTHZ REGRESSION AUDIT now.

## Scope

1. Review backend changes from the last 7 days that touch routers, services, tenant resolution, memberships, or resource access.
2. Verify each changed route declares or reuses the correct centralized authorization policy.
3. Flag inline policy drift, cross-tenant lookup risk, and missing negative tests.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including `PharmaMate`, Paperclip task/skill SSOT, CLI wrappers, tests, prompts, deploys, or live config — must be listed under **Needs approval** with the exact failing test or repro to add. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/authz-$(date +%F).md`:
- Header: `# Authz Regression Audit <date> - GREEN | N issue(s)`
- Signals: `routes changed N · policy gaps N · tests gaps N`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed code/test fix.

Then PushNotification: `Authz <date>: GREEN` or `Authz <date>: N issues - <worst>`.
