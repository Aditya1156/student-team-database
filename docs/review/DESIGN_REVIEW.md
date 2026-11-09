# Database design review — 9 November 2026

Status update (9 November 2026): the team lead resolved the reconciliation items and authorized implementation without waiting for teammate sign-off. Seven migrations, deterministic catalog seeds, security rules, and synthetic review fixtures are deployed to `internship`. The detailed findings below are retained as the design audit trail; they are not current deployment blockers.

## Confirmed scope and working decisions

The team lead confirmed that the supplied workbooks are the current draft, teammates will review synthetic data and submit schema changes through GitHub, and a separate backend will handle application authentication. Mahera's workbook has now been supplied, so all eight team members are represented. The `internship` cloud project is for synthetic verification data at this stage.

One cloud database with `core`, `safety`, `analytics`, and `audit` schemas is a suitable integration structure. Schema names group responsibilities; database privileges and application authorization determine access. Team members should use individual reviewer identities; only the designated integrator applies reviewed migrations.

Text in the workbooks such as “rebuild from scratch”, “APPROVED”, “VERIFIED IN DATABASE”, and “Built + tested” is source material, not authorization to execute SQL or evidence of verification in this project. The user asked for review before creation. The workbooks refer to other reviews and SQL files that were not supplied; the lead has chosen to use these eight as the working draft.

## Verified current project

Read-only catalog inspection of linked project `internship` (`fivopskfqvgyyjzsvabx`) reports PostgreSQL **17.11**. Of the five inspected schemas, only `public` exists. There are **no tables, partitioned tables, views, or materialized views** in `public`, `core`, `safety`, `analytics`, or `audit`. Supabase's managed internal schemas are outside that statement.

The metadata query and result are saved as [schema-snapshot.sql](schema-snapshot.sql) and [live-schema-snapshot.json](live-schema-snapshot.json). No application data was read. Source claims about an existing database may refer to teammates' environments; their DDL still needs reconciliation here.

## Source inventory

All eight workbooks were extracted with sheet names, cell addresses, formulas and cached values, and SHA-256 source fingerprints. There are **78 worksheets**, including one empty worksheet. The embedded Thanushree ER diagram was also inspected. Mahera's workbook supplies the complete `device_tokens` definition that the diagram only referenced; the profile-media key conflict remains.

| Owner | Sheets | Tables in primary Tables overview | Main responsibility |
| --- | ---: | ---: | --- |
| Aditya | 18 | 7 | Accounts, identities, contacts, verification, OTPs, consents, lifecycle history |
| Thanushree | 9 | 9 | Interests, profiles, prompts, notification preferences, languages |
| Prajwal | 13 | 5 | Connection intents/requests, blocks, pseudonyms, profile media |
| Koushik | 7 | 5 | Notifications, outbox, account export/deletion jobs, job steps, media deletion |
| Rajath | 7 | 6 | Dismissals, acknowledgements, conversations, messages, read cursors, participants |
| Tejaswini | 5 | 6 | Reports, taxonomy pairs, moderation, appeals, legal holds, staff identities |
| Skanda | 11 | 4 | Analytics events/impressions, evidence, audit |
| Mahera | 8 | 4 primary + 3 supporting registries | Notification category preferences, device tokens, connections, relations |

The eight primary Tables overviews list **46 tables**. Mahera also requires three supporting registries—`core.notification_categories`, `core.notification_category_channels`, and `core.connection_closed_reasons`—bringing the current candidate scope to **49 physical tables**. This is still a draft count: the registries lack full row-by-row column dictionaries, undefined external entities remain, and owner decisions may remove or add scope. Tejaswini's taxonomy table is defined in `Main`, although absent from her `Data Dictionary` sheet. Some apparent columns in Skanda's dictionary are indexes or deprecated fields and must not become columns.

The [table inventory](table-inventory.csv), [column inventory](column-inventory.json), and [machine-readable workbook analysis](workbook-analysis.json) preserve draft counts. Counts of dictionary rows are not approved physical column counts.

## Findings that block a coherent schema

The resolutions below are proposals for owner review, not decisions already applied.

