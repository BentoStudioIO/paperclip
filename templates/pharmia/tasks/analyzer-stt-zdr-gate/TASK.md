---
name: "Analyzer STT ZDR Gate"
project: "pharmamate"
assignee: "clinical-flow-observer"
recurring: true
description: >
  Webhook routine for Echo analyzer, STT, or phone-config changes; verifies
  relevant benches ran and no ZDR-voiding config was introduced.
---

Run the ANALYZER/STT/ZDR GATE for the triggering change.

## Scope

1. Read the webhook payload and identify touched Echo analyzer, STT, LiveKit, phone-agent, or provider config files.
2. Verify the relevant bench/eval/test evidence exists for the change.
3. Check for ZDR-voiding keys or explicit cache/storage behavior that would breach the privacy boundary.

## Remediation policy

- Fix in-run only for Outline/runbook non-code docs and local report files.
- Any code/config/tooling change — including Paperclip task/skill SSOT, CLI wrappers, deploys, or live config — must be listed under **Needs approval** with the exact validation required. Do not ship it without approval.

## Output

Write `~/.cache/pharmia-health/analyzer-zdr-$(date +%F-%H%M%S).md`:
- Header: `# Analyzer STT ZDR Gate - PASS | BLOCK`
- Signals: `files · benches · ZDR`
- Issues: one line per blocking item.

Then PushNotification only on BLOCK: `Analyzer/STT/ZDR gate BLOCK - <worst>`.
