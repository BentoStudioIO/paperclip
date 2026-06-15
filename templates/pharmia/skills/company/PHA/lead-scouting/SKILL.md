---
name: "lead-scouting"
description: "OPQ ⨯ Twenty ⨯ online-signal ⨯ PLG-signup method for building the ranked who-to-DM list, plus the DM-list output format. Founder-led: the human sends; lead-scout ranks + writes opportunities to Twenty."
slug: "lead-scouting"
metadata:
  paperclip:
    slug: "lead-scouting"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/lead-scouting"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/lead-scouting"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/lead-scouting"
  user-invocable: true
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/lead-scouting"
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

## Source 3 — online-activity signal (`linkedin-signals` CLI, cookieless)
Primary tool: **`linkedin-signals`** (`~/.local/bin/linkedin-signals`, Apify-actor-backed, NO cookie/login —
verified on the FREE Apify plan 2026-06-14). It DOES read individual profiles, posts, and reactions,
superseding the old "individual LinkedIn activity is login-walled" assumption. Subcommands:
- `search "<query>"` — discovery: name + title + headline + url (find pharmacists by keyword/role).
- `profile <url>` — about / experience / role / company → **confirms ownership** (propriétaire).
- `posts <url>` — their posts incl. reactions + comments → the **intent signal** (workload / AI / practice).
- `reactions <url>` — what they reacted to · `company <url>` — firmographics · `jobs "<q>"` — hiring.
Run `linkedin-signals --help` for flags (`--summary`, `--max`, `--location`).
- **GAP (not yet supported):** NO post-level discovery — there is no `post-search` / `post-comments` /
  `post-reactions` subcommand, so "find WHO commented on an AI-pharmacy post" (topic→engagers) is not yet
  available via the CLI; that play is manual until built.
- The old n8n + Browserless pipeline still exists for **company-page** watching (`http://browserless:3000/scrape`).
- No signal → mark the candidate `signal: none` — **never fabricate activity**.

## Source 4 — PLG signups (hottest signal)
New public-tenant pharmacists who self-served Atlas this week — they already tried the product:
```sql
-- pg canary app   (the ba_user table is in the `app` database; bare `pg canary` errors)
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
- Rank + write to CRM; **never send a DM or email** — that's the human (founder-led sales).
