---
name: "Daily alert-health"
assignee: "platform-observer"
recurring: true
description: >
  Grafana/Prometheus fired-vs-expected + poller-cursor drops / NoData, with grouped
  root-cause analysis + concrete rules.yaml action items routed through the
  alert-rule-change-validator skill.
---

Run the DAILY ALERT HEALTH CHECK now, autonomously. Use the alert-rule-change-validator skill and the pharmia-grafana-alerting knowledge.

## Steps (last 24h on canary)

1. Verify Grafana/Prometheus alerts fired vs expected (use `prom` for alerts + rule eval, `loki canary errors --since 24h` for spikes).
2. Check for poller-cursor drops and NoData on pharmia-api alerts — remember pharmia-api is OTel-push so it has NO `up` series, and OTel metric renames silently NoData alerts.
3. Flag any alert rule that is firing-but-shouldn't or silent-but-should. Be concise and cite the rule/metric.

## For every anomaly

Investigate the ROOT CAUSE — identify the exact rule/metric/recording-rule and whether it is an OTel metric rename, a threshold misfit, a missing/renamed series, provisioning drift (Grafana API edits silently revert the file SSOT in `tooling/grafana/provisioning/alerting/rules.yaml`), or a genuine incident. GROUP findings that share one root cause. For each group propose a CONCRETE action item: the precise edit to `rules.yaml` + the fix + how to validate via `render-alerting.sh` + `promtool`, routed through the alert-rule-change-validator skill. Cheaply validate when you can (`promtool check rules`, or confirm the metric series actually exists).

## Remediation policy

- **Proactive — fix in-run, no approval (docs + tooling ONLY):** CLI scripts in `~/.local/bin` (`prom`/`loki`/`grr` gaps), Grafana dashboards-as-code via `grr`, runbook/doc notes. Fix at the source, verify, list under **Remediated**.
- **Ask first — propose, do NOT ship (anything in the Pharmia repo):** `tooling/grafana/provisioning/alerting/rules.yaml` and any other `PharmaMate` change. Back it with `render-alerting.sh` + `promtool check rules`, route through the alert-rule-change-validator skill, list under **Needs approval**, and stop. NEVER push a Pharmia branch or open a PR from this task.

## Output — terse, one line per item (no prose paragraphs; omit empty sections)

Write `~/.cache/pharmia-health/alert-$(date +%F).md` in this exact shape:
- **Header:** `# Alert Health <date> — <GREEN | N issue(s)>`
- **Two one-liners:** `Alerts:` firing-as-expected · firing-but-shouldn't · silent-but-should · NoData — each a count. `Signals:` poller-cursor `ok|drop` · OTel-rename `none|<metric>`.
- **`## Issues`** (omit if none) — one bullet each: `[rule/metric] <symptom> — RC <root cause: rename|threshold|missing series|provisioning drift|incident>. → REMEDIATED <cli/dashboard> | ASK rules.yaml: <edit>`
- **`## Remediated`** (CLI/dashboard fixed this run) — one bullet each: `<cli|dashboard>: <what> (verified <how>)`
- **`## Needs approval`** (rules.yaml / Pharmia repo — proposed, not shipped) — one bullet each: `<rule>: <edit> — validate render-alerting.sh + promtool`

Then PushNotification, one line: `Alert <date>: GREEN` — or `Alert <date>: N issues, k remediated, j need approval — <worst one-liner>`.
