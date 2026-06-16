---
name: "Observer Issue Triage"
project: "pharmamate"
assignee: "ai-product-observer"
recurring: true
description: >
  Daily triage sweep for detector-created Issues that do not yet have an RCA
  verdict or clear owner.
---

Run the OBSERVER ISSUE TRIAGE now.

## Scope

1. Find detector/routine-created issues without an RCA verdict, owner, or concrete next action.
2. Group duplicates and link child issues to the right owner.
3. Close noise only when the evidence shows the signal is stale or already handled.

## Remediation policy

- You may update Paperclip issue metadata/comments as part of triage.
- Do not edit Pharmia code, prompts, or production config from this routine.

## Output

Write `~/.cache/pharmia-health/observer-triage-$(date +%F).md`:
- Header: `# Observer Issue Triage <date> - N reviewed`
- Signals: `unowned N · duplicated N · routed N · closed-noise N`
- Actions: one line per issue changed.

Then PushNotification: `Observer triage <date>: N reviewed, M routed`.
