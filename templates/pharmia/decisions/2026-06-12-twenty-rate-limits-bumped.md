---
title: Twenty CRM API rate limits bumped to ~100k/min (single-tenant Bento instance)
status: accepted
date: 2026-06-12
deciders: amine (CTO)
supersedes:
superseded-by:
---

## Context

Twenty CRM (self-hosted at `twenty.bentostudio.io`, container `bento-studio-twenty-w9iq7f-twenty-server-1`) ships with defaults:

- `API_RATE_LIMITING_SHORT_LIMIT = 100` (per 1 sec window)
- `API_RATE_LIMITING_LONG_LIMIT = 100` (per 60 sec window)

These defaults assume a multi-tenant SaaS workload. Our instance is **single-tenant**: only the Bento Studio team + automation (`twenty` CLI from this repo, the vortex-claude Discord bot signup pipeline, batch backfill scripts) hit the API. Hitting the 100/min cap during bulk operations (e.g., the 88-person Accès Pharma backfill on 2026-06-12 needed ~85 calls/min sustained for 14 minutes) forces consumers to wrap calls in Python throttles, which is friction every batch script has to re-implement.

## Decision

Bump both limits by **1000×**:

- `API_RATE_LIMITING_SHORT_LIMIT = 10_000` (10k req/sec)
- `API_RATE_LIMITING_LONG_LIMIT = 100_000` (100k req/min)

These are upper bounds, not target throughput — the token bucket still smooths usage. Effective ceiling is well above anything a single human team can generate.

## How it's wired (Dokploy → docker-compose)

The compose source in Dokploy (composeId `Qk8cbFjq6-ftleQZaXb-k`, app name `twenty` on instance `bento`) declares the env refs on the `twenty-server` service:

```yaml
environment:
  IS_CONFIG_VARIABLES_IN_DB_ENABLED: "true"
  API_RATE_LIMITING_SHORT_LIMIT: ${API_RATE_LIMITING_SHORT_LIMIT:-10000}
  API_RATE_LIMITING_LONG_LIMIT: ${API_RATE_LIMITING_LONG_LIMIT:-100000}
```

Defaults baked into the compose so any future redeploy preserves the new ceiling even if the Dokploy `.env` is lost. The Dokploy `.env` also has the same values (set via `dokploy bento env-set twenty API_RATE_LIMITING_SHORT_LIMIT=10000 API_RATE_LIMITING_LONG_LIMIT=100000`).

## Verification

After deploy:

```sh
ssh bento "docker exec bento-studio-twenty-w9iq7f-twenty-server-1 sh -c 'echo SHORT=\$API_RATE_LIMITING_SHORT_LIMIT LONG=\$API_RATE_LIMITING_LONG_LIMIT'"
# → SHORT=10000 LONG=100000
```

A subsequent burst of 150 parallel GraphQL queries succeeded without 429s.

## Reversal

To reset to upstream defaults (e.g., if Twenty changes default behavior in a breaking way):

```sh
dokploy bento env-rm twenty API_RATE_LIMITING_SHORT_LIMIT API_RATE_LIMITING_LONG_LIMIT
# Then PATCH the compose file via `dokploy bento compose update` to drop the two env refs
dokploy bento compose deploy --composeId Qk8cbFjq6-ftleQZaXb-k
```

## Consequences

- Bulk Twenty mutations no longer need client-side throttle wrappers. The Python `time.sleep(0.7)` pattern in `/tmp/acces-work/mutate.py` (and similar batch scripts) becomes unnecessary; remove on next touch.
- The `twenty` CLI (`paperclip/templates/pharmia/cli/bin/twenty`) has no built-in throttle and now doesn't need one. If a future external (non-Bento) consumer ever uses our Twenty (currently impossible — instance is private), this ceiling would need re-evaluation.
- If a runaway agent loop hits the new ceiling, observability is via `loki bento search "throttle" --service twenty-server`. The token-bucket exception message is `Limit reached (N tokens per M ms)`.

## Related

- Twenty source: `packages/twenty-server/dist/engine/core-modules/twenty-config/config-variables.js` (defaults), `packages/twenty-server/dist/engine/api/common/common-query-runners/common-base-query-runner.service.js` (enforcement call site).
- 2026-06-12 backfill that triggered this: 88 Accès Pharma owners into Twenty (see `/tmp/acces-work/` ledger + `https://outline.pharmia.ca/doc/acces-pharma-69-priority-outreach-list-88-owners-b0jXhdWYvB`).
