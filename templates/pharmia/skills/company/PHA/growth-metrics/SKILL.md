---
name: "growth-metrics"
description: "Concrete pg canary queries for Pharmia conversion / activation / retention / user-growth + the MRR proxy. The HOW behind the Growth Brief CORE STATS and USER GROWTH sections."
slug: "growth-metrics"
metadata:
  paperclip:
    slug: "growth-metrics"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/growth-metrics"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/growth-metrics"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/growth-metrics"
  user-invocable: true
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/growth-metrics"
---

# growth-metrics

The runnable query set behind **CORE STATS** and **USER GROWTH**. Run on the **main app DB**:
`pg canary "<sql>"` (read-only, 60s timeout — safe by default; `app` is the default DB). camelCase columns MUST be quoted
(`"createdAt"`). Always report each metric with an `as-of` timestamp and a WoW delta.

## The funnel (verified schema, `ba_user` + `tenant`)
The public-tenant Atlas funnel is encoded in `ba_user`:
`is_anonymous=true` (anonymous trial) → `role='user'` (signed up) → `onboarding_completed` → `last_login_at`
within window (retained). `anon_queries_before_signup` measures pre-signup engagement.

**Anonymous trials are unreachable** — no email/name/phone is captured, so there is no way to DM or email
them. "Re-engage the anons" is NOT an actionable play. The only levers on anon trials are: *conversion*
(prompt for identity mid-trial so they become reachable), on-return in-app re-engagement (if their cookie
persists), and paid retargeting (what the `gclid`/`fbclid` attribution capture enables). The reachable
existing audiences are pre-onboarding drop-offs (`role='user'`, NOT `onboarding_completed` — they have
accounts/email) and not-yet-contacted owners in Twenty.

### 1. Signups — new users this week vs last (USER GROWTH)
```sql
SELECT date_trunc('week', "createdAt") AS wk, count(*)
FROM ba_user WHERE NOT is_anonymous AND role <> 'anonymous'
GROUP BY 1 ORDER BY 1 DESC LIMIT 8;
```
**WoW delta:** the top row is the *current partial week* — compare the two most recent **completed** weeks
(rows 2 vs 3), or an early-week run reads a false "growth down".

### 2. Anonymous → signup conversion (CONVERSION RATE)
```sql
WITH anon AS (SELECT count(*) a FROM ba_user WHERE is_anonymous),
     conv AS (SELECT count(*) c FROM ba_user
              WHERE NOT is_anonymous AND anon_queries_before_signup > 0)
SELECT conv.c, anon.a, round(100.0*conv.c/NULLIF(anon.a+conv.c,0),1) AS conv_pct FROM anon, conv;
```
(`anon_queries_before_signup > 0` = signed up after trying Atlas anonymously — the PLG conversion.)
**Caveat (approximate proxy, not a cohort-exact rate):** the denominator mixes a *live* anon snapshot with
*completed* conversions, and if anon rows are merged into the user row on conversion the anon count is
understated → the rate is inflated. Report it as an **approximate PLG conversion proxy**, not an audited
rate. The truer form windows signups by cohort (anon-started week W vs converted-by week W+n).

### 3. Activation — signed up AND completed onboarding (ACTIVATION)
```sql
SELECT count(*) FILTER (WHERE onboarding_completed) AS activated,
       count(*) AS signups,
       round(100.0*count(*) FILTER (WHERE onboarding_completed)/NULLIF(count(*),0),1) AS activation_pct
FROM ba_user WHERE NOT is_anonymous AND role <> 'anonymous'
  AND "createdAt" > now() - interval '30 days';
```

### 4. Retention — W1 (came back ≥1 day after signup) (RETENTION)
```sql
SELECT round(100.0*count(*) FILTER (
         WHERE last_login_at > "createdAt" + interval '1 day')
       /NULLIF(count(*),0),1) AS w1_retained_pct
FROM ba_user WHERE NOT is_anonymous AND role <> 'anonymous'
  AND "createdAt" BETWEEN now() - interval '5 weeks' AND now() - interval '1 week';
```

### 5. B2B vs public split (USER GROWTH — cohort split)
```sql
SELECT CASE WHEN tenant = 'app' THEN 'public'
            WHEN tenant IN ('admin','guest','disabled','tenant') THEN 'system'
            ELSE 'b2b' END AS surface,
       count(*) FILTER (WHERE NOT is_anonymous) AS users
FROM ba_user GROUP BY 1;
```
(`ba_user.tenant` holds the tenant **name** (a string), not the UUID. Public Atlas tenant name = `'app'`
(`PUBLIC_TENANT`); `'admin'` is the superadmin tenant and `'guest'`/`'disabled'`/`'tenant'` are test
tenants — bucket all of those as `system` so they aren't miscounted as B2B growth. Everything else is a
real B2B pharmacy.)

## MRR proxy (DEFERRED — no prod Autumn key wired)
There is **no billing/subscription table in this DB** and the prod Autumn key is not wired, so true MRR is
unavailable. Proxy = count of **active tenants with a billing product id set** × an ARPA estimate. (The
`*Enabled` booleans all default `true NOT NULL`, so they do NOT indicate paying — gate on the
`*BillingProductId` columns, which are only set when a tenant is wired to an Autumn product.)
```sql
SELECT count(*) FILTER (WHERE "echoBillingProductId" IS NOT NULL
                           OR "copilotBillingProductId" IS NOT NULL
                           OR "consultationBillingProductId" IS NOT NULL) AS paid_tenants,
       count(*) AS active_tenants
FROM tenant WHERE active AND name NOT IN ('app','admin','guest','disabled');
```
Report as **`paid_tenants × ARPA-est = $X (PROXY)`** — never as audited revenue. **To make this real: wire
the prod Autumn key and replace this with `autumn` CLI customer/MRR data.** Flag this every cycle.

## Atlas question corpus (what users want / where Atlas fails)
- `threads modelmix canary --since 7d` — served-model mix + fallback rate.
- `threads list canary --problems-only` — no-reply / abort / tool-error threads.
- Theme-mine on `pg canary mastra`:
```sql
SELECT left(content::text, 200) FROM mastra_messages
WHERE role='user' AND "createdAt" > now() - interval '7 days'
ORDER BY "createdAt" DESC LIMIT 200;
```
Cluster the 200 into top-3 intents + top-3 failure modes by hand/LLM. Feeds growth-lead (gaps) and content (topics).

## Discipline
- Read-only only; never `--write` here.
- Every metric → query + `as-of` + WoW delta. No bare numbers.
- MRR is a labelled PROXY until Autumn is wired. Say so.
