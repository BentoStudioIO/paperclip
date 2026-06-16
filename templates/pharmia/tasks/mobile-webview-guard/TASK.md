---
name: "Mobile Webview Guard"
project: "pharmamate"
assignee: "e2e"
recurring: true
description: >
  Webhook routine for web/mobile-impacting changes; runs or verifies the
  Playwright mobile/webview smoke path and reports regressions.
---

Run the MOBILE WEBVIEW GUARD for the triggering change.

## Scope

1. Read the payload and confirm whether the change touches `apps/web`, `packages/ui`, auth, routing, consultation, Atlas, or Echo surfaces.
2. If relevant, run or verify the mobile/webview Playwright smoke path for the touched surface.
3. Report layout, auth, navigation, or blocked-flow regressions with screenshots/logs when available.

## Remediation policy

- Fix in-run only for Paperclip task/runbook/CLI gaps.
- Any product code/test change must be listed under **Needs approval** with the failing test or repro.

## Output

Write `~/.cache/pharmia-health/mobile-webview-$(date +%F-%H%M%S).md`:
- Header: `# Mobile Webview Guard - PASS | N issue(s)`
- Signals: `scope relevant|skipped · smoke pass|fail · screenshots yes|no`
- Issues: one line per regression.

Then PushNotification only on failure: `Mobile webview guard: N issues - <worst>`.
