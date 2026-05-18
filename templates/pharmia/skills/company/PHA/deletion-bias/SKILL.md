---
name: "deletion-bias"
description: "Use during implementation — enforces minimal code, net-negative LOC, and prevents over-engineering and premature abstraction"
slug: "deletion-bias"
metadata:
  author: "vortex"
  paperclip:
    slug: "deletion-bias"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/deletion-bias"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/deletion-bias"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/deletion-bias"
  type: "custom"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/deletion-bias"
---

# Deletion Bias

## Core Rule

For every line added, ask what can be removed. Net-negative LOC is the ideal outcome. Measure success by end-state codebase size, not effort expended.

## Implementation Checklist

For each task:

1. Can this be done with an existing library instead of custom code?
2. Can this extend existing code rather than creating new files?
3. After implementing, count: lines added vs lines removed. Prefer net-negative.
4. Files created should be 0 whenever possible.
5. Every new abstraction must justify itself — if it's used once, inline it.
6. If any metric is higher than necessary, refactor before moving on.

## No Premature Abstraction

- No interfaces for single implementations
- No flexibility that wasn't explicitly requested
- No abstraction until there are 3+ concrete instances that share the pattern
- If 200 lines could be 50, rewrite it as 50

## Anti-Patterns (Never Do These)

- **New file when logic fits in an existing one** — check existing files first
- **Interface/abstraction for a single implementation** — inline it
- **Utils/helpers grab-bag files** — almost always a code smell
- **Error handling for impossible states** — don't handle what can't happen
- **Comments restating code** — if the code needs a comment to explain what it does, simplify the code
- **Feature flags when you can just change the code** — flags add permanent complexity
- **Wrapper classes that add nothing** — if the wrapper just delegates, remove it
- **Config/options nobody asked for** — build what was requested, nothing more

## Refactor Adjacent Code

When touching a file, check if nearby code can be simplified as part of the change. Opportunistic cleanup that reduces total LOC is always welcome.

## Scope Discipline

- Follow the approved plan — do not add features that weren't planned
- No features beyond what was asked
- No abstractions for single-use code
- Surgical changes only — minimal diff, minimal files touched
- If you're creating more than the plan calls for, stop and reassess
