import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ExcelJS from 'exceljs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const migrationName = '20261110100000_identity_lifecycle_completion.sql';
const migrationPath = path.join(root, 'supabase', 'migrations', migrationName);
const migrationSql = fs.readFileSync(migrationPath, 'utf8');
const hardeningName = '20261111100000_aditya_gap_hardening.sql';
const hardeningSql = fs.readFileSync(path.join(root, 'supabase', 'migrations', hardeningName), 'utf8');
const output = path.join(root, 'docs', 'Aditya_Auth_Session_and_Policy_Version_Review.xlsx');

const colors = {
  navy: '17365D', blue: '1F4E78', teal: '0F6B78', green: '2E7D32', amber: 'C65911',
  red: 'C00000', purple: '7030A0', gray: '666666', white: 'FFFFFF', black: '1F1F1F',
  paleBlue: 'EAF3F8', lightBlue: 'D9EAF7', lightGreen: 'E2F0D9',
  lightAmber: 'FCE4D6', lightRed: 'F4CCCC', changeYellow: 'FFFF00'
};

const changeMarkers = [
  hardeningName,
  'implemented and hardened',
  'composite identity ownership',
  'bounded expiry',
  'rotation-state consistency',
  'one-row rotation',
  'same session user',
  'cannot exceed absolute expiry',
  'auth_sessions_identity_owner_fk',
  'auth_sessions_identity_owner_ix',
  'auth_sessions_idle_within_absolute_ck',
  'auth_sessions_rotation_state_ck',
  'non-overlapping effective periods',
  'policy_versions_no_effective_overlap_excl',
  'controlled publish/retire',
  'publish_policy_version',
  'retire_policy_version',
  'currently effective versions'
];

function highlightChangedRows(ws, headerRow = 4) {
  for (let rowNo = headerRow + 1; rowNo <= ws.rowCount; rowNo += 1) {
    const row = ws.getRow(rowNo);
    const text = row.values.slice(1).map(value => String(value ?? '')).join(' ').toLowerCase();
    if (!changeMarkers.some(marker => text.includes(marker.toLowerCase()))) continue;
    row.eachCell({ includeEmpty: true }, cell => {
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.changeYellow}` } };
      cell.font = { ...(cell.font ?? {}), color: { argb: `FF${colors.black}` } };
    });
  }
}

function extractCreate(table) {
  const escaped = table.replace('.', '\\.');
  const match = migrationSql.match(new RegExp(`create table ${escaped} \\([\\s\\S]*?\\n\\);`, 'i'));
  if (!match) throw new Error(`CREATE TABLE not found: ${table}`);
  return match[0].trim();
}

const workbook = new ExcelJS.Workbook();
workbook.creator = 'Aditya / Student Enterprise Database Team';
workbook.lastModifiedBy = 'OpenAI Codex';
workbook.created = new Date('2026-11-11T00:00:00+05:30');
workbook.modified = new Date('2026-11-11T00:00:00+05:30');
workbook.title = 'Aditya Supporting Tables Review';
workbook.subject = 'Detailed review of core.auth_sessions and core.policy_versions';
workbook.description = 'Columns, values, constraints, relationships, use cases, DDL, tests, ownership, and tech-lead decisions.';

function border() {
  return {
    top: { style: 'thin', color: { argb: 'FFD0D7DE' } }, left: { style: 'thin', color: { argb: 'FFD0D7DE' } },
    bottom: { style: 'thin', color: { argb: 'FFD0D7DE' } }, right: { style: 'thin', color: { argb: 'FFD0D7DE' } }
  };
}

function title(ws, heading, subtitle, lastColumn, color = colors.navy) {
  ws.mergeCells(1, 1, 1, lastColumn);
  ws.getCell(1, 1).value = heading;
  ws.getCell(1, 1).font = { name: 'Aptos Display', size: 20, bold: true, color: { argb: `FF${colors.white}` } };
  ws.getCell(1, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${color}` } };
  ws.getCell(1, 1).alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(1).height = 34;
  ws.mergeCells(2, 1, 2, lastColumn);
  ws.getCell(2, 1).value = subtitle;
  ws.getCell(2, 1).font = { name: 'Aptos', size: 10, italic: true, color: { argb: `FF${colors.gray}` } };
  ws.getCell(2, 1).alignment = { vertical: 'middle', wrapText: true };
  ws.getRow(2).height = 30;
}

