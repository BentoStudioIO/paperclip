---
name: "Daily alert-health"
project: "pharmamate"
assignee: "devops"
recurring: true
description: >
  Host detector for Grafana/Prometheus fired-vs-expected, silent-failure signals
  (poller-cursor / NoData), and structural coverage gaps. Collect evidence,
  write the health report, and route confirmed follow-ups without blocking the
  recurring detector issue.
---

Run the DAILY ALERT HEALTH CHECK now, autonomously. You are the host detector:
collect the CLI-backed evidence first, then write the health report. Use the
alert-rule-change-validator skill and the pharmia-grafana-alerting knowledge.

## Steps (last 24h on canary)

1. **Fired-vs-expected.** Verify every Grafana/Prometheus state change (`prom` for alerts + rule eval, `loki canary errors --since 24h` for spikes). Classify each: firing-as-expected · firing-but-shouldn't · silent-but-should.
2. **Silent-failure signals.** Confirm the signals that fail quietly are healthy — verify at the SOURCE, never from absence of an error: poller-cursor actually advancing (read the cursor/row, not the lack of a log), and each NoData alert backed by a live series. pharmia-api is OTel-push (no `up` series); an OTel metric rename silently turns an alert to NoData.
3. **Coverage (structural).** Beyond what fired, ask what *can't* fire: a critical or customer-facing path with no signal ops can alert on (no metric, no log, no rule), an alert whose backing query/series is dead, or a failure class no rule would catch. A real gap is a `silent-but-should` finding even when nothing fired — don't overfit to past examples, reason from the path.

## For every finding

Name the exact rule/metric/series/path and the ROOT CAUSE — one of: OTel rename · threshold misfit · missing/renamed series · provisioning drift (Grafana API edits silently revert the file SSOT `tooling/grafana/provisioning/alerting/rules.yaml`) · coverage gap (signal/alert that should exist but doesn't) · genuine incident. GROUP findings sharing one cause; one concrete action item per group, routed through the validator skill. Validate cheaply before asserting (confirm the series exists; query the source-of-truth, e.g. the DB row, not the absence of a log).

If a finding needs observer/product judgment after evidence collection, create a
child issue for Platform Observer with the report and raw evidence pointers. Do
not block this recurring detector issue on that follow-up; mark this issue done
after the report is posted and any follow-up issues are created.

## Remediation policy

- **Proactive — fix in-run, no approval (docs + tooling ONLY):** CLI scripts in `~/.local/bin` (`prom`/`loki`/`grr` gaps), Grafana dashboards-as-code via `grr`, runbook/memory notes. Fix at source, verify, list under **Remediated**.
- **Ask first — propose, do NOT ship (any `PharmaMate` change):** `rules.yaml`, relay/app code, anything in the repo. Back it with the relevant validation (`render-alerting.sh` + `promtool check rules` for alert rules), route through the validator skill, list under **Needs approval**, stop. NEVER push a Pharmia branch or open a PR from this task.

## Output — terse, bullets only, omit empty sections

Write `~/.cache/pharmia-health/alert-$(date +%F).md` in this exact shape:

- **Header:** `# Alert Health <date> — <GREEN | N issue(s)>`
- **Signals (ONE line):** `firing-as-expected N · firing-but-shouldn't N · silent-but-should N · NoData N (healthy|…) · poller-cursor ok|drop · OTel-rename none|<metric> · coverage ok|gap`
- **`## Issues`** — `[rule/metric/path] <symptom> — RC <root cause>. → REMEDIATED <what> | ASK <file>: <edit>`
- **`## Remediated`** — `<cli|dashboard|note>: <what> (verified <how>)`
- **`## Needs approval`** — `<rule/file>: <edit> — validate <how>`
- **`## Context`** (optional, ≤3 bullets, one line each, no prose) — genuine/CTO-accepted firings worth noting.

Then PushNotification, one line: `Alert <date>: GREEN` — or `Alert <date>: N issues, k remediated, j need approval — <worst one-liner>`.
