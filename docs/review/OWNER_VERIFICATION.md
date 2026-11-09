# Owner verification record

Use one copy of this record per module in a pull request. Leave items pending until evidence exists. This template does not indicate that the schema has been created or verified.

Owner:

Module and tables:

Reviewed commit:

Source workbook/version:

Migration versions tested:

Cross-module reviewers:

## Definition review

- [ ] Table scope and authoritative sheet versions are agreed.
- [ ] Every column has an agreed type, nullability, default and purpose.
- [ ] PKs, unique keys, FK targets/types and deletion behavior match parent modules.
- [ ] Allowed codes, category/subcategory pairs and JSON payload contracts are agreed.
- [ ] State transitions and associated timestamp/NULL rules are defined.
- [ ] Relevant issue IDs in DESIGN_REVIEW.md have resolutions recorded in the PR.
- [ ] Backend permissions, student reviewer permissions and staff roles are distinct.
- [ ] Retention, legal holds, soft deletion and erasure responsibilities are agreed.

## Isolated test evidence

- [ ] All migrations build from an empty test database.
- [ ] Valid synthetic operations succeed and invalid operations fail as intended.
- [ ] Authorization checks deny another user's operations and unauthorized staff actions.
- [ ] Reviewer credentials cannot mutate data/schema or execute privileged routines.
- [ ] Relevant concurrency, retry, idempotency and lifecycle tests pass.
- [ ] Synthetic catalog fixtures match the approved counts and key formats.

Evidence links / results:

## Shared database review

- [ ] The lead deployed the reviewed migration versions.
- [ ] Read-only schema checks match the approved definition.
- [ ] Synthetic data demonstrates the module and cross-module relationships.
- [ ] Remaining limitations are recorded with owners.

Open issues:

Owner decision: pending / accepted / changes requested

Cross-module owner decisions:

Lead decision:
