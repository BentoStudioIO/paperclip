---
title: Split bento-docs into sources/ (verbatim primaries) and derived/ (authored interpretation)
status: accepted
date: 2026-05-23
deciders: team
supersedes:
superseded-by:
---

## Context

Bento-docs is the durable knowledge repository for non-code departments
(legal, pharmacy, design). It accumulated a mix of primary regulatory text,
contract excerpts, paraphrased summaries, agent-authored interpretation, and
working notes — all in the same tree. Agents querying for a fact had no way
to know whether they were reading the law itself, a summary of the law, or
an old paraphrase that drifted.

This is the root cause of the "confident-wrong legal answer" failure mode:
an agent reads a derived summary, treats it as canonical, and cites the
summary's wording back to the user. When the summary is stale or imprecise,
the answer is wrong.

## Decision

Reorganize bento-docs into two top-level trees:

- `sources/` — verbatim copies of primary text (laws, regulations,
  contracts, certifications, audit reports). Read-only by convention.
  Each file carries provenance metadata in a header (origin URL, retrieval
  date, hash).
- `derived/` — authored interpretation, summaries, working notes, agent
  output. Every claim in `derived/` that depends on a primary must cite
  the file in `sources/`.

A `MANIFEST.yaml` lists every `sources/` file with its provenance. A
`verify.sh` script re-checks the manifest (file exists, hash matches if
recorded, header well-formed) and runs in CI.

## Rationale

The split makes the trust boundary explicit. An agent answering a legal
question opens the primary in `sources/` and cites it. If only a derived
summary exists, the agent flags that the answer is not anchored to a
primary and either (a) fetches the primary or (b) marks the answer as
provisional.

The manifest plus verify.sh prevents drift: nobody can quietly modify a
"primary" copy, because the hash check fails on the next CI run.

## Alternatives considered

- Per-file `kind: primary | derived` frontmatter — rejected because it
  relies on every author tagging correctly, and a misfiled document is
  silently authoritative.
- Single `legal/` tree with citation discipline — rejected because the
  discipline never held; mixed-trust trees regress.
- Read-only filesystem permission on a subtree — rejected as too brittle
  on a shared dev environment.

## Consequences

- positive: every legal/compliance answer can be audited to its primary;
  derived content is allowed to evolve without polluting the source of
  truth; CI catches silent edits to primaries
- negative: contributors must classify new content (sources or derived)
  and write provenance metadata; the manifest is a maintenance surface
- mitigations: a `bento-docs add-source <path> <url>` helper that creates
  the file, computes the hash, and updates the manifest in one step
