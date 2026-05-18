---
name: "testing-intelligence"
description: "Use when writing tests, reviewing test quality, or deciding what to test — enforces prioritization, quality rules, and mutation testing standards"
slug: "testing-intelligence"
metadata:
  author: "vortex"
  paperclip:
    slug: "testing-intelligence"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/testing-intelligence"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/testing-intelligence"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/testing-intelligence"
  type: "custom"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/testing-intelligence"
---

# Testing Intelligence

## Test Prioritization

Score every piece of code before writing tests:

```
Priority = Business Impact (1-5) x Failure Probability (1-5)

>= 15: MUST test. Multiple cases covering happy path + edge cases.
9-14:  SHOULD test. At minimum happy path + one error case.
<= 8:  MAY skip. Document why. Don't write filler tests.
```

Default allocation per feature: start with 2 tests (one positive, one negative). Add more only with justification. Realistic range: 2-7 tests. More than 7 suggests the feature needs decomposition.

Do NOT test: getters/setters, config constants, auto-generated code, migration files.

## Tests the Construction Eliminates

Before writing a test, ask: **does a structural guarantee already prevent this failure?** If yes, the test is redundant. Three categories of structural guarantees eliminate tests:

- **Type system** — if the type makes a state unrepresentable, a test for that state is waste. Tests that re-verify what the compiler already enforces add noise without confidence.
- **Database constraints** — uniqueness, nullability, referential integrity, and check constraints enforced at the storage layer don't need app-level test coverage. Test the constraint exists (migration test), not that the app rejects what the DB already rejects.
- **Declarative enforcement** — when a cross-cutting concern (auth, tenant isolation, input validation) is enforced by a central mechanism, one integration test on the mechanism is worth N unit tests on individual call sites. Test the policy, not every consumer of the policy.

**What to test instead:**
- Boundaries where unvalidated data enters the system (API input, file parsing, external responses)
- The enforcement mechanism itself (does the policy actually reject what it should?)
- The constraint itself (does the migration apply correctly?)
- Behavior that spans multiple guarantees (integration points where no single guarantee covers the full path)

**Evidence requirement:** When skipping a test because of a structural guarantee, cite it. This makes the reasoning auditable and catches cases where the guarantee is later removed.

## Test-with-Feature Mandate

- Every feature ships with at least one test exercising the happy path.
- Every bug fix ships with a regression test that reproduces the bug. The test MUST fail against pre-fix code.
- Tests are written in the same task/PR. "I'll add tests later" is not acceptable.

## 7 Quality Rules

Apply these regardless of test framework. Examples use Jest/Vitest syntax — use equivalents for other frameworks.

1. **Never use `toBeTruthy()`/`toBeDefined()` as primary assertions.** Assert specific values with strict equality.
2. **Never test implementation details.** Test behavior (input -> output), not internals (call counts, mock shapes).
3. **Never mock your own pure functions.** Mock only external boundaries (APIs, DB, filesystem). Prefer fakes > stubs > spies > mocks.
4. **Never use `any` in test files.** Tests are executable documentation. Use proper types.
5. **Never share mutable state between tests.** Each test is independent. Use `beforeEach` for setup.
6. **Never nest `describe` more than 2 levels.** Put context in test names instead.
7. **Never write a test without a behavioral assertion.** "No error thrown" or "returns something" is a shell test.

Always follow AAA pattern (Arrange, Act, Assert) with one act per test. Use parameterized tests (`it.each`) instead of copy-pasting test bodies.

## Test Naming

Format: `[role/context]: should [expected behavior] when [condition]`

## Mutation Testing

Run on priority >= 15 code after writing tests. Interpretation:

- 90%+: Excellent — tests effectively catch regressions
- 70-89%: Good — review surviving mutants for critical paths
- 60-69%: Weak — surviving mutants likely hide real gaps
- < 60%: Critical — tests provide false confidence, prioritize strengthening

When a mutant survives: identify the line, assess priority, write a test that kills it, re-run to confirm. Skip mutation testing for UI components, config, migrations, and eval infrastructure.
