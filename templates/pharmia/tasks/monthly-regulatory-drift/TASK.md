---
name: "Monthly Regulatory Drift"
project: "pharmamate"
assignee: "quebec-legal"
recurring: true
description: >
  Monthly Quebec regulatory drift check for TGV/MSSS status, RAMQ infolettres,
  OPQ changes, and privacy compliance deadlines.
---

Run the MONTHLY REGULATORY DRIFT CHECK now.

## Scope

1. Check TGV/MSSS, RAMQ, OPQ, and Quebec privacy/regulatory sources for dated changes since the last run.
2. Quote verbatim source text for any material change before interpreting it.
3. Classify impact: no action, monitor, legal review, pharmacy review, or engineering change.

## Remediation policy

- Fix in-run only for Paperclip legal/task/runbook source-list gaps.
- Any product, legal-policy, pharmacy-content, or code change must be listed under **Needs approval** with source citations.

## Output

Write `~/.cache/pharmia-health/regulatory-$(date +%F).md`:
- Header: `# Regulatory Drift <date> - GREEN | N item(s)`
- Signals: `TGV · RAMQ · OPQ · privacy · SaMD`
- Issues: one line per source-backed change.
- Needs approval: one line per proposed action.

Then PushNotification: `Regulatory <date>: GREEN` or `Regulatory <date>: N items - <worst>`.