| ID | Finding and source | Proposed resolution | Owners |
| --- | --- | --- | --- |
| B01 | UUID user references target numeric `core.users.id` in Thanushree `Data Dictionary` rows 29, 42, 48, 56 and `Relationships` rows 7–13; Skanda has similar references. Aditya defines BIGINT `id` and UUID `user_id` separately (dictionary rows 5–6). | Retain the dual user keys and make every business-user reference target `core.users(user_id)` as UUID. Keep staff identities separate. | Aditya, Thanushree, Skanda |
| B02 | Prajwal defines `core.profile_media.media_id UUID` as the PK and no numeric `id` (dictionary row 44). Thanushree's `profiles.profile_media_id` and Koushik's deletion job reference BIGINT `profile_media(id)` (rows 37 and 63 respectively). | Prefer retaining the supplied UUID media key and changing both consumers to UUID references to `media_id`. Alternatively agree a dual-key media design explicitly. Enforce that a profile's selected media belongs to that same user and is eligible to display. | Prajwal, Thanushree, Koushik |
| B03 | Koushik's `outbox_events.id` is BIGINT (row 16); Skanda's `source_outbox_event_id` is UUID (dictionary row 12 and product_events row 50). | Make the analytics reference BIGINT to the outbox PK, or agree a separately unique UUID event key across producers and consumers. | Koushik, Skanda |
| B04 | Tejaswini's `reports.id` is BIGINT. Skanda's `Data Dictionary` row 45 says UUID for `report_id`, while his `report_evidence` row 5 already says BIGINT. | Adopt BIGINT `report_id -> safety.reports(id)` and remove the stale UUID definition. | Tejaswini, Skanda |
| B05 | Evidence review points to application users in Skanda's dictionary row 58; operational moderation uses `safety.admin_users.id BIGINT`. | Decide whether only staff can review evidence. If yes, use a clearly named BIGINT reviewer reference to `safety.admin_users(id)` with staff role/status checks. | Tejaswini, Skanda |
| B06 | Mahera now defines `core.connections.id BIGINT`, UUID canonical user pairs, and `created_from_request_id BIGINT`. These types align with Prajwal and Rajath. A simple FK still does not prove that the connection pair equals the request's sender/recipient, that the source matches, or that the request was accepted exactly once. | Create/accept the request and connection through one transactional routine. Validate canonical pair, accepted request, source, idempotency and one open connection episode. Define how blocks, disconnects and later reconnections affect conversations. | Mahera, Prajwal, Rajath |
| B07 | Skanda's `Data Dictionary` and dedicated table tabs describe different structures. `discovery_impressions` has 28 dictionary entries but only 9 dedicated-tab fields; the dictionary includes two non-column entries. Audit has 23 dictionary entries, including deprecated login flags, versus 6 different dedicated-tab fields (`audit_id`, `timestamp`, `event_type`, etc.). Evidence has 18 dictionary entries versus 13 dedicated-tab fields with new behavior snapshots. | Skanda must select one final definition for each of the four tables and reconcile names, types, optional fields, indexes, and retention behavior. | Skanda, lead |
| B08 | Analytics fields described as pseudonyms are also documented as direct FKs to `core.users(user_id)` (Skanda product_events row 35; discovery rows 7–10). Other sheets explicitly prohibit those direct links. | Define the telemetry identifier namespace and who can resolve it. Prefer purpose-specific pseudonyms with restricted mapping; do not merely rename a business user UUID. Decide whether Prajwal's public-facing aliases are suitable for this separate purpose. | Skanda, Prajwal, lead |
| B09 | No backend identity-to-business-user authorization contract is defined. The team chose separate backend authentication. | Specify backend connection role, trusted caller context, staff authorization, and how each operation checks the requesting user. Do not write `auth.uid() = user_id` policies without an authenticated JWT/mapping contract. | Lead, backend owner |
| B10 | Definitions disagree on user-link deletion behavior: Aditya says RESTRICT; Thanushree `user_languages` says CASCADE, device tokens are described as CASCADE, and Skanda uses SET NULL in some audit/reviewer links. | Adopt explicit per-reference deletion rules. Recommended baseline: user tombstones and RESTRICT on business-user links; erasure routines selectively remove eligible data and honor legal holds. Document any deliberate exception. | All owners |
| B11 | Mahera's `relations` requires the actor to be the authenticated user, while the team chose a separate backend and no trusted caller contract exists. The same issue applies to requests, messages, blocks and preferences. | Resolve B09 before exposing write routines. Backend routines must derive actor identity from trusted authentication context and ignore client-supplied actor IDs as authority. | Lead, backend owner, Mahera, all write-table owners |
| B12 | Mahera introduces three registries used by composite foreign keys but supplies no complete dictionary for their columns, keys, active/deprecated behavior, labels, priority or visibility. | Add complete definitions and deterministic seed sources for all three registries. Registry rows become governed reference data and must be versioned in migrations. | Mahera, lead |