function styleGrid(ws, headerRow, color) {
  ws.getRow(headerRow).height = 30;
  ws.getRow(headerRow).eachCell(cell => {
    cell.font = { name: 'Aptos', size: 10, bold: true, color: { argb: `FF${colors.white}` } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${color}` } };
    cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
    cell.border = border();
  });
  for (let row = headerRow + 1; row <= ws.rowCount; row += 1) {
    ws.getRow(row).eachCell({ includeEmpty: true }, cell => {
      cell.font = { name: 'Aptos', size: 10, color: { argb: `FF${colors.black}` } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${row % 2 ? colors.white : colors.paleBlue}` } };
      cell.alignment = { vertical: 'top', wrapText: true };
      cell.border = border();
    });
  }
  ws.views = [{ state: 'frozen', ySplit: headerRow }];
  ws.autoFilter = { from: { row: headerRow, column: 1 }, to: { row: headerRow, column: ws.columnCount } };
  ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0, paperSize: 9, margins: { left: 0.2, right: 0.2, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 } };
  ws.headerFooter.oddFooter = '&LAditya Supporting Tables&CPage &P of &N&R11 Nov 2026';
}

function grid(name, heading, subtitle, headers, rows, widths, color = colors.blue) {
  const ws = workbook.addWorksheet(name, { properties: { tabColor: { argb: `FF${color}` } } });
  title(ws, heading, subtitle, headers.length, color);
  ws.addRow([]); ws.addRow(headers); rows.forEach(row => ws.addRow(row));
  widths.forEach((width, index) => { ws.getColumn(index + 1).width = width; });
  styleGrid(ws, 4, color);
  return ws;
}

const summaryRows = [
  ['core.auth_sessions', 'Added for Aditya Question 5', 'Separate backend authentication needs session and refresh-token state.', 'Aditya owns schema; backend authentication developer operates it.', 'Implemented and hardened: composite identity ownership, bounded expiry, and rotation-state consistency.'],
  ['core.policy_versions', 'Added for Aditya Question 8', 'Consent needs an exact immutable policy document/version reference.', 'Aditya owns schema; product/tech/legal policy owner supplies approved content.', 'Implemented and hardened: non-overlapping effective periods and controlled publish/retire functions.']
];

const sessionColumns = [
  ['session_id', 'uuid', 'PK; random UUID', '43894e7b-71cb-4406-b0a3-19d9fbca0201', 'Identifies one login session on one browser/device.', 'Created by database.'],
  ['session_family_id', 'uuid', 'Required; random UUID', '9a6b1140-dc12-4789-ac38-d10004a798e1', 'Stable lineage identifier for family-wide compromise handling.', 'The implemented model keeps one row per login and rotates its digest; family ID is reserved for lineage/future history.'],
  ['user_id', 'uuid', 'Required FK → core.users(user_id)', 'User business UUID', 'Account that owns the session.', 'Delete restricted.'],
  ['auth_identity_id', 'bigint', 'Required FK → core.auth_identities(id)', '25', 'Email OTP, phone OTP, Google, or Apple identity used for login.', 'Must belong to the same user and be active when issuing session.'],
  ['refresh_token_hash', 'bytea', 'Required; unique; exactly 32 bytes', '<32-byte SHA-256/HMAC digest>', 'Protected representation of the refresh token.', 'Plaintext refresh token must never be stored.'],
  ['refresh_token_version', 'integer', 'Required; default 1; minimum 1', '1 → 2 → 3', 'Counts successful refresh-token rotations.', 'Incremented during rotation.'],
  ['device_id', 'varchar(100)', 'Optional', 'android-installation-001', 'Identifies the device/application installation for session management.', 'Not a push token; push tokens use core.device_tokens.'],
  ['ip_hmac', 'bytea', 'Optional; exactly 32 bytes', '<32-byte HMAC>', 'Protected IP representation for security comparison.', 'Secret key remains in backend secret manager.'],
  ['user_agent_hash', 'bytea', 'Optional; exactly 32 bytes', '<32-byte hash>', 'Protected browser/device-agent representation.', 'Original user-agent is not required in this table.'],
  ['status', 'text', 'Required; default active', 'active', 'Current session lifecycle state.', 'Allowed: active, revoked, expired, compromised.'],
  ['created_at', 'timestamptz', 'Required; database time', '2026-11-11 10:00:00+05:30', 'When login session was issued.', 'Security decisions use server time.'],
  ['last_seen_at', 'timestamptz', 'Required; database time', '2026-11-11 15:00:00+05:30', 'Last refresh/session activity recorded by database.', 'Current implementation updates during token rotation, not every API call.'],
  ['expires_at', 'timestamptz', 'Required; after created_at', 'Creation + 30 days', 'Absolute session lifetime.', 'Cannot be extended beyond chosen absolute lifetime without a new login.'],
  ['idle_expires_at', 'timestamptz', 'Required; after created_at', 'Last refresh + up to 7 days', 'Ends a session after inactivity.', 'Rotation extends it, never beyond expires_at.'],
  ['revoked_at', 'timestamptz', 'Conditional', 'Logout/security event time', 'When the session became non-active.', 'NULL for active; required for revoked/expired/compromised.'],
  ['revocation_reason', 'text', 'Conditional', 'user_logout', 'Why the session became non-active.', 'NULL for active; required otherwise; value list not currently constrained.'],
  ['replaced_at', 'timestamptz', 'Optional', 'Latest rotation time', 'When the refresh-token hash was most recently replaced.', 'Possible clearer name: refresh_token_rotated_at.'],
  ['updated_at', 'timestamptz', 'Required; database time', 'Latest update time', 'Last session-row modification time.', 'Updated during rotation/revocation.']
];

