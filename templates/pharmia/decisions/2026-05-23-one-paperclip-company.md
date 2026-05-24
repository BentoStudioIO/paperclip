---
title: Keep all Pharmia agents in one Paperclip company instead of splitting by function
status: accepted
date: 2026-05-23
deciders: team
supersedes:
superseded-by:
---

## Context

Paperclip's data model has a hard tenancy boundary at `companies.id` —
agents, skills, instances, board permissions, and runtime instructions all
hang off a single company row. Cross-company referencing is not a first-class
operation: it would require dual board API tokens, duplicated skills, and
manual sync.

The question that came up: should we split Pharmia's agents into multiple
companies (engineering, operations, legal, pharmacy) to mirror real
departmental structure? Or keep one company with role-tagged agents?

## Decision

One Paperclip company for all Pharmia agents.

Departmental structure is expressed through agent `role` fields
(`engineering`, `pharmacy`, `legal`, `meta`, ...) and the `reportsTo`
hierarchy, not through company boundaries. Cross-functional collaboration
(e.g., a legal review of an engineering plan) happens inside the same
company with shared skills and a shared task envelope.

## Rationale

The platform optimises strongly for the single-company case: skills are
keyed `company/<id>/<slug>`, board API keys are scoped per company, runtime
instructions live under `companies/<id>/agents/<id>/instructions/`, and the
sidebar manifest is per company. Splitting would multiply every one of these
artefacts.

The real benefit a split would provide is access isolation — but our access
isolation needs are already covered by per-agent skill bindings and
`reportsTo`. Departmental separation that does not require access isolation
is just an organisational tag, and a tag fits inside one company.

## Alternatives considered

- Separate company per department — rejected: triples the artefact count,
  breaks cross-functional task handoffs, no security benefit.
- One company with sub-orgs / namespaces — rejected: the platform does not
  expose sub-org primitives; emulating them with naming conventions reintroduces
  the drift problem.
- Hybrid (one company for shared eng agents, one per regulated function) —
  rejected as the worst of both worlds: duplication for shared skills,
  cross-company handoffs for any non-trivial workflow.

## Consequences

- positive: one set of skills, one board API key, one sidebar, one import
  command; cross-functional handoffs work via normal `tasks/` envelopes;
  the org-as-code repo has a single canonical tree
- negative: a future need for hard isolation between two functions (e.g.,
  a regulated audit boundary) would require revisiting this decision;
  permission management is per-agent rather than per-department
- mitigations: agent `role` tags are explicit so an auditor can filter by
  function; if a function genuinely needs isolation, supersede this
  decision and document the threat model that forces the split
