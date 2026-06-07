---
name: "law25-telemetry-review"
description: "Grep + checklist that flags any new analytics / beacon / telemetry event carrying a clinical topic, source domain/URL, patient identifier, or free text — and enforces the closed-enum pattern (sourceCategory, atlasEntryPoint). Use on frontend diffs that add or change a tracked event before merge."
slug: "law25-telemetry-review"
metadata:
  paperclip:
    slug: "law25-telemetry-review"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/law25-telemetry-review"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/law25-telemetry-review"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/law25-telemetry-review"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/law25-telemetry-review"
---

# Law 25 Telemetry Review

Run this on any frontend diff that **adds or changes a tracked event** (analytics,
beacon, session-replay tag, survey trigger, product event). Quebec Law 25 governs
personal/clinical data — a telemetry payload that carries what a pharmacist looked
up, the source host, or any patient identifier is a leak even if the analytics
backend is self-hosted. The rule is **closed enums only**: an event attribute is
either a fixed, reviewed enum or it does not ship.

## The Pattern (correctness by construction)
Two reference implementations define the bar — read them, copy the shape:
- `apps/web/src/components/atlas/atlasEntryPoint.ts` —
  `AtlasEntryPoint = 'atlas_page' | 'suggestion_card' | 'note_picker'`. A closed
  union, documented as "never carries free text". Enriches
  `atlas_question_submitted`.
- `apps/web/src/components/atlas/markdown/sourceCategory.ts` —
  `sourceCategory(url)` collapses ANY source URL to `'gov' | 'pubmed' | 'inesss'
  | 'other'` so a click event is analysable without exposing WHERE the pharmacist
  looked (the host alone can leak the clinical topic). The raw URL never leaves
  the client as telemetry.

The send path is `trackUsertourEvent(code, attributes)`
(`apps/web/src/lib/usertour.ts`) — fire-and-forget, no-ops when unconfigured.
`attributes` is typed `Record<string, string | number | boolean>`; this skill is
about WHAT goes in those values.

## Grep Sweep (run first)
Find every tracked event in the diff and inspect its payload:
```sh
# all event sends + survey/replay tags touched
git diff --unified=0 origin/main -- 'apps/web*/src/**' | rg -n \
  'trackUsertourEvent|usertour\.track|\.track\(|track[A-Z]\w*Event|sendBeacon|navigator\.sendBeacon|openreplay|tracker\.event|identify\('
# any payload value that is NOT a literal / closed-enum variable
```
For each hit, read the object passed as `attributes`.

## Forbidden Payload Values (reject any of these)
- [ ] **Clinical topic / free text** — drug name, condition, symptom, the user's
  question text, a note body, a transcript line. Even a "category" string the
  user typed is free text.
- [ ] **Source domain or URL** — a host, full URL, or slug of a clinical source.
  Must be collapsed via `sourceCategory()` to the 4-bucket enum, never the raw
  link. (A monograph host leaks the drug.)
- [ ] **Patient identifiers** — patient id, name, DOB, MRN, phone, consultation
  id tied to a patient, tenant slug that identifies the pharmacy's patient.
- [ ] **Anything unbounded** — a value whose domain isn't a fixed, enumerated set
  you could write down. If you can't list every possible value, it's not an enum.

## Allowed (closed enums + non-identifying scalars)
- [ ] A documented closed union (like `AtlasEntryPoint`) — finite, reviewed.
- [ ] A coarse bucket from a collapsing function (like `sourceCategory`).
- [ ] Counts / booleans / durations with no identity (e.g. `turnCount`,
  `hadAttachment`, `trigger: 'button' | 'shortcut'`).

## Enforcement Rule
If a new event needs a dimension that isn't yet a closed enum:
1. Define the enum as a TS union next to its event (mirror `atlasEntryPoint.ts`),
   with a comment stating it never carries free text.
2. If it's a URL/topic, write/extend a collapsing function (mirror
   `sourceCategory.ts`) and send the bucket.
3. NEVER widen a value to `string` "for now" — that's the leak.

## Cross-Check
- [ ] Tracking gates on authentication where the SDK requires an identified user
  (surveys only show post-identify) — but identity must be the SDK's anonymous
  id, not PHI (`usertour.ts` init is documented "anonymous — no PII").
- [ ] Session-replay (OpenReplay) tags added in the same diff get the same
  treatment — a replay label is telemetry too.
- [ ] If the change also adds a backend access surface, run
  **`pharmia-authz-checklist`** (its PHI-leak step points back here).

## VERDICT
```
VERDICT
- Events added/changed: <list>
- Payload audit: all closed-enum / non-identifying  |  LEAK: <event>.<attr> = <value>
- New enums/collapsers added where needed: yes/no
- Verdict: SAFE TO MERGE | BLOCKED (<leaking attribute>)
```
Never approve an event whose payload you couldn't fully enumerate.