const sessionValues = [
  ['status', 'active', 'Session may be used only if both expiry timestamps, account, and identity are also valid.', 'revoked_at and revocation_reason must be NULL.'],
  ['status', 'revoked', 'Session was deliberately cancelled.', 'revoked_at and revocation_reason required.'],
  ['status', 'expired', 'Session exceeded absolute or idle lifetime.', 'Validation rejects expired timestamps even if a cleanup worker has not yet changed stored status.'],
  ['status', 'compromised', 'Wrong/old refresh-token hash indicates possible token reuse or theft.', 'Current implementation marks the active family compromised.'],
  ['revocation_reason', 'user_logout', 'User logs out one device.', 'Generated by revoke-one function default.'],
  ['revocation_reason', 'security_event', 'Backend/security team revokes all user sessions.', 'Generated by revoke-all function default.'],
  ['revocation_reason', 'account_recovery', 'Successful recovery OTP revokes previous sessions.', 'Automatic recovery behavior.'],
  ['revocation_reason', 'refresh_token_reuse', 'Submitted current hash does not match stored current hash.', 'Marks session/family compromised.'],
  ['revocation_reason', 'account_suspended / account_deactivated / account_deletion_pending / account_deleted', 'Account enters a blocked lifecycle state.', 'Automatic lifecycle trigger.'],
  ['revocation_reason', 'identity_unlinked / identity_revoked', 'Authentication provider identity becomes non-active.', 'Automatic identity trigger.']
];

const sessionConstraints = [
  ['Primary key', 'session_id', 'auth_sessions_pkey', 'One unique session row.'],
  ['Foreign key', 'user_id → core.users(user_id)', 'Generated FK', 'Session must belong to an existing application user; delete restricted.'],
  ['Foreign key', 'auth_identity_id → core.auth_identities(id)', 'Generated FK', 'Session must reference an existing authentication identity; delete restricted.'],
  ['Unique', 'refresh_token_hash', 'auth_sessions_token_uq', 'Same digest cannot be used by two session rows.'],
  ['CHECK', 'octet_length(refresh_token_hash)=32', 'auth_sessions_token_hash_ck', 'Only 32-byte refresh digest.'],
  ['CHECK', 'ip_hmac NULL or 32 bytes', 'auth_sessions_ip_hash_ck', 'Protected IP has fixed length.'],
  ['CHECK', 'user_agent_hash NULL or 32 bytes', 'auth_sessions_agent_hash_ck', 'Protected user-agent has fixed length.'],
  ['CHECK', 'refresh_token_version >= 1', 'auth_sessions_version_ck', 'Rotation version never zero/negative.'],
  ['CHECK', 'status in active/revoked/expired/compromised', 'auth_sessions_status_ck', 'Only approved state values.'],
  ['CHECK', 'expiry and last-seen ordering', 'auth_sessions_time_ck', 'Expiry after creation; last-seen not before creation.'],
  ['Composite FK', '(auth_identity_id,user_id) → core.auth_identities(id,user_id)', 'auth_sessions_identity_owner_fk', 'Proves the selected identity belongs to the same session user.'],
  ['CHECK', 'idle_expires_at <= expires_at and last_seen_at <= expires_at', 'auth_sessions_idle_within_absolute_ck', 'Idle/observed activity cannot exceed absolute lifetime.'],
  ['CHECK', 'version 1 has no replaced_at; later versions require it', 'auth_sessions_rotation_state_ck', 'Rotation counter and timestamp remain consistent.'],
  ['Index', 'auth_identity_id,user_id,status', 'auth_sessions_identity_owner_ix', 'Supports ownership and identity-session revocation lookup.'],
  ['CHECK', 'active has no revocation data; non-active requires it', 'auth_sessions_revocation_ck', 'Status and audit fields remain consistent.'],
  ['Index', 'user_id, status, expires_at', 'auth_sessions_user_status_ix', 'Fast user-session listing and expiry lookup.'],
  ['Index', 'session_family_id', 'auth_sessions_family_ix', 'Fast family-wide compromise/revocation.'],
  ['RLS/privilege', 'RLS enabled; anon/authenticated denied; service_role allowed', 'Migration security', 'Only trusted backend operates sessions.']
];

const sessionUseCases = [
  ['New login', 'User completes email/phone/Google/Apple authentication.', 'Backend generates access token and refresh token; stores only refresh hash through issue function.', 'One active session row.'],
  ['Five-day laptop usage', 'User closes/reopens app several times.', 'Same login session continues; refresh token obtains many short-lived access tokens.', 'No new database session every ten minutes.'],
  ['Refresh rotation', 'Access token expires.', 'Backend checks current refresh hash, stores new hash, increments version, extends idle expiry.', 'Old refresh token becomes invalid.'],
  ['Old token reused', 'An older/copied refresh token is submitted.', 'Hash mismatch marks session/family compromised.', 'User must authenticate again.'],
  ['Logout one device', 'User clicks logout on laptop.', 'Revoke that session only.', 'Phone session may remain active.'],
  ['Logout all devices', 'User selects logout everywhere or security team acts.', 'Revoke all active sessions for user.', 'All devices require login.'],
  ['Account recovery', 'Recovery OTP succeeds.', 'Automatically revoke all old active sessions.', 'Stolen sessions cannot continue.'],
  ['Suspension/deactivation/deletion', 'Account enters blocked status.', 'Lifecycle trigger revokes active sessions.', 'Blocked user cannot continue using refresh token.'],
  ['Identity unlinked', 'Google/Apple/OTP identity becomes unlinked/revoked.', 'Sessions issued through that identity are revoked.', 'Other identity sessions depend on product policy.'],
  ['Expiry', 'Absolute or idle time passes.', 'Validation rejects the session; worker may persist status=expired.', 'Reauthentication required.']
];

const policyColumns = [
  ['consent_type', 'text', 'Required; composite PK', 'privacy_notice', 'Identifies Terms, Privacy, KYC, or Marketing policy.', 'Allowed controlled values.'],
  ['policy_version', 'text', 'Required; composite PK', 'v1.0 / v1.1 / v2.0', 'Stable identifier for one exact policy document.', 'Must match vN.N format.'],
  ['content_sha256', 'bytea', 'Required; exactly 32 bytes', '<SHA-256 document fingerprint>', 'Proves which exact document content the version represents.', 'Any document-content change produces a different hash.'],
  ['document_uri', 'text', 'Required; HTTPS', 'https://policies.example.com/privacy/v1.0', 'Permanent location of versioned policy document.', 'Should not silently change content at same URI.'],
  ['published_at', 'timestamptz', 'Required', '2026-01-01 00:00:00+00', 'When the version was officially published.', 'Must not be after effective_at.'],
  ['effective_at', 'timestamptz', 'Required', '2026-01-15 00:00:00+00', 'When this version begins applying.', 'At or after published_at.'],
  ['retired_at', 'timestamptz', 'Optional', 'NULL while current', 'When the version stops being current/available for new acceptance.', 'When present, after effective_at.'],
  ['created_at', 'timestamptz', 'Required; database time', 'Insertion time', 'When catalogue record was stored.', 'Different from publication/effective time.']
];

const policyValues = [
  ['consent_type', 'terms_of_service', 'Rules and contractual terms for using the application.', 'Required for main-app access.'],
  ['consent_type', 'privacy_notice', 'How personal data is collected and handled.', 'Required for main-app access.'],
  ['consent_type', 'kyc_verification', 'Permission and notice for Aadhaar/PAN verification processing.', 'Required before KYC starts and for main access.'],
  ['consent_type', 'marketing', 'Optional marketing communication consent.', 'Withdrawal must stop optional marketing.'],
  ['policy_version', 'v1.0', 'Initial approved version.', 'Exact meaning determined by URI and content hash.'],
  ['policy_version', 'v1.1', 'Minor approved revision.', 'Old v1.0 remains immutable.'],
  ['policy_version', 'v2.0', 'Major approved revision.', 'Backend may require re-consent.'],
  ['retired_at', 'NULL', 'Version is not retired.', 'Does not alone prove it is the only current version; policy governance must define selection.'],
  ['retired_at', 'Timestamp', 'Version is no longer current for new acceptance.', 'Historical user consent remains linked to it.']
];

const policyConstraints = [
  ['Composite primary key', 'consent_type + policy_version', 'policy_versions_pkey', 'One row per policy type/version pair.'],
  ['CHECK', 'approved consent types only', 'policy_versions_type_ck', 'Terms, Privacy, KYC, Marketing.'],
  ['CHECK', 'policy_version matches ^vN.N$', 'policy_versions_version_ck', 'Consistent machine-readable version format.'],
  ['CHECK', 'content_sha256 exactly 32 bytes', 'policy_versions_hash_ck', 'Valid SHA-256 fingerprint length.'],
  ['CHECK', 'document_uri begins https://', 'policy_versions_uri_ck', 'Encrypted document transport.'],
  ['CHECK', 'effective_at >= published_at; retired_at > effective_at', 'policy_versions_times_ck', 'Policy dates remain logically ordered.'],
  ['Exclusion', 'No overlapping effective range per consent_type', 'policy_versions_no_effective_overlap_excl', 'Only one version can apply to a consent type at any instant.'],
  ['Foreign key consumer', 'core.user_consents(consent_type, policy_version)', 'user_consents_policy_fk', 'Consent cannot reference an unknown policy.'],
  ['Controlled immutability', 'Content immutable; first retirement only through approved function', 'policy_versions_append_only_trg', 'Accepted policy content remains fixed while controlled retirement is possible.'],
  ['Functions', 'publish_policy_version / retire_policy_version', 'Controlled policy lifecycle', 'Retire and replace atomically; direct mutation remains blocked.'],
  ['RLS/privilege', 'RLS enabled; anon/authenticated denied; service_role allowed', 'Migration security', 'Only trusted administration/backend process writes catalogue.']
];

