---
name: "lead-scouting"
description: "OPQ ⨯ Twenty ⨯ online-signal ⨯ PLG-signup method for building the ranked who-to-DM list, plus the DM-list output format. Founder-led: the human sends; lead-scout ranks + writes opportunities to Twenty."
user-invocable: true
---

# lead-scouting

Method behind **WHO TO DM**. Cross four sources into one ranked list; write qualified opportunities to
Twenty; the **human sends the DMs**.

## Source 1 — OPQ repertoire (the ICP universe)
```
curl -s 'https://www.opq.org/wp-content/uploads/pharmacist-search/pharmacists_index.json' \
  | jq '[.[] | select(.isStudent==false)]'
```
JSON array: `id, fullName, licenseNumber, studentLicenseNumber, city, isStudent`. Filter to licensed
non-students. OPQ does NOT flag ownership — infer **pharmacien-propriétaire** by cross-referencing web /
LinkedIn / known pharmacy names (the repertoire is the universe, ownership is the qualifier).

## Source 2 — Twenty (dedupe + write)
- Discover schema: `twenty objects`, `twenty fields person`, `twenty fields company`.
- Dedupe: Twenty `name` is a COMPOSITE (`{firstName,lastName}`), not a flat string —
  `twenty gql '{ people(filter:{name:{lastName:{ilike:"%Tremblay%"}}}) { edges { node { id name { firstName lastName } } } } }'`
  — never DM someone already in an active opportunity.
- Verify license/city against OPQ before writing (avoid wrong-person).

## Source 3 — online-activity signal (best-effort, fragile)
The EXISTING n8n + Browserless pipeline (Bento n8n, `http://browserless:3000/scrape`) reads **public
LinkedIn company pages** without login (works for company pages; **individual profile activity is
login-walled**). Use it to catch when a target pharmacy/owner posts about practice, workload, or AI.
- **jina and camofox CANNOT read LinkedIn** (login wall) — do not attempt.
- Profile-level signals are best-effort: if the pipeline returns nothing, mark the candidate
  `signal: none` — **never fabricate activity**.

## Source 4 — PLG signups (hottest signal)
New public-tenant pharmacists who self-served Atlas this week — they already tried the product:
```sql
-- pg canary
SELECT id, name, email, license_number, "createdAt", signup_source
FROM ba_user
WHERE role='user' AND NOT is_anonymous
  AND anon_queries_before_signup > 0
  AND "createdAt" > now() - interval '7 days'
ORDER BY "createdAt" DESC;
```
`ba_user` has **no `city` column** — get the candidate's city by joining the OPQ JSON (Source 1) on
`fullName`/`name`, never from `ba_user`.

## Ranking (why-now beats who)
1. **PLG signup this week** — already in product. Hottest.
2. **Recent relevant LinkedIn activity** — warm, timely hook.
3. **Owner-operator, target city, no prior contact** — cold ICP-fit.

## DM-list output format (to growth-lead)
```
DM LIST — week of <date>   (as-of <ts>)
1. <name> · propriétaire <pharmacy>, <city> · why-now: <signal> · hook: "<one line, FR québécois>"
2. ...
WROTE TO TWENTY: <N opportunities> (ids)
LINKEDIN PIPELINE: <ran ok | empty | unavailable>
```
Hook references the signal (their post / their signup), never generic. Owner-operator contact =
**opportunity** in Twenty (per CRM rules: rencontre/contact propriétaire = opportunity).

## Discipline
- `twenty gql` mutations only — never hand-crafted UUIDs (server generates).
- No signal → not on the list. Honesty on LinkedIn status, always.
- Rank + write to CRM; **never send a DM** — that's the human (founder-led sales).
