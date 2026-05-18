---
name: "review-protocol"
description: "Use after implementation is complete — 8-phase verification protocol covering build, types, lint, tests, security, diff review, acceptance criteria, and final verdict"
slug: "review-protocol"
metadata:
  author: "vortex"
  paperclip:
    slug: "review-protocol"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/review-protocol"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/review-protocol"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/review-protocol"
  type: "custom"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/review-protocol"
---

# Review Protocol

## 8-Phase Verification

Run all phases in order. No completion claims without fresh evidence from each phase.

### Phase 1: Build
Run the build command. Read output. Fix all errors. Re-run until clean.

**If `package.json`, `package-lock.json`, or any `Dockerfile*` changed — reproduce the prod image build, not just the host build.** Host `tsc`/`vite build` cannot catch lockfile drift, missing optional deps, or `npm ci` failures that only surface inside the production base image. At minimum:
- Identify the Node + npm version pinned in `Dockerfile.prod` (e.g. `node:22-alpine`). Match it locally (nvm).
- Run the exact `npm ci` invocation the Dockerfile uses (e.g. `npm ci --legacy-peer-deps`) against a fresh `node_modules`, with the same `patches/` directory and the same pruned lockfile if turbo prune is in the pipeline.
- If feasible, run `docker build -f <Dockerfile.prod> .` end-to-end. If not, at least reproduce the failing stage's commands in a clean `/tmp` dir with the matching Node version.
- Verify no `Missing: <pkg>@<v> from lock file` errors. These come from regenerating the lockfile under a different Node major (optional native/wasm transitives diverge between Node 22 and 24).

Host type-check passing is NOT evidence that the prod build will succeed.

### Phase 2: Type Check
Run type checking. Read output. Fix all errors. Re-run until clean.

### Phase 3: Lint
Run linter. Read output. Fix all violations introduced by the change. Re-run until clean.

### Phase 4: Tests + Coverage Gate
Run test suite. Read output. Fix all failures. Then verify:
- New tests exist for new features (at least happy path)
- New regression tests exist for bug fixes
- Tests are not skipped or `.skip`'d
- Tests assert meaningful behavior (not `expect(true).toBe(true)`)
- Tests follow the 7 quality rules (no toBeTruthy as primary, no implementation-detail tests, no `any`, etc.)
- For priority >= 15 code (safety, billing, auth): run mutation testing

If no new tests exist for new code: FAIL. Send back with "missing tests."

### Phase 5: Security + Dependency Audit
Security scan of changes:
- No hardcoded secrets or credentials
- No unsanitized user input reaching SQL/shell/eval
- No missing auth/authz checks
- No sensitive data in logs or error messages
- No new deps with known vulnerabilities

If package.json or lock file changed — Dependency Change Audit:
- Identify every added, removed, or upgraded dependency
- For upgrades: read changelog between old and new version for breaking changes
- For new deps: check bundle size, maintenance status, license
- For removed deps: verify no imports still reference the package
- "npm install && tests pass" is NOT sufficient — silent behavioral changes are the most dangerous regressions

### Phase 6: Diff Review + Infrastructure Validation
Review `git diff` for:
- Unintended changes to files not in the plan
- Leftover console.log / debug statements
- TODO/FIXME that should be resolved
- Dead code, unnecessary complexity, missing boundary error handling

If diff touches Docker, Compose, CI/CD, or deployment config:
- Dockerfile: multi-stage build order correct, no secrets in layers, base image pinned
- Compose: service dependencies with healthchecks, network isolation, correct volume mounts
- CI/CD: correct stage order, secrets from vault not hardcoded
- Deployment: DNS records exist, domain entries exist, TLS config correct
- Never assume infra config works by reading it — verify against running environment where possible

### Phase 7: Acceptance Criteria
For each criterion from the plan, verify PASS or FAIL with evidence (test output, command result, observable behavior). If not met, fix or escalate.

### Phase 8: Verification Report

Produce a structured report:

```
Phase          | Status        | Details                    | Severity
Build          | PASS/FAIL     | [evidence]                 | —
Prod Build     | PASS/SKIP/FAIL| [Docker/npm ci repro]      | HIGH if FAIL
Type Check     | PASS/FAIL     | [evidence]                 | —
Lint           | PASS/FAIL     | [evidence]                 | —
Tests          | PASS/FAIL     | [X/Y passed, coverage]     | —
Security       | PASS/WARN/FAIL| [findings + confidence]    | HIGH/MED/LOW
Dep Audit      | PASS/SKIP/WARN| [changes found]            | —
Diff Review    | PASS/WARN     | [concerns]                 | —
Infra          | PASS/SKIP/WARN| [validation results]       | —
Acceptance     | PASS/FAIL     | [per-criterion evidence]   | —

Verdict: APPROVED / CHANGES REQUESTED
```

If CHANGES REQUESTED: list specific failures with actionable fixes. Send back to implementation.