const policyUseCases = [
  ['Signup consent', 'User grants Terms v1.1 and Privacy v1.1.', 'user_consents references the matching policy rows.', 'Exact accepted documents are retrievable.'],
  ['KYC consent', 'Before Aadhaar/PAN starts.', 'Latest KYC consent must be granted and references exact KYC policy.', 'Verification cannot start without current grant.'],
  ['Policy update', 'Privacy v1.0 changes.', 'Do not edit v1.0; insert v1.1 with new URI/hash/dates.', 'Existing history remains truthful.'],
  ['Re-consent', 'Current required version is newer than user grant.', 'Backend compares current required version to latest user decision.', 'Show new policy before full access if product requires.'],
  ['Withdrawal', 'User withdraws Marketing v1.0.', 'Insert a new withdrawn consent event; never edit the grant.', 'Current-consent view returns withdrawn.'],
  ['Audit request', 'Reviewer asks what user accepted on a date.', 'Join user_consents to policy_versions.', 'Return type/version, hash, URI, effective date, and captured time.'],
  ['Integrity verification', 'Policy file is retrieved from storage.', 'Recalculate SHA-256 and compare with content_sha256.', 'Mismatch means document changed or wrong file was served.'],
  ['Retirement', 'v1.0 is no longer offered to new users.', 'Set retirement only through approved controlled migration/process; historical references remain.', 'New signups use approved current version.']
];

const relationshipRows = [
  ['core.auth_sessions.user_id', 'core.users.user_id', 'Many sessions to one user', 'ON DELETE RESTRICT', 'Preserve session/account history.'],
  ['core.auth_sessions.auth_identity_id', 'core.auth_identities.id', 'Many sessions to one identity', 'ON DELETE RESTRICT', 'Know which login provider created the session.'],
  ['core.user_consents.(consent_type, policy_version)', 'core.policy_versions.(consent_type, policy_version)', 'Many consent events to one policy version', 'ON DELETE RESTRICT', 'Every user decision points to exact immutable policy.']
];

const ownershipRows = [
  ['Aditya', 'Database owner', 'Own schema, columns, constraints, migrations, lifecycle integration, and test evidence.', 'Does not personally decide legal policy wording.'],
  ['Backend authentication developer', 'Session operator', 'Generate tokens, hash refresh token, call issue/rotate/revoke/validate functions, protect secrets.', 'Never expose service-role key or plaintext refresh token.'],
  ['Frontend/mobile developer', 'Session client', 'Store refresh credential securely, use access token, request refresh/logout.', 'Does not directly read/write core.auth_sessions.'],
  ['Tech lead', 'Architecture approver', 'Approve token lifetimes, family model, revocation strategy, retention, and access-token invalidation.', 'Records final decisions before production.'],
  ['Product/legal/policy owner', 'Policy content approver', 'Supply approved document, URI, hash, publication/effective/retirement dates.', 'Database owner stores approved metadata only.'],
  ['Backend application developer', 'Consent recorder', 'Record grant/decline/withdrawal and select required current policy version.', 'Must not overwrite historical consent.']
];

