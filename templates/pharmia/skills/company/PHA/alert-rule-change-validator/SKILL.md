---
name: "alert-rule-change-validator"
description: "Clean-context pre-merge checklist for any diff under tooling/grafana/provisioning/alerting/. Use before committing/pushing a Grafana alert-rule change — verifies render test passes, every rule has a contact point + dedup fingerprint, deletions land in delete-rules.yaml, and no rule depends on a renamed OTel metric. Points at memory pharmia-grafana-alerting for the facts."
slug: "alert-rule-change-validator"
metadata:
  paperclip:
    slug: "alert-rule-change-validator"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/alert-rule-change-validator"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/alert-rule-change-validator"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/alert-rule-change-validator"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/alert-rule-change-validator"
---

# Grafana Alert-Rule Change Validator

Run this WHENEVER a diff touches `tooling/grafana/provisioning/alerting/`
(`rules-*.yaml`, `delete-rules.yaml`, `contact-points.yaml`, `policies.yaml`).
The alerting config is **file-provisioned and is the SSOT** — Grafana API edits
revert on next provision, so a bad rule file silently ships a broken or
never-firing alert. This skill owns ONLY the checklist; the facts (job names,
templating, why API edits revert) live in memory `pharmia-grafana-alerting` —
read it once, don't restate it.

## Gate 1 — Render Test (blocking)
The rule files are templated and rendered by `tooling/grafana/render-alerting.sh`.
Run its test before anything else:
```sh
bash tooling/grafana/render-alerting.test.sh
```
If it fails, STOP — the templated output is malformed and would either fail
provisioning or ship a different rule than the diff suggests. Do not eyeball the
YAML in place of running this.

## Gate 2 — Per-Rule Checklist (every added/changed rule)
- [ ] **Contact point exists.** The rule's notification path resolves to a
  contact point defined in `contact-points.yaml` and routed in `policies.yaml`.
  A rule with no matching route fires into the void.
- [ ] **Dedup fingerprint / unique identity.** The rule has a stable unique
  identity (uid / group+title) so Grafana dedups alert instances instead of
  spawning duplicates or orphaning the old one on rename. Renaming a rule
  without preserving identity = a NEW rule fires and the OLD one is never
  cleaned up (see Gate 3).
- [ ] **Threshold + `for` are sane.** A `for:` that's too short flaps; a missing
  one alerts on a single scrape blip. Confirm the duration matches the metric's
  scrape cadence.
- [ ] **Labels match a route.** Severity / team labels on the rule actually match
  a matcher in `policies.yaml`, or the alert won't reach the right channel.

## Gate 3 — Deletions Must Be Explicit
File-provisioning does NOT delete a rule just because you removed it from a
`rules-*.yaml` file — orphaned rules linger in Grafana. Any removal or rename
MUST also be recorded in:
```
tooling/grafana/provisioning/alerting/delete-rules.yaml
```
(mirror for contact points: `delete-contact-points.yaml`). A rename = a delete of
the old identity + an add of the new one. Verify the deleted rule's identity is
listed there in the SAME diff.

## Gate 4 — OTel Metric-Rename Trap (highest-value check)
The app job `pharmia-api` pushes metrics via OTel and has **no `up` series** —
and an OTel metric rename silently turns its alert to NoData (the rule keeps
provisioning fine, it just never fires again). For every metric/PromQL
expression referenced by a changed rule:
- [ ] Confirm the metric name still exists in the live push:
  ```sh
  prom <env> 'group by (__name__) ({__name__=~"<metric_prefix>.*"})'
  prom <env> '<the rule's exact expr>'   # returns data, not empty
  ```
- [ ] If any instrumentation diff in the SAME change renamed/removed a metric,
  every alert that queries it is now dead — update or delete those rules here.

## Gate 5 — VERDICT
```
VERDICT
- Files changed:  <rules-*.yaml / delete-rules.yaml / contact-points / policies>
- Render test:    PASS | FAIL
- Rules added/changed/deleted: <n / n / n>  (deletions in delete-rules.yaml? yes/no)
- Metric refs verified live: <yes — exprs return data | NoData risk on: …>
- Verdict:        SAFE TO MERGE | BLOCKED (<reason>)
```
Never report SAFE without Gate 1 actually run and Gate 4 actually queried.

## DRY — Owns ONLY The Checklist
Job names, `render-alerting.sh` templating internals, why API edits revert, the
`pharmia-api` no-`up`-series fact, and the OTel-rename mechanism all live in
memory `pharmia-grafana-alerting.md`. Read it for the WHY; this skill is the
pre-merge gate.