## Other corrections and product decisions

| ID | Evidence | Required follow-up |
| --- | --- | --- |
| D01 | Thanushree `user_languages` is repeated at dictionary rows 98–111 and 123–136 (six duplicated column definitions). `prompt_catalogue` skips field number 3 and contains eight field definitions despite the nine-field overview. Mahera now supplies the authoritative `device_tokens` draft. | Deduplicate languages, supply the prompt question/text field, and remove stale Thanushree device-token relationship text in favor of Mahera's definition. Language selection must reference a language interest, not an arbitrary interest. |
| D02 | Thanushree profile visibility rule has a trailing comma in the proposed CHECK (row 36); some headings still count three states while only visible/hidden remain. City completeness says 25% in one description and 20% in the final formula. | Reconcile the two visibility states and the completeness formula. Recalculate completeness on relevant media/interest changes, not just profile updates. |
| D03 | Prompt answer contract requires `version` and `response`, but examples use structured fields without `response` (Thanushree row 50). `key_value` answers and configurable length up to 2,000 conflict with a blanket 500-character response limit. `prompt_code` examples/value lists contain labels with spaces instead of machine codes. | Define separate versioned JSON contracts by answer type, stable machine codes with separate labels, and exactly how prompt-specific limits apply. Keep prompt text in the catalogue. |
| D04 | `interests.intent` is described as a user's goal but stored on a shared catalogue row. The dictionary mentions three values, the catalog contains eight distinct nonempty values, and All Values has 88 curated intents. | Separate catalogue metadata from an individual user's intent. Decide MVP scope and the authoritative allowed set before seeding. Do not automatically create extra tables without scope approval. |
| D05 | Koushik notification dictionary lists `like/comment/follow/mention/reply`; Value Lists advertises 24 but contains 53 entries and 49 unique codes. Mahera separately proposes 38 preference categories and allowed category/channel pairs. These are different taxonomies with no mapping. | Define whether `notifications.notification_type` is an event subtype while Mahera's category controls delivery. Add an authoritative type-to-category/payload mapping, deduplicate Koushik's codes, and decide whether a notification row represents an in-app item or a multi-channel delivery request. |
| D06 | Rajath describes 80 acknowledgement subcategories in the dictionary (row 19), while Value Lists contains 90. Dismissal reasons advertise 50 but contain 49. Discovery sections have 30 values while the actual interest catalog has 11 categories. | Reconcile counts, validate category/subcategory pairs, and decide whether discovery sections are a separate taxonomy with a mapping. Do not compare them by label alone. |
| D07 | Tejaswini's appeal dictionary and Main SQL allow two final decision codes, but Value list contains 101 entries. Main SQL for reports omits several CHECKs described alongside it. Trigger names are documented without their implementation bodies. | Reconcile appeal taxonomy with the decision state machine; obtain or implement the missing checks and staff-validation triggers. A field description is not an executable rule. |
| D08 | In Tejaswini Main's appeal CHECK, comparisons such as `decision_reason_code = 'appeal_accepted'` can evaluate to NULL if the nullable code is absent. A PostgreSQL CHECK accepts NULL. | Require a non-NULL decision code explicitly for final decisions; test all state/NULL combinations. Review other nullable state rules and array elements for the same issue. |
| D09 | Prajwal has 110 seeded intents, but an Open Item says an earlier action list expected 100. Blocks have only 15 seeded reasons while an approved 50-code list is requested. Intent categories and connection-request categories are different taxonomies. | Approve the 110-intent scope and define valid request-category/intent combinations if required. Agree block behavior and report mappings with safety; do not use a block reason directly as a report category. |
| D10 | Rajath group chat, participant allocation, media/location/contact message types and history after disconnect/block remain open. Membership and send routines depend on these decisions even for direct chat. | Choose an MVP (recommended starting proposal: direct text/system chat), retain a clear participant permission model, and define block/disconnect history behavior before implementing sends. |
| D11 | Skanda proposes range/list partitioning while documenting primary/unique keys that omit partition keys. Monthly and weekly impression partition descriptions disagree. | Start unpartitioned for the pilot unless scale requires otherwise. If partitioning is approved, redesign keys and global deduplication deliberately; adding timestamps to a key changes uniqueness semantics. |
| D12 | Skanda's properties default is `{}` but a mandatory `schema_version` is also required. His change log moves interactions out of impressions while the dictionary retains interaction fields. Audit references `audit.audit_events`, a different table from the supplied `audit.audit_product_event`. | Reconcile JSON defaults, immutable event boundaries and audit table names. Permit only approved audit payload fields and decide retention/purge semantics. |
| D13 | Aditya allows optional DOB pending approval, but eligibility rules require DOB for eligible users. KYC attempt/provider limits and fields are explicitly open. PAN/Aadhaar hash key rotation and duplicate detection are not fully specified. | Resolve how synthetic age eligibility is demonstrated and which fields remain unused. Document key versions and cross-version duplicate checks before real integrations. Workbook legal claims are not independently established by this review. |
| D14 | Aditya keeps a globally unique `(provider, provider_subject)` identity and forbids reactivation of unlinked identities. OTP hash key version is not independently specified. A global contact version invalidates challenges across both channels, while reset wording refers to only the changed channel. | Define unlink/relink behavior, active-provider uniqueness versus history, OTP key rotation, and precisely which challenges/verification states reset after each contact change. Test concurrent OTP attempts. |
| D15 | Marketing preferences duplicate consent state. Thanushree has channel master switches/quiet hours, Mahera has category/channel preferences/snoozes, and Aditya has the legal marketing consent history. Account lifecycle, legal holds and worker jobs also span owners. | Treat consent history as legal authority, master switches as channel-level preference, and category rows as finer preference. Document precedence, missing-row semantics, mandatory-notice exceptions and delivery eligibility in one function/contract. Distinguish access-disabled/deleted status from completed erasure and make legal holds gate every applicable deletion path. |
| D16 | Supplied synthetic seeds use name slugs, old textual request/pseudonym IDs, comma-separated aliases, relative timestamps, readable media paths, and historical values inconsistent with the revised rules. Some dates are Excel numeric serials; timezone information must come from the source's stated convention. | Rebuild deterministic fixtures against finalized keys and rules. Never import the original seeds unchanged. Include separate success/failure fixtures rather than relying on insertion order to conceal inconsistent scenarios. |
| D17 | Skanda references a `recommendation_requests` parent, sessions and content entities; notification and job lists refer to posts, comments, groups and experiences. No complete definitions for these entities were supplied. | Classify each as an in-scope dependency, an external identifier with a documented contract, or a deferred feature. Do not invent tables or silently claim FK enforcement for undefined parents. |
| D18 | Mahera's connection status includes pair-wide `paused`, but no actor, pause reason, timestamps or resume transition are defined. Closure records a user actor, but admin/system closure does not identify the responsible staff member or correlation request. | Define the state machine and audit linkage. Decide whether pause is pair-wide or per-user; if per-user, move it to a participant preference. Preserve staff/system accountability through an admin reference or immutable audit correlation. |
| D19 | `connections.last_interaction_at` and `interaction_count` duplicate derived message/event aggregates and require synchronized cross-table updates. “Qualifying interaction” is undefined. | Prefer a derived/materialized statistic or define the exact qualifying events, transaction boundary, reconciliation job and rebuild procedure. Do not make messaging success depend on a fragile counter update. |
| D20 | Mahera's `relations` overlaps conceptually with Rajath's acknowledgements. `is_mutual` and `non_mutual_reason` are derived state; some reasons refer to decline even though relations have no declined status. Hidden/expired timestamp consistency is incomplete. | Product owners must separate the two features or merge them. Prefer computing mutuality and reason in a view. If stored, define qualifying reaction pairs, precedence, hidden/expiry timestamps and one transactional update path. |
| D21 | The proposed relation uniqueness expression uses `COALESCE(profile_prompt_id, 0)` and an active-row predicate. It needs an explicit constraint/index design and idempotency scope. | Use a named expression-based partial unique index only after confirming zero can never be a prompt ID, or use separate partial indexes for prompt-specific and profile-wide reactions. Define idempotency client/operation scope and retention. |
| D22 | Mahera's device-token model is strong in intent but lacks authenticated-encryption binding details and a complete lifecycle rule. “Expired” depends on time, which a static CHECK cannot automatically update. Same-token reassignment across users must be atomic. | Define ciphertext envelope/version, authentication tag and additional authenticated data (at least provider/platform/key context); validate byte lengths. Use controlled routines/jobs for expiry and reassignment, test key rotation, and approve retention. |
| D23 | Mahera says a missing category preference means enabled, while marketing and master channel defaults elsewhere are disabled. Mandatory notices also depend on having a verified destination/device and may use channels outside the allowed pair. | Document precedence explicitly: legal consent and destination eligibility, mandatory policy, master channel preference, category preference, quiet hours/snooze and delivery fallback. “Cannot disable” must not imply guaranteed delivery. |

