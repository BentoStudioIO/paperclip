---
title: <short imperative — what gets done, not what gets discussed>
assignee: <agent slug or "open">
reviewer: <agent slug or "open">
status: open
priority: med
---

<!--
Use this template for any task that crosses agent boundaries. The envelope is
the contract between the dispatcher and the assignee — if a field is missing,
the dispatcher owns the gap and must fill it before assigning. The assignee
may refuse a task whose "Definition of done" is not independently verifiable.

For trivial in-agent work (a single grep, a one-line edit), skip the envelope
and just do the work.
-->

## Context

<1 paragraph — why this task exists, what came before, what other work it
depends on. Link to the spec, decision, or incident report that triggered it.>

## Inputs

- <every file, decision record, dataset, external link, or prior conversation
  the assignee needs. If the assignee has to ask "where do I find X?", the
  Inputs list is incomplete.>

## Definition of done

- <bulleted acceptance criteria. Each one must be independently verifiable
  with a command, a test, or an inspection. Avoid "works correctly" — write
  the specific check that proves it works.>

## Escalate on

- <conditions that should bounce the task back to the dispatcher rather than
  being decided locally. Examples: scope expands beyond N files, blocker
  requires a decision the assignee is not authorized to make, evidence
  contradicts the stated assumption.>

## Out of scope

- <explicit boundaries. List things the assignee might reasonably think are
  part of this task but are not. Prevents scope creep without requiring the
  assignee to ask.>
