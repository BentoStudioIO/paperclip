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

## Output

Write the full findings to `~/.cache/pharmia-health/alert-$(date +%F).md` with a ROOT-CAUSE ANALYSIS + ACTION ITEMS section (say "all healthy" if nothing found), then call the PushNotification tool with a one-line summary (or "Alert health: all green").
