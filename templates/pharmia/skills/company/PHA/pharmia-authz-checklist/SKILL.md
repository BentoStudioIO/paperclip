---
name: "pharmia-authz-checklist"
description: "Reusable security-rounds checklist for any new/changed Pharmia router, handler, or stream endpoint — tenant isolation, scope/role gates, PHI-leakage, input bounds, content-type. Use before merging backend access-surface changes, or as the dispatch brief for a security reviewer. Concrete: where tenant policy is declared and the fail-closed flag."
slug: "pharmia-authz-checklist"
metadata:
  paperclip:
    slug: "pharmia-authz-checklist"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-authz-checklist"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-authz-checklist"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-authz-checklist"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-authz-checklist"
---

# Pharmia Authz / Security-Rounds Checklist

Run this over any diff that adds or changes a backend **access surface**: a tRPC
procedure, an Express handler, an SSE/stream endpoint, or a file/audio proxy.
Pharmia carries clinical PHI on B2B tenants, so authz is correctness-by-
construction, not best-effort. Use this as the merge gate OR as the brief you
hand a clean-context security reviewer.

## 1 — Tenant Isolation (the load-bearing control)
Tenant policy is **declared at the point of use** and enforced centrally — never
inline a tenant check per call site.

- **tRPC procedures** declare `tenantAccess` in `.meta({ … })`. The enforcement
  middleware is `packages/api/src/middlewares/checkAuth.ts`; the policy types and
  helpers are `packages/api/src/auth/tenantPolicy.ts`
  (`TenantAccessMode = none|read|write|operate|administer|owner|public`,
  `resolveAllowedTenants`, `hasTenantFeatureEnabled`).
- **Express handlers** call `resolveExpressAuth(req, '<scope>', '<read|write>')`
  (`packages/api/src/auth/expressAuth.ts`) — same `tenantPolicy.ts` SSOT.
- [ ] **Every new procedure declares `tenantAccess`.** A procedure with no
  `tenantAccess` and no `requiredScopes` is DENIED by the fail-closed flag
  `TENANT_POLICY_FAIL_CLOSED = true` (`tenantPolicy.ts`) — message "Endpoint must
  declare tenantAccess". Do NOT disable this flag to make a test pass.
- [ ] **`administer` / `owner` have NO public-tenant exemption** — they assert on
  every tenant including `app` (by construction in `checkAuth.ts`). Don't add an
  exemption.
- [ ] **The resource's tenant is checked, not just the caller's mode.** Loading a
  row by id must confirm the row's `tenantId` is in the caller's allowed set
  (`assertTenantAccess`-style), or a `read`-moded caller can pull another
  tenant's record. Reproduce the cross-tenant read in a test.
- [ ] **Public tenant `app` holds NO clinical data.** A new endpoint reachable on
  `app` must not query or return clinical tables (consultations, insights, echo
  notes). Bookmarks/threads only.

## 2 — Scope / Role Gates
- [ ] Procedure declares `requiredScopes: { scopes: ['…'] }` matching the action
  (verify against `packages/api/src/auth/scope.ts` / `scopeAssignations.ts`).
- [ ] Non-staff roles are excluded where required — reuse `isNonStaffRole`
  (`auth/role.ts`); patient/anon must not reach pharmacist-only surfaces.
- [ ] No scope is a strict superset of what the endpoint needs (least privilege).

## 3 — PHI / Data Leakage
- [ ] Error messages and logs never echo PHI (patient name, DOB, free-text
  clinical content). Log ids, not bodies.
- [ ] The response DTO returns only the fields the caller's role needs — no
  `select *` of a clinical row to a low-priv caller.
- [ ] Telemetry/analytics added in the same change carries NO clinical topic,
  source URL, or identifier → run the **`law25-telemetry-review`** skill on it.

## 4 — Input Bounds & Abuse
- [ ] Every input is a zod schema with explicit bounds: list `limit` capped
  (existing pattern: `.max(50)`), strings length-bounded, ids `z.uuid()`.
- [ ] Pagination cursor can't be coerced to read across tenants.
- [ ] Expensive/stream endpoints have back-pressure or rate limits (mirror the
  analyzer `rateLimit.ts` pattern; SSE replays bounded active state on connect).

## 5 — Content-Type & Proxy Safety
- [ ] File/audio proxies (e.g. `routes/echo/audioStreamHandler.ts`) set an
  explicit safe `Content-Type` and never reflect the client's, and re-check
  tenant ownership of the streamed object — auth on the row, not just the route.
- [ ] No user-controlled value reaches a path, MinIO key, or shell without
  validation.

## 6 — Tests (mandatory for security-sensitive changes)
Per CLAUDE.md, security-sensitive backend changes ship with at least minimal
focused tests. Write a FAILING test first that proves the gate:
- a cross-tenant read returns FORBIDDEN,
- a missing-scope caller is rejected,
- the fail-closed default denies an undeclared endpoint.
Run `cd packages/api && npm run test:once` (smallest relevant test first).

## 7 — VERDICT
```
VERDICT
- Surfaces changed: <procedures / handlers / streams>
- tenantAccess declared on all: yes/no   fail-closed intact: yes/no
- Cross-tenant read tested:     yes/no
- Scope/role gates:             ok / gap: …
- PHI leakage:                  none / found: …
- Verdict: SAFE TO MERGE | BLOCKED (<reason>)
```

## DRY
Telemetry-leak specifics → **`law25-telemetry-review`**. Test prioritization /
mutation standards → **`testing-intelligence`**. This skill owns the authz gate
and points at the SSOT files above — don't restate `tenantPolicy.ts` internals.