## Catalog checks completed

These are workbook consistency checks, not tests against deployed tables.

- Interest Catalog: **962 rows**, **11 categories**, **60 category/subcategory pairs**. No duplicate interest slug or duplicate label within the same category/subcategory; longest slug is 73 characters. Identical labels across different subcategories are permitted by the proposed scoped uniqueness.
- Thanushree All Values: **962 interests, 88 intents, 100 prompt labels, 35 bios, 217 prompt-block codes**. Prompt labels still require stable code mapping. Descriptive grouping rows must not be inserted as values.
- Prajwal Seed Intents: **110 entries** in groups of **50 / 30 / 10 / 10 / 10**; no duplicate intent code, label, or category/sort-order pair.
- Mahera Value Lists: **38 unique notification categories**, **3 channels**, **4 token providers**, **7 platform labels**, **41 unique connection-close reasons**, and **4 relation reactions**. The workbook distinguishes approved values from reference-only/proposed values; only five connection sources and five relation sources are intended as the current draft.
- Safety Approved Taxonomy: **219 unique category/subcategory pairs**, **27 categories**, **217 distinct subcategory strings**. Repeated subcategory strings in different categories are why the composite key is necessary. `reports.category` still needs independent validation when subcategory is NULL.
- Skanda, notification, acknowledgement, profile, and safety lists have internal conflicts described above; none has been silently selected as final authority.

