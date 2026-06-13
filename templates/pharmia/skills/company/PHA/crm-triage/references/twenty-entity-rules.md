# Twenty CRM — Entity Rules (runtime-self-contained)

Agent-facing CRM rules for the agents-VPS runtime (where `~/.claude/rules/twenty-crm.md`
is NOT present). Use the high-level `twenty` subcommands — never hand-write GraphQL,
never hand-craft UUIDs (the server generates them).

## Field model + live enums (verified)
- **name** is composite `{firstName,lastName}` — split correctly (first="Sophya", last="Berrada"; NEVER first="Sophya Berrada" last="Berrada").
- **emails** `{primaryEmail, additionalEmails}`; **phones** split into `{primaryPhoneNumber, callingCode, countryCode}` — pass `--phone +15145551234` and the CLI splits it.
- **Person.source**: `PHARMIA_SIGNUP` | `INBOUND_MEETING` | `REFERRAL` | `COLD` | `SOCIAL` | `EVENT` | `PARTNER_REFERRAL`
- **Person.group** (persona, NOT origin): `PHARMACIST_OWNER` | `PHARMACIST` | `VC` | `INFLUENCER` | `MENTOR` | `CLIENT` | `SALES` | `PARTNER` | null
- **Person.pharmiaTenant**: the Pharmia tenant SLUG (`app`, `pjc-254`, …), NOT the friendly name ("Public").
- **Person.pharmiaUserId**: the Pharmia **better-auth user id** (`ba_user.id`) — the CRM↔app link. Set it whenever the person has a Pharmia account; its presence is how we identify an **Atlas user** in the CRM (combine with `group=PHARMACIST_OWNER` for the owner∩Atlas segment). `group` is single-select so it can't also encode "Atlas user" — that's exactly why the link field exists. Get the id from `pg canary app "SELECT id FROM ba_user WHERE lower(email)='<email>'"`. A daily cron `pharmia-twenty-atlas-sync` backfills it by email for anyone missed.
- **Opportunity.stage**: `NEW` | `SCREENING` | `MEETING` | `PROPOSAL` | `CLIENT` | `DONE` | `LATER`
- **Note/Task body** = markdown via `twenty note add --md` / `--md-file`.
- `source` = where they came from; `group` = who they are. Keep them distinct.

## The `twenty` subcommands (use these, not raw gql)
```
twenty person get <email|phone|name> [--json]
twenty person upsert --email X [--first --last --phone --city --job-title --source <enum> --tenant <slug> --pharmia-user-id <ba_user.id> --group <enum>]
twenty opportunity get --person <id> [--all]      # dedupe: check for an active opp first
twenty opportunity create --name "..." [--stage <enum> --close-date <ISO> --person <id> --company <id>]
twenty opportunity update <id> [--stage --close-date]
twenty note add --title "..." (--md "..." | --md-file PATH) [--link person:<id> --link opportunity:<id>]
twenty company upsert --name "..." [--employees --domain --city --rx-per-day --icp]
```
Always `person get` (or `opportunity get --person`) BEFORE create → upsert/dedupe, never duplicate.

## Ownership detection — MANDATORY for any pharmacist (never skip)
Owner-operators (Acces Pharma, Pharmaprix, Proxim, Brunet, Familiprix, Jean Coutu, Uniprix) are the highest-value cohort. Don't stop at "OPQ says licensed → PHARMACIST". Check, in parallel:
- **Tenant banner**: a Pharmia tenant like "Pharmaprix X"/"Proxim Y" → prefix is the banner; the tenant's pharmacist is very likely its owner. Cross-ref OPQ.
- **Banner sites** (public owner listings): `bx web "<name> acces pharma propriétaire"` / `pharmaprix` / `proxim` / `brunet` / `familiprix` / `jean coutu` / `uniprix`, or generic `bx web "<name> pharmacien propriétaire <city>"`.
- **REQ** (registre des entreprises QC): `bx web "<name> registraire entreprises quebec pharmacie"` (admin/shareholder of a pharmacy entity).
- **Context signals**: `signup_source`/`referral_source` = conference/demo/sales → usually an owner; tenant != "app" matching the name → owner with their own tenant.
≥1 source confirms ownership → `group=PHARMACIST_OWNER` + capture the pharmacy/banner in the Note. Zero after real search → `PHARMACIST`.

## Identity enrichment when OPQ is empty — MANDATORY
Never conclude "probable non-pharmacist" and stop. OPQ empty → one of: student (check `studentLicenseNumber` in the OPQ API), other health role (technician/ATP/nurse/MD), or industry/commercial/curious. Search before finalizing:
1. **LinkedIn** (priority — where non-pharmacist industry people are): `bx web "<full name> linkedin"` (+ pharma/pharmacy/city). Note title/employer (e.g. "Sales Rep Pfizer", "ATP CHUM", "Étudiant Pharm.D U Laval").
2. **Alt ordres** if the name suggests another profession: CMQ (MDs), OIIQ (nurses), OTPQ (technicians), UdeM/Laval (pharmacy students).
3. **General web**: `bx web "<full name>"`.
4. **Email/tenant signals**: pro domain (@chain.ca, @hopital.qc.ca, @industry.com) = strong signal; tenant != "app" = staff of that pharmacy.
Classify: student → `group=null`, jobTitle="Étudiant(e) en pharmacie - <uni>"; ATP/technician → `group=null`, jobTitle accordingly; **pharma rep / industry → `group=SALES`** (high value — flag it); MD/nurse → `group=null` + title; nothing after exhaustive search → `group=null`, jobTitle="Non identifié (recherche exhaustive)" + flag for manual.

## Note structure (attach to Person, and Opportunity if one exists)
`twenty note add --title "Signup Pharmia - <tenant>" --md "..." --link person:<id> [--link opportunity:<id>]` with sections:
- **OPQ**: licence #, ville, statut — or "non-trouvé après recherche".
- **Identité** (if OPQ empty): LinkedIn/web/ordre findings + verbatim URLs.
- **Propriété**: PHARMACIST_OWNER of [pharmacies] + source (banner site / REQ / web), or "non-proprio confirmé", or "N/A".
- **Compte**: signup_source, attribution, locale, onboarding state.

## OPQ classify (raw — `opq-verify` is NOT on the runtime)
```
curl -s 'https://www.opq.org/wp-content/uploads/pharmacist-search/pharmacists_index.json' \
  | jq '[.[] | select(.fullName | test("<name>";"i"))]'
```
Fields: id, fullName, licenseNumber, studentLicenseNumber, city, isStudent. Empty match ≠ "not a pharmacist" → run the identity-enrichment block.

## Write authorization — interactive vs autonomous
- **Interactive / batch / destructive** (operator-run triage, cohort reconcile, reward claw-back, deletes): **confirm before writing.**
- **Autonomous watch** (a single signup/booking trigger enriching ONE record via `person upsert` + `note add` — idempotent by design): write WITHOUT per-record confirm. This is the only autonomous-write exception; everything else still confirms.