const tests = [
  ['S1', 'Session status distribution', `SELECT status, COUNT(*) AS total_sessions\nFROM core.auth_sessions\nGROUP BY status\nORDER BY status;`, 'Rows for active/revoked/expired/compromised as present', 'Read-only'],
  ['S2', 'Invalid session-state rows', `SELECT COUNT(*) AS invalid_rows\nFROM core.auth_sessions\nWHERE octet_length(refresh_token_hash)<>32\n   OR refresh_token_version<1\n   OR (status='active' AND (revoked_at IS NOT NULL OR revocation_reason IS NOT NULL))\n   OR (status<>'active' AND (revoked_at IS NULL OR revocation_reason IS NULL));`, 'invalid_rows = 0', 'Read-only'],
  ['S3', 'Blocked account active sessions', `SELECT COUNT(*) AS invalid_rows\nFROM core.auth_sessions s\nJOIN core.users u USING (user_id)\nWHERE u.account_status IN ('suspended','deactivated','deletion_pending','deleted')\n  AND s.status='active';`, 'invalid_rows = 0', 'Read-only'],
  ['S4', 'Reject short token hash', `SELECT core.issue_auth_session(\n  ai.user_id, ai.id, decode('01','hex'), 'test-device', NULL, NULL\n)\nFROM core.auth_identities ai\nJOIN core.users u USING (user_id)\nJOIN core.user_verifications v USING (user_id)\nWHERE ai.status='active' AND u.account_status IN ('limited','active')\n  AND v.email_status='verified' AND v.phone_status='verified'\nLIMIT 1;`, 'ERROR: Refresh token hash must be 32 bytes', 'Negative; statement rolls back'],
  ['S5', 'Session timestamps', `SELECT COUNT(*) AS invalid_rows\nFROM core.auth_sessions\nWHERE expires_at<=created_at\n   OR idle_expires_at<=created_at\n   OR last_seen_at<created_at;`, 'invalid_rows = 0', 'Read-only'],
  ['P1', 'Policy catalogue', `SELECT consent_type, policy_version, document_uri, published_at, effective_at, retired_at\nFROM core.policy_versions\nORDER BY consent_type, policy_version;`, 'All approved catalogue rows', 'Read-only'],
  ['P2', 'Consent missing policy', `SELECT COUNT(*) AS invalid_rows\nFROM core.user_consents c\nLEFT JOIN core.policy_versions p\n  ON p.consent_type=c.consent_type AND p.policy_version=c.policy_version\nWHERE p.policy_version IS NULL;`, 'invalid_rows = 0', 'Read-only'],
  ['P3', 'Invalid policy integrity fields', `SELECT COUNT(*) AS invalid_rows\nFROM core.policy_versions\nWHERE octet_length(content_sha256)<>32\n   OR document_uri !~ '^https://'\n   OR effective_at<published_at\n   OR (retired_at IS NOT NULL AND retired_at<=effective_at);`, 'invalid_rows = 0', 'Read-only'],
  ['P4', 'Reject unknown policy', `INSERT INTO core.user_consents(user_id,consent_type,policy_version,decision,source)\nSELECT user_id,'privacy_notice','v99.0','granted','settings'\nFROM core.users LIMIT 1;`, 'ERROR: user_consents_policy_fk', 'Negative; statement rolls back'],
  ['P5', 'Reject policy modification', `UPDATE core.policy_versions\nSET document_uri='https://example.test/changed'\nWHERE consent_type='privacy_notice' AND policy_version='v1.0';`, 'ERROR: append-only relation cannot be updated or deleted', 'Negative; statement rolls back'],
  ['P6', 'Consent decisions by policy', `SELECT consent_type, policy_version, decision, COUNT(*) AS total\nFROM core.user_consents\nGROUP BY consent_type, policy_version, decision\nORDER BY consent_type, policy_version, decision;`, 'Counts of granted/declined/withdrawn events', 'Read-only']
];

const decisions = [
  ['Session family model', 'One-row rotation is documented; session_family_id is reserved for lineage/family compromise.', 'Implemented', 'A token-history model would require a separate reviewed migration.'],
  ['Access-token lifetime', 'How long is a short-lived access token valid?', 'Decision needed', 'Typical starting point: 10–15 minutes.'],
  ['Absolute session lifetime', 'Current function uses 30 days.', 'Review', 'Confirm business/security requirement.'],
  ['Idle session lifetime', 'Current function uses 7 days.', 'Review', 'Confirm expected “remember me” behavior.'],
  ['Access-token revocation', 'How is an already-issued token blocked after session revocation?', 'Decision needed', 'Short TTL plus session/cache check for sensitive/immediate revocation.'],
  ['Expiration maintenance', 'Who changes stored active rows to expired?', 'Decision needed', 'Validation already rejects timestamps; worker can persist state for reporting.'],
  ['last_seen_at updates', 'Rotation only or periodic activity updates?', 'Decision needed', 'Avoid write on every API request; use throttled updates.'],
  ['Revocation reasons', 'Keep free text or add controlled catalogue/CHECK?', 'Decision needed', 'Recommend controlled values plus extension process.'],
  ['Session retention', 'How long retain revoked/expired/compromised rows?', 'Decision needed', 'Coordinate security, privacy, audit, and deletion requirements.'],
  ['Policy current-version rule', 'Non-overlap and effective-period lookup select one current version.', 'Implemented', 'Registration and access gates require currently effective versions.'],
  ['Re-consent rule', 'Which policy changes require user to accept again?', 'Decision needed', 'Product/legal decision; version change alone should not silently decide.'],
  ['Policy document storage', 'Where are immutable historical documents stored?', 'Decision needed', 'Versioned object storage/website URI with retention and access controls.'],
  ['Policy hash generation', 'Who calculates and verifies SHA-256?', 'Decision needed', 'Controlled release pipeline/admin process before inserting version.'],
  ['Policy retirement process', 'Direct mutation is blocked; controlled publish/retire functions are available.', 'Implemented', 'Only trusted service_role can execute lifecycle functions.'],
  ['Ownership confirmation', 'Aditya owns both supporting table schemas.', 'Review', 'Backend operates sessions; policy owner approves content.']
];

