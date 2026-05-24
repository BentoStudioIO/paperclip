# AGENTS.md — `packages/db/`

Drizzle schema, migrations, runtime config, and DB clients. One file per
table under `src/schema/`; everything else (clients, migrate runner, seed,
runtime-config) lives at the top level.

## 1. Schema invariants

- **`companyId notNull` on every operational table.** Every row belongs to
  exactly one company. Cross-company FK lookups never happen. Authority:
  `src/schema/companies.ts` (the parent), and any operational table such as
  `src/schema/issues.ts:25` (`companyId: uuid("company_id").notNull()
  .references(() => companies.id)`).
- **One file per table.** Don't merge related tables into one file; the
  generator and the IDE both depend on the 1:1 mapping.
- **Index naming convention.** Snake_case, prefixed with the table name and
  suffixed `_idx` (or `_uq` for unique). Example: `issue_tree_hold_members
  _hold_issue_uq` in `src/schema/issue_tree_hold_members.ts:29`.
- **`(companyId, ...)` index pattern.** Composite indexes on operational
  tables always lead with `companyId` so single-company scans use the index.
  Example: `cost_events_company_occurred_idx` on `(companyId, occurredAt)`
  in `src/schema/cost_events.ts:32`.

## 2. FK delete ordering

Not every FK uses `onDelete: "cascade"`. When the parent is deleted in a
transaction, child rows that reference it via a no-action FK must be
deleted first or the transaction fails.

Known orderings (parent → must-delete-children-first):

- **agent** → `cost_events` (scoped to the agent's heartbeat runs) BEFORE
  `heartbeat_runs`. Fixed in commit `b34d1b6a` (May 2026). The
  `cost_events.heartbeat_run_id` FK has no cascade
  (`src/schema/cost_events.ts:17`), so deleting `heartbeat_runs` first
  blows up with `cost_events_heartbeat_run_id_heartbeat_runs_id_fk`.
  Implementation lives in `server/src/services/agents.ts` (transaction
  around line 518). When adding any new table that references
  `heartbeat_runs` without cascade, extend that transaction too.
- **issue_tree_holds** → `issue_tree_hold_members` BEFORE the parent (the
  members FK at `src/schema/issue_tree_hold_members.ts:13` does cascade,
  but external services may pre-delete members for audit; either is fine
  as long as the order is consistent).

If you add a new FK without cascade, add a row to this list and update the
relevant service-layer transaction.

## 3. Migration workflow

**Never hand-write SQL migrations.** The generator pipeline is:

```
pnpm db:generate "migration name"   # from repo root, or pnpm generate in this package
```

What it does (see `package.json` scripts):

1. `check:migrations` — `tsx src/check-migration-numbering.ts`. Gates the
   build/typecheck/generate scripts; rejects out-of-order or duplicate
   migration numbers.
2. `tsc -p tsconfig.json` — compiles `src/schema/*.ts` into
   `dist/schema/*.js` (drizzle-kit reads the compiled JS, not the TS).
3. `drizzle-kit generate` — diffs the compiled schema against the latest
   migration and writes a new `src/migrations/NNNN_*.sql` plus the
   `meta/_journal.json` entry.

Apply with `pnpm db:migrate`; both `migrate` and `build` re-run
`check:migrations` first so a broken numbering breaks the whole pipeline.

Workflow checklist when changing a table:

1. Edit `src/schema/<table>.ts`.
2. Export the new table from `src/schema/index.ts` if new.
3. `pnpm db:generate "<descriptive-name>"`.
4. Inspect the generated SQL — never edit hand-rolled SQL, but reading it
   catches schema mistakes early.
5. `pnpm -r typecheck` from the repo root.

## 4. PGlite vs Postgres parity

Dev defaults to embedded PGlite (via `embedded-postgres` package; see
`src/runtime-config.ts:114` for the `database.mode === "pglite"` branch).
Production runs real Postgres.

Known divergences:

- PGlite is a single-process embedded build; concurrent connections behave
  differently than a real pool. Don't rely on lock semantics that only hold
  under a connection pool.
- Some Postgres extensions are missing or stubbed in PGlite. If a query
  needs an extension, gate it behind a runtime check.

Tests should run against both modes when behavior depends on transaction
isolation, advisory locks, or extension features. Default to PGlite for
speed; opt into a real Postgres container only when the feature requires it.

## 5. Adding a new operational table — checklist

1. Create `src/schema/<table>.ts` with `companyId.notNull().references(() =>
   companies.id)` as the first FK.
2. Decide `onDelete:` for every FK. If not cascade, document the required
   pre-delete order in §2 above AND extend the relevant service
   transaction in `server/src/services/`.
3. Add at least one composite index leading with `companyId` if the table
   is queried per-company.
4. Export from `src/schema/index.ts`.
5. Run `pnpm db:generate "add <table>"` and verify the generated SQL.
6. Add at minimum a smoke test that inserts and selects scoped by
   `companyId`.
