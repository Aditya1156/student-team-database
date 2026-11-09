# Mahera module review — 9 November 2026

Source: `Mahera_Data_Dictionary_FinalLast5.xlsx`

Status: reviewed as a draft. No SQL has been created or deployed from this workbook.

## Interfaces that align

| Interface | Mahera definition | Related owner definition | Review result |
| --- | --- | --- | --- |
| Business user key | UUID references `core.users(user_id)` | Aditya uses UUID `user_id` as the shared key | Aligned |
| Accepted request provenance | `connections.created_from_request_id BIGINT` | Prajwal uses `connection_requests.id BIGINT` | Type aligned; transaction rules pending |
| Conversation parent | `connections.id BIGINT` | Rajath's `conversations.connection_id` follows `connections.id` | Aligned |
| Prompt reaction ownership | `(profile_prompt_id, target_user_id)` | Thanushree has BIGINT prompt `id` and UUID `user_id` | Types align; parent needs `UNIQUE (id, user_id)` |
| Marketing authority | reads `core.user_consents.user_id` | Aditya uses `user_id` and append-only consent history | Column aligned; precedence pending |
| Quiet hours | delegated to channel preference table | Thanushree defines quiet hours/timezone | Complementary; scheduler precedence pending |

## Candidate scope

Mahera's primary overview defines four tables and 49 columns:

- `core.notification_category_preferences` — 10 columns.
- `core.device_tokens` — 13 columns.
- `core.connections` — 13 columns.
- `core.relations` — 13 columns.

The workbook also requires three physical registry tables that are not fully defined in the Data Dictionary:

- `core.notification_categories`.
- `core.notification_category_channels`.
- `core.connection_closed_reasons`.

The Value Lists contain 38 unique preference categories, 3 channels, 4 token providers, 7 platform labels, 41 unique connection-close reasons, 4 relation reactions, 5 intended connection sources and 5 intended relation sources. Reference-only values must not be seeded as approved values.

## Required corrections and decisions

1. Add full dictionaries for all three registry tables: columns, PK/unique keys, labels, status/deprecation, priority, mandatory flag, consent requirement, user visibility, created/updated timestamps and seed ownership as applicable.
2. Define an authoritative mapping from Koushik's notification event types to Mahera's 38 delivery-preference categories and allowed channels. State whether `core.notifications` is an in-app inbox row or a general delivery command.
3. Document delivery precedence across Aditya consent, Thanushree master channel settings and quiet hours, Mahera category settings and snoozes, mandatory notices, verified destinations and available devices.
4. Create accepted requests and connections through one transactional routine. It must verify request status, canonicalize the same sender/recipient pair, copy/validate the source, consume the request once, and return the existing result on retry.
5. Define `paused`: who can pause/resume, whether it affects both users, timestamps/reasons and allowed transitions. If it is a per-user inbox preference, move it out of the pair-wide connection row.
6. Link closure to accountable actors. `closed_by_user_id` covers a participant, but admin/system closure needs an immutable staff/audit correlation. Define how a block closes or restricts connections and conversations.
7. Decide whether `last_interaction_at` and `interaction_count` are stored. If kept, define qualifying events, atomic updates, rebuild and reconciliation. Derived statistics are safer for the first synthetic pilot.
8. Separate or merge `core.relations` and Rajath's `core.acknowledgements`. If relations remain, define profile-wide versus prompt-specific reactions and whether mutuality is computed or stored.
9. Correct relation state consistency: `non_mutual_reason=action_declined` lacks a corresponding relation transition; hidden state has no timestamp; expired state needs an expiry rule. Prefer a view for `is_mutual` and reason.
10. Implement duplicate active relation rules with explicit indexes. A robust option is two partial unique indexes: one for `profile_prompt_id IS NULL`, another including a non-NULL prompt ID. Define idempotency scope and retention.
11. Complete the device-token encryption envelope: ciphertext/tag format, nonce and fingerprint lengths, key/algorithm version, authenticated context, rotation behavior and sender permissions. Expiry/reassignment requires controlled routines or jobs rather than a static CHECK alone.
12. Approve or remove proposed product values: priority periods, Web Push/WNS, 22 proposed close reasons, four reactions, retention and any `restricted` state.

## Cross-owner verification

| Owner | What to verify with Mahera |
| --- | --- |
| Aditya | Consent lookup and lifecycle-driven connection closure; backend caller identity contract |
| Thanushree | Master/category preference precedence, quiet hours, prompt composite key, stale device-token references |
| Prajwal | Accepted-request transaction, canonical pair, source copy, blocks and reconnection episodes |
| Koushik | Notification type/category mapping, payload contract, channel delivery and outbox event |
| Rajath | Conversation FK, disconnect/block behavior, interaction counter and relation/acknowledgement overlap |
| Tejaswini | Admin closure authority, safety reasons and audit visibility |
| Skanda | Event/audit records for connection lifecycle and notification delivery without leaking token data |

## Suggested pilot decisions for review

These are proposals, not approved requirements:

- Keep `connections` states `active` and `closed` for the first pilot; add `paused` only after its pair-wide semantics are approved.
- Derive relation mutuality and connection interaction statistics initially.
- Keep only approved source values; retain reference-only values in documentation.
- Use the three registries rather than large duplicated CHECK lists, after their schemas are completed.
- Make device-token and connection mutations available only through backend routines with trusted caller identity.

Mahera and the cross-module owners should record their decisions in a pull request using [OWNER_VERIFICATION.md](OWNER_VERIFICATION.md).