// Cover sheet
const cover = workbook.addWorksheet('00 Cover', { properties: { tabColor: { argb: `FF${colors.navy}` } }, views: [{ showGridLines: false }] });
cover.columns = Array.from({ length: 8 }, () => ({ width: 17 }));
cover.mergeCells('A1:H3');
cover.getCell('A1').value = 'ADITYA SUPPORTING TABLES\nTECH-LEAD REVIEW WORKBOOK';
cover.getCell('A1').font = { name: 'Aptos Display', size: 27, bold: true, color: { argb: `FF${colors.white}` } };
cover.getCell('A1').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.navy}` } };
cover.getCell('A1').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getRow(1).height = 38; cover.getRow(2).height = 38; cover.getRow(3).height = 38;
cover.mergeCells('A5:H5');
cover.getCell('A5').value = 'core.auth_sessions + core.policy_versions';
cover.getCell('A5').font = { size: 17, bold: true, color: { argb: `FF${colors.blue}` } };
cover.getCell('A5').alignment = { horizontal: 'center' };
const facts = [
  ['Important correction', 'These are two additional tables, not two additional columns.'],
  ['Owner', 'Aditya — identity, authentication, consent, and account lifecycle module'],
  ['Reason added', 'Session/refresh-token revocation requirement and exact accepted-policy requirement'],
  ['Authentication architecture', 'Separate backend authentication; Supabase auth schema is not used as application session source'],
  ['Scope', '18 session columns + 8 policy columns'],
  ['Migrations', `${migrationName}; ${hardeningName}`],
  ['Data safety', 'No plaintext refresh tokens; no mutable accepted-policy documents'],
  ['Review date', '11 November 2026']
];
let r = 8;
for (const [label, value] of facts) {
  cover.mergeCells(r, 1, r, 2); cover.mergeCells(r, 3, r, 8);
  cover.getCell(r, 1).value = label; cover.getCell(r, 3).value = value;
  cover.getCell(r, 1).font = { bold: true, color: { argb: `FF${colors.white}` } };
  cover.getCell(r, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.blue}` } };
  cover.getCell(r, 3).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${r % 2 ? colors.white : colors.paleBlue}` } };
  for (let c = 1; c <= 8; c += 1) { cover.getCell(r, c).border = border(); cover.getCell(r, c).alignment = { vertical: 'middle', wrapText: true }; }
  cover.getRow(r).height = 31; r += 1;
}
cover.mergeCells('A18:H20');
cover.getCell('A18').value = 'Review goal\nDecide whether both tables are required, confirm every column and constraint, approve backend responsibilities, resolve the open session-family/policy-governance decisions, and then retain or revise the migration through GitHub.';
cover.getCell('A18').font = { size: 12, bold: true, color: { argb: `FF${colors.navy}` } };
cover.getCell('A18').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightGreen}` } };
cover.getCell('A18').alignment = { vertical: 'middle', wrapText: true };
cover.getCell('A18').border = border();
cover.mergeCells('A22:H23');
cover.getCell('A22').value = 'YELLOW HIGHLIGHT = change implemented in the Aditya hardening update on 11 November 2026';
cover.getCell('A22').font = { size: 12, bold: true, color: { argb: `FF${colors.black}` } };
cover.getCell('A22').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.changeYellow}` } };
cover.getCell('A22').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getCell('A22').border = border();

grid('01 Summary', 'Why These Two Tables Exist', 'Both are requirement-derived supporting tables; neither was claimed as an original Excel-defined table.', ['Table', 'Source requirement', 'Why it exists', 'Ownership', 'Necessity decision'], summaryRows, [32, 30, 80, 55, 72], colors.teal);
const sessionColSheet = grid('02 Session Columns', 'core.auth_sessions — Complete Column Design', 'One row per custom-backend login session. Access tokens are short-lived; refresh-token digest and lifecycle state are stored here.', ['Column', 'Datatype', 'Required / constraint', 'Example value', 'Purpose', 'Important note'], sessionColumns, [30, 22, 36, 45, 75, 75], colors.blue);
for (let row = 5; row <= sessionColSheet.rowCount; row += 1) sessionColSheet.getRow(row).height = 50;
grid('03 Session Values', 'Session Status and Reason Values', 'Status is constrained; revocation_reason is currently required for non-active sessions but not restricted to a fixed list.', ['Field', 'Value', 'Meaning', 'Rule / behavior'], sessionValues, [28, 65, 80, 78], colors.amber);
grid('04 Session Constraints', 'core.auth_sessions — Constraints and Indexes', 'Database-level protection for relationships, hashes, states, times, and trusted backend access.', ['Kind', 'Columns / expression', 'Constraint / index', 'Why it matters'], sessionConstraints, [24, 66, 48, 82], colors.purple);
grid('05 Session Use Cases', 'core.auth_sessions — Practical Use Cases', 'Examples to explain login continuity, refresh rotation, multi-device logout, expiry, and compromise to the tech lead.', ['Use case', 'Starting event', 'What backend/database does', 'Result'], sessionUseCases, [35, 58, 90, 65], colors.green);

const policyColSheet = grid('06 Policy Columns', 'core.policy_versions — Complete Column Design', 'One immutable catalogue row identifies one exact approved policy document version.', ['Column', 'Datatype', 'Required / constraint', 'Example value', 'Purpose', 'Important note'], policyColumns, [30, 22, 36, 55, 75, 75], colors.blue);
for (let row = 5; row <= policyColSheet.rowCount; row += 1) policyColSheet.getRow(row).height = 50;
grid('07 Policy Values', 'Policy Types, Versions, and Retirement Values', 'The policy catalogue describes documents; core.user_consents records each user’s granted, declined, or withdrawn decision.', ['Field', 'Value', 'Meaning', 'Rule / behavior'], policyValues, [28, 35, 85, 80], colors.amber);
grid('08 Policy Constraints', 'core.policy_versions — Constraints and Integrity Rules', 'Exact accepted-policy provenance depends on composite identity, immutable history, hash, URI, and ordered dates.', ['Kind', 'Columns / expression', 'Constraint / trigger', 'Why it matters'], policyConstraints, [26, 70, 50, 82], colors.purple);
grid('09 Policy Use Cases', 'core.policy_versions — Practical Use Cases', 'Examples for signup, KYC, policy changes, re-consent, withdrawal, integrity checking, and audits.', ['Use case', 'Starting event', 'What backend/database does', 'Result'], policyUseCases, [35, 58, 90, 65], colors.green);

grid('10 Relationships', 'Relationships to Existing Aditya Tables', 'The supporting tables extend—not replace—the original users, identities, and consents tables.', ['Child column(s)', 'Parent column(s)', 'Cardinality', 'Delete rule', 'Purpose'], relationshipRows, [58, 58, 44, 28, 82], colors.teal);
grid('11 Ownership', 'Responsibility Matrix', 'Schema ownership, operational backend work, client responsibilities, and policy-content approval are deliberately separated.', ['Person / team', 'Role', 'Responsible for', 'Must not do'], ownershipRows, [35, 35, 95, 80], colors.red);

const ddlRows = [
  ['core.auth_sessions', migrationName, extractCreate('core.auth_sessions')],
  ['core.policy_versions', migrationName, extractCreate('core.policy_versions')],
  ['Related hardening', hardeningName, hardeningSql]
];
const ddlSheet = grid('12 Exact DDL', 'Exact CREATE TABLE DDL', 'Copied from the deployed migration. Git migration remains the executable source of truth.', ['Table', 'Migration', 'DDL'], ddlRows, [34, 55, 135], colors.navy);
for (let row = 5; row <= ddlSheet.rowCount; row += 1) { ddlSheet.getCell(row, 3).font = { name: 'Consolas', size: 9 }; ddlSheet.getRow(row).height = 300; }

const testSheet = grid('13 SQL Tests', 'SQL Verification Tests', 'Run one query at a time. Read-only checks expect zero invalid rows; negative checks expect the stated error.', ['Test ID', 'Test', 'SQL', 'Expected result', 'Safety'], tests, [14, 45, 115, 60, 32], colors.green);
for (let row = 5; row <= testSheet.rowCount; row += 1) { testSheet.getCell(row, 3).font = { name: 'Consolas', size: 9 }; testSheet.getRow(row).height = 130; }

const decisionSheet = grid('14 Tech Lead Decisions', 'Tech-Lead Decision Register', 'These decisions should be agreed before treating the two supporting tables as production-final.', ['Topic', 'Question / current implementation', 'Status', 'Recommendation / discussion'], decisions, [42, 85, 24, 90], colors.red);
for (let row = 5; row <= decisionSheet.rowCount; row += 1) {
  const cell = decisionSheet.getCell(row, 3);
  const implemented = String(cell.value).toLowerCase()==='implemented';
  cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${implemented ? colors.lightGreen : colors.lightAmber}` } };
  cell.font = { bold: true, color: { argb: `FF${implemented ? colors.green : colors.amber}` } };
  decisionSheet.getRow(row).height = 48;
}

for (const ws of workbook.worksheets) {
  if (ws.name !== '00 Cover') highlightChangedRows(ws);
  ws.properties.defaultRowHeight = 18;
  ws.pageSetup.paperSize = 9;
  ws.pageSetup.fitToPage = true;
  ws.pageSetup.horizontalCentered = true;
}

await workbook.xlsx.writeFile(output);
console.log(output);
console.log(`Sheets: ${workbook.worksheets.length}`);
console.log(`Session columns: ${sessionColumns.length}`);
console.log(`Policy columns: ${policyColumns.length}`);
console.log(`SQL tests: ${tests.length}`);
console.log(`Tech-lead decisions: ${decisions.length}`);
