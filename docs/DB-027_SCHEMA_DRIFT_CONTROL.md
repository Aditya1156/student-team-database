# DB-027 — Constraint documentation drift control

The executable source of truth is `supabase/migrations`. The approved review
artifacts are `docs/Team_Database_Complete_Design.xlsx` and
`docs/schema-catalog-approved.json`.

For every schema-changing pull request, CI starts a clean Supabase database,
applies every migration, regenerates the workbook, reads PostgreSQL metadata
from `pg_catalog`, and compares the result with the approved catalog snapshot.
The build fails when a table, column, constraint, foreign key, or index is
missing, renamed, or has a changed definition.

## Developer commands

```text
npm run docs:team
npm run schema:drift:remote
```

Only after the DBA and module owners approve an intentional schema change:

```text
npm run schema:approve:remote
```

Commit the migration, regenerated workbook, and changed JSON snapshot together.
Never approve a snapshot merely to make CI green; reviewers must verify the
catalog diff and the migration on a clean database first.