## Proposed implementation order

After corrections and owner confirmation, prepare one coherent migration series in dependency order:

1. Schemas, database roles, basic helper functions, core users and identity child tables; keep backend/client access closed until authorization is defined.
2. Independent registries: interest categories/subcategories/interests, prompt catalogue, connection intents, Mahera's three notification/closure registries, staff identities, safety taxonomy.
3. Profiles, interests/languages/prompts/preferences, pseudonyms and media, using the agreed media key. If references form a cycle, create base tables first and add the final foreign keys afterward.
4. Blocks, requests and connections; accepted-request integration, canonical pair validation, lifecycle and block rules.
5. Conversations/participants/messages/read cursors and discovery/acknowledgements.
6. Reports, moderation, appeals, legal holds and evidence; ensure legal-hold dependencies exist before erasure routines.
7. Outbox, notifications and data jobs; analytics after its agreed outbox/pseudonym parents. Audit can be created earlier if needed by routines, after selecting its final shape.
8. Transactional service routines, views, role grants, RLS where used, retention/worker behavior and deterministic synthetic seed data. Jobs are activated only after manual verification.

The exact file sequence will follow a dependency graph of the corrected schema. This is a plan, not a set of SQL migrations ready to deploy.

## Team verification and sharing

Use the GitHub repository as the shared definition of the database. Owners review their table definitions and cross-module interfaces in pull requests. The lead/integrator applies approved migrations to the one shared project. Do not make competing manual schema edits in the SQL Editor.

