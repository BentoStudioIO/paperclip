---
name: "researcher-workflow"
description: "Use before building anything new — enforces library doc verification, existing solution search, and capability verification before writing custom code"
slug: "researcher-workflow"
metadata:
  author: "vortex"
  paperclip:
    slug: "researcher-workflow"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/researcher-workflow"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/researcher-workflow"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/researcher-workflow"
  type: "custom"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/researcher-workflow"
---

# Researcher Workflow

## Library Docs Gate (Mandatory)

Before touching any library integration, configuration, or API usage — run this 4-step check:

1. **VERSION CHECK** — Read the library version from package.json/lock file. Has it had a major/minor release since your version? If upgrading, read the FULL changelog between current and target versions.

2. **API DOCS CHECK** — Use ctx7 or official docs for the specific API/feature being used. Verify: correct API for your version? Built-in feature for what you're building? Known gotchas or constraints?

3. **BREAKING CHANGE SCAN** — Use `gh release list <owner/repo> --limit 10` for recent releases. For any major/minor bump, read release notes. Cross-reference against APIs you use.

4. **DOCUMENT WHAT WAS READ** — List every doc page, changelog entry, API reference consulted. Format: `[library] v[version]: [doc/page] — [what was learned]`. If nothing relevant found, document that too.

Hard rules: never use a library API from memory alone — verify against current docs. Never assume syntax from version N works in N+1. If ctx7 doesn't cover it, use `gh` to find the repo and read docs directly.

## Decision Framework

Priority order — exhaust each tier before moving to the next:

1. **Adopt** — Use an existing solution as-is (requires verification it actually works for your case)
2. **Extend** — Fork or extend an existing solution (must identify the specific extension point)
3. **Compose** — Combine multiple existing solutions
4. **Build** — Write custom code (last resort, must document why no existing solution fits)

## 6 Common Traps

1. **Library vs CLI confusion** — npm packages are often libraries, not CLIs. Check for `bin` entry in package.json.
2. **Partial feature match** — A tool may support the category but not the specific operation. Check exact commands in docs.
3. **Official does not mean better** — Official tools may lack features you need. Compare side-by-side.
4. **README-driven adoption** — README promises may not match implementation. Look for working examples or test yourself.
5. **Stale popularity** — Recent commits don't mean it works for your case. Check issues/PRs for your specific need.
6. **Transitive bloat** — Adding a dependency for one function may pull in a heavy tree. Check bundle size.

## Confidence Levels

Every recommendation gets a confidence level:

- **High** — Tool tested or verified against specific requirements
- **Medium** — Appears to fit based on docs/examples, not personally verified
- **Low** — Might fit, significant uncertainty, needs validation

Never present Low confidence as fact. Always qualify with uncertainty.

## Capability Verification

Before recommending "Adopt": install it, run it, check output. A README read is not verification. Minimum 10 minutes of actual verification.

## Framework Plugin Check

Before building custom functionality, check whether installed frameworks already have built-in features or official plugins that solve the problem. Check docs sites, plugin registries, and `node_modules` docs.
