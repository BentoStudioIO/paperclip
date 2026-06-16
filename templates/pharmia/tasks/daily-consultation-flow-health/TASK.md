---
name: "Daily Consultation Flow Health"
project: "pharmamate"
assignee: "clinical-flow-observer"
recurring: true
description: >
  Daily clinical-flow detector for consultation form dead-ends, incomplete
  patient journeys, and review handoff failures.
---

Run the DAILY CONSULTATION FLOW HEALTH CHECK now, against canary.

## Scope

1. Find consultations created or touched in the last 24h where the patient flow stalled before pharmacist review.
2. Check for form states that never become complete, confirmation dead-ends, and failed review handoffs.
3. Group findings by root cause: form validation, patient-agent routing, persistence, notification, or UI state.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local health-report files.
- For any code/config/tooling change — including `PharmaMate`, Paperclip task/skill SSOT, CLI wrappers, prompts, evals, schemas, deploys, or live config — report the exact file/change and validation path under **Needs approval**. Do not push a branch, open a PR, deploy, or mutate live config.

## Output

Write `~/.cache/pharmia-health/consultation-flow-$(date +%F).md`:
- Header: `# Consultation Flow Health <date> - GREEN | N issue(s)`
- Signals: `created N · completed N · stalled N · handoff failures N`
- Issues: one line per grouped root cause.
- Needs approval: one line per proposed product fix.

Then PushNotification: `Consultation flow <date>: GREEN` or `Consultation flow <date>: N issues - <worst>`.
