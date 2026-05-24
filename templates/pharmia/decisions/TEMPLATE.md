---
title: <decision in one line — what was chosen, not what was discussed>
status: proposed
date: YYYY-MM-DD
deciders: <names or "team">
supersedes: <decision filename or empty>
superseded-by: <decision filename or empty>
---

<!--
A decision record captures a one-shot architectural or policy choice with its
rationale, so the next agent reading the codebase can understand "why this
shape" without re-deriving the reasoning. File naming: YYYY-MM-DD-<slug>.md.

When a later decision overrides this one, set this file's `status: superseded`
and `superseded-by: <new file>`, and set the new file's `supersedes:` to this
file. Never delete a superseded decision — it is part of the audit trail.
-->

## Context

<the situation that demanded a decision: the constraints, the prior state,
the forcing function. What made this a question rather than an obvious move?>

## Decision

<what we chose, in 1–3 sentences. Precise enough that a reviewer can verify
the implementation matches the decision.>

## Rationale

<why this over the alternatives. Anchor on the specific properties that
mattered — cost, blast radius, reversibility, regulatory constraint, etc.>

## Alternatives considered

- <alt 1> — rejected because…
- <alt 2> — rejected because…

## Consequences

- positive: <what gets easier or cheaper>
- negative: <what we accept as a cost or constraint>
- mitigations: <how we manage the negative>