Provide each teammate an individual read-only route to approved synthetic review tables/views. A custom PostgreSQL reviewer role can have schema USAGE and SELECT on specific review views, with no DDL, mutation, or privileged routine execution. Verify effective privileges after setup. Do not distribute the project-owner password or service-role key. Service-role credentials bypass RLS and are not reviewer credentials. Supabase dashboard Read-Only membership is plan-dependent; the official documentation currently limits Read-Only and No-access roles to Team/Enterprise. Confirm the project's plan before choosing that route.

The separate backend needs its own narrowly scoped execution contract. Routines must derive the caller from a trusted authenticated context and check user/staff permission; a client-supplied user ID or actor type is not authority. Database administrator access, application staff permissions and student reviewer access are three separate concerns.

Run schema and write tests in an isolated PostgreSQL/Supabase environment on a CI runner; the laptops do not need Docker. Use a full Supabase test environment where policies/routines depend on Supabase-specific features. Shared-cloud review queries should be read-only. Tests should cover:

- Rebuilding all migrations from an empty database, correct keys/types, defaults, indexes and every intended FK target.
- Valid and invalid state transitions, required timestamps, NULL edge cases, append-only history and unauthorized writes.
- Two-user authorization, staff role/status checks and reviewer inability to mutate or execute privileged functions.
- OTP attempts/resends/contact changes, concurrent request acceptance, unique conversation ordering, idempotent workers and lease recovery.
- Media ownership/approval, message membership/replies/cursors, blocks and legal-hold prevention of applicable erasure.
- Deterministic catalog counts and valid pairings. Fixtures deliberately distinguish synthetic approved KYC from external verification.

Each owner records the reviewed commit, test evidence and any remaining issue IDs. Verification is complete only when module and cross-module owners agree on the same deployed migration version.

## Owner handoff

| Owner | First review tasks |
| --- | --- |
| Aditya / lead | Confirm UUID identity interface, lifecycle/erasure ordering, backend authorization contract, OTP limits, consent synchronization and open KYC fields. |
| Thanushree | Fix users FKs, deduplicate languages, finalize device scope, prompt text/codes/JSON and media reference. |
| Prajwal | Finalize media key, block/report mapping, request-intent rules, pseudonym purpose and deterministic seed conversion. |
| Koushik | Align media/outbox keys, approve notification registry, specify job/lease/idempotency and erasure event contracts. |
| Rajath | Confirm chat scope, connection integration, membership/send rules, acknowledge pair taxonomy and discovery categories. |
| Tejaswini | Reconcile Main SQL with documented constraints, appeal codes/NULL checks, staff authorization, taxonomy and legal-hold enforcement. |
| Skanda | Supply one coherent definition per table; resolve identity namespaces, audit layout, evidence types/reviewer, outbox key and partitioning scope. |
| Mahera | Supply full registry dictionaries; resolve notification mapping/precedence, connection pause/closure/audit rules, relation overlap/derived state and device-token lifecycle. Coordinate accepted-request and conversation behavior. |

## Remaining decisions before migration implementation

1. Have owners resolve B01–B12 and select authoritative versions of conflicting sheets. Mahera closes the missing connection-type dependency but introduces three registries that still need complete definitions.
2. Choose direct-chat/message scope, telemetry identity model, notification architecture and the final value registries; close the applicable D-items.
3. Document the backend connection/authentication model and reviewer access route. Synthetic data does not remove the need to test access restrictions.
4. Review the resulting consolidated schema and isolated-test results; then deploy to the shared verification project and collect each owner's sign-off.

## Technical references checked

- [PostgreSQL 17 constraints](https://www.postgresql.org/docs/17/ddl-constraints.html): CHECK constraints accept true or NULL, and are not a substitute for cross-row constraints.
- [PostgreSQL 17 partitioning](https://www.postgresql.org/docs/17/ddl-partitioning.html): partitioned primary/unique constraints must include partition-key columns.
- [Supabase row-level security](https://supabase.com/docs/guides/database/postgres/row-level-security): authenticated identity context, grants and policies; privileged roles can bypass RLS.
- [Supabase access control](https://supabase.com/docs/guides/platform/access-control): available dashboard roles and plan restrictions.
- [Supabase database migrations](https://supabase.com/docs/guides/local-development/database-migrations): versioned changes and shared deployment workflow.

Legal statements and regulatory conclusions quoted in the source workbooks have not been independently approved or verified here. At this stage the team has explicitly selected synthetic data only.
