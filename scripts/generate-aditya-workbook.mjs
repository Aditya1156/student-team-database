import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ExcelJS from 'exceljs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const docsDir = path.join(root, 'docs');
const output = path.join(docsDir, 'Aditya_Identity_Database_Design.xlsx');
const designPath = path.join(docsDir, 'ADITYA_IDENTITY_DATABASE.md');
const testsPath = path.join(root, 'supabase', 'tests', 'aditya_auth_lifecycle_queries.sql');
const coreMigrationPath = path.join(root, 'supabase', 'migrations', '20261109090000_core_identity.sql');
const lifecycleMigrationPath = path.join(root, 'supabase', 'migrations', '20261110100000_identity_lifecycle_completion.sql');
const hardeningMigrationPath = path.join(root, 'supabase', 'migrations', '20261111100000_aditya_gap_hardening.sql');
const routinesMigrationPath = path.join(root, 'supabase', 'migrations', '20261109100000_routines_security.sql');

const design = fs.readFileSync(designPath, 'utf8');
const testSql = fs.readFileSync(testsPath, 'utf8');
const coreSql = fs.readFileSync(coreMigrationPath, 'utf8');
const lifecycleSql = fs.readFileSync(lifecycleMigrationPath, 'utf8');
const hardeningSql = fs.readFileSync(hardeningMigrationPath, 'utf8');
const routinesSql = fs.readFileSync(routinesMigrationPath, 'utf8');

const colors = {
  navy: '17365D', blue: '1F4E78', teal: '0F6B78', lightBlue: 'D9EAF7',
  paleBlue: 'EAF3F8', green: '2E7D32', lightGreen: 'E2F0D9', amber: 'C65911',
  lightAmber: 'FCE4D6', red: 'C00000', lightRed: 'F4CCCC', gray: '666666',
  lightGray: 'F2F2F2', white: 'FFFFFF', black: '1F1F1F', purple: '7030A0',
  changeYellow: 'FFFF00'
};

const changeMarkers = [
  '20261111100000_aditya_gap_hardening.sql',
  'auth_identities_id_user_uq',
  'auth_sessions_identity_owner_fk',
  'auth_sessions_identity_owner_ix',
  'auth_sessions_idle_within_absolute_ck',
  'auth_sessions_rotation_state_ck',
  'users_age_consistency_ck',
  'policy_versions_no_effective_overlap_excl',
  'publish_policy_version',
  'retire_policy_version',
  'policy_version_is_effective',
  'user_has_current_consent',
  'current_policy_versions',
  'one-row rotation',
  'same session user',
  'cannot exceed absolute expiry',
  'verified identity evidence',
  'currently effective'
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

const workbook = new ExcelJS.Workbook();
workbook.creator = 'Aditya / Student Team Database';
workbook.lastModifiedBy = 'OpenAI Codex';
workbook.created = new Date('2026-11-11T00:00:00+05:30');
workbook.modified = new Date('2026-11-11T00:00:00+05:30');
workbook.subject = 'Aditya identity, authentication, verification, consent, and lifecycle database design';
workbook.title = 'Aditya Identity Database Design';
workbook.description = 'Implemented PostgreSQL/Supabase design, DDL, constraints, relationships, rules, and test SQL.';
workbook.company = 'Student Enterprise Database Project';
workbook.calcProperties.fullCalcOnLoad = true;

function border() {
  return {
    top: { style: 'thin', color: { argb: 'FFD0D7DE' } },
    left: { style: 'thin', color: { argb: 'FFD0D7DE' } },
    bottom: { style: 'thin', color: { argb: 'FFD0D7DE' } },
    right: { style: 'thin', color: { argb: 'FFD0D7DE' } }
  };
}

function styleTitle(ws, title, subtitle, lastColumn) {
  ws.mergeCells(1, 1, 1, lastColumn);
  ws.getCell(1, 1).value = title;
  ws.getCell(1, 1).font = { name: 'Aptos Display', size: 20, bold: true, color: { argb: `FF${colors.white}` } };
  ws.getCell(1, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.navy}` } };
  ws.getCell(1, 1).alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(1).height = 34;
  ws.mergeCells(2, 1, 2, lastColumn);
  ws.getCell(2, 1).value = subtitle;
  ws.getCell(2, 1).font = { name: 'Aptos', size: 10, italic: true, color: { argb: `FF${colors.gray}` } };
  ws.getCell(2, 1).alignment = { vertical: 'middle', wrapText: true };
  ws.getRow(2).height = 28;
}

function styleGrid(ws, headerRow = 4) {
  const header = ws.getRow(headerRow);
  header.height = 30;
  header.eachCell(cell => {
    cell.font = { name: 'Aptos', size: 10, bold: true, color: { argb: `FF${colors.white}` } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.blue}` } };
    cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
    cell.border = border();
  });
  for (let r = headerRow + 1; r <= ws.rowCount; r += 1) {
    const row = ws.getRow(r);
    row.eachCell({ includeEmpty: true }, cell => {
      cell.font = { name: 'Aptos', size: 10, color: { argb: `FF${colors.black}` } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${r % 2 ? colors.white : colors.paleBlue}` } };
      cell.alignment = { vertical: 'top', wrapText: true };
      cell.border = border();
    });
  }
  ws.views = [{ state: 'frozen', ySplit: headerRow, xSplit: 0 }];
  ws.autoFilter = { from: { row: headerRow, column: 1 }, to: { row: headerRow, column: ws.columnCount } };
  ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0, margins: { left: 0.25, right: 0.25, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 } };
  ws.headerFooter.oddFooter = '&LAditya Identity Database&CPage &P of &N&R11 Nov 2026';
}

function setWidths(ws, widths) {
  widths.forEach((width, index) => { ws.getColumn(index + 1).width = width; });
}

function addGridSheet(name, title, subtitle, headers, rows, widths, tabColor = colors.blue) {
  const ws = workbook.addWorksheet(name, { properties: { tabColor: { argb: `FF${tabColor}` } } });
  styleTitle(ws, title, subtitle, headers.length);
  ws.addRow([]);
  ws.addRow(headers);
  for (const row of rows) ws.addRow(row);
  setWidths(ws, widths);
  styleGrid(ws, 4);
  return ws;
}

function clean(text) {
  return text.replace(/`/g, '').replace(/<br\s*\/?>/gi, ' ').trim();
}

function parseColumnDesign(markdown) {
  const rows = [];
  const sections = [...markdown.matchAll(/^### 5\.(\d+) `([^`]+)`/gm)];
  for (let s = 0; s < sections.length; s += 1) {
    const table = sections[s][2];
    const start = sections[s].index + sections[s][0].length;
    const end = s + 1 < sections.length ? sections[s + 1].index : markdown.indexOf('\n## 6.', start);
    const lines = markdown.slice(start, end).split(/\r?\n/);
    let group = 'Core columns';
    for (let i = 0; i < lines.length; i += 1) {
      const heading = lines[i].match(/^####\s+(.+)/);
      if (heading) group = clean(heading[1]);
      if (!/^\|\s*Column\s*\|/i.test(lines[i])) continue;
      const headers = lines[i].split('|').slice(1, -1).map(clean);
      i += 2;
      while (i < lines.length && /^\|/.test(lines[i])) {
        const values = lines[i].split('|').slice(1, -1).map(clean);
        const record = Object.fromEntries(headers.map((header, index) => [header.toLowerCase(), values[index] ?? '']));
        rows.push([
          table,
          group,
          record.column ?? '',
          record.type ?? '',
          record['required/default'] ?? '',
          record['meaning and rules'] ?? record.rule ?? ''
        ]);
        i += 1;
      }
    }
  }
  return rows;
}

function extractCreate(sql, qualifiedName) {
  const escaped = qualifiedName.replace('.', '\\.');
  const match = sql.match(new RegExp(`create table ${escaped} \\([\\s\\S]*?\\n\\);`, 'i'));
  if (!match) throw new Error(`CREATE TABLE not found for ${qualifiedName}`);
  return match[0].trim();
}

function extractAlterStatements(sql, qualifiedName) {
  const escaped = qualifiedName.replace('.', '\\.');
  return [...sql.matchAll(new RegExp(`alter table ${escaped}[\\s\\S]*?;`, 'gi'))].map(match => match[0].trim());
}

function parseReadOnlyTests(sql) {
  const rows = [];
  const blocks = sql.split(/(?=-- -{20,}\r?\n-- Question)/g);
  for (const block of blocks) {
    const q = block.match(/-- Question\s+(\d+)(?:\s+continued)?:\s*([^\r\n]+)/i);
    if (!q) continue;
    const comments = block.split(/\r?\n/).filter(line => line.startsWith('--')).map(line => line.replace(/^--\s?/, '').trim());
    const expected = comments.find(line => /^Expected output:/i.test(line))?.replace(/^Expected output:\s*/i, '') ?? 'PASS and 0 invalid rows';
    const sqlStart = block.split(/\r?\n/).findIndex(line => /^(with|select)/i.test(line.trim()));
    const statement = block.split(/\r?\n/).slice(sqlStart).join('\n').trim();
    rows.push([`Q${q[1]}`, clean(q[2]), comments.slice(1).filter(line => line && !/^Expected/.test(line) && !/^-+$/.test(line)).join(' '), statement, expected, 'Read-only']);
  }
  return rows;
}

const tables = [
  ['core.users', 'Original Excel', 'Master account, random business UUID, account and verification state', 'Aditya', '1 per user'],
  ['core.auth_identities', 'Original Excel', 'Email OTP, phone OTP, Google, and Apple identities linked to one user', 'Aditya + backend auth', '0..many per user'],
  ['core.user_contacts', 'Original Excel', 'Current unique email and phone with contact version', 'Aditya', '1 per user'],
  ['core.user_verifications', 'Original Excel', 'Email, phone, Aadhaar, PAN, and age verification state', 'Aditya + KYC backend', '1 per user'],
  ['core.user_otp_challenges', 'Original Excel', 'OTP signup, login, contact change, and recovery workflow', 'Aditya + backend auth', '0..many per user'],
  ['core.user_consents', 'Original Excel', 'Append-only user consent decisions', 'Aditya + backend', '0..many per user'],
  ['core.user_status_history', 'Original Excel', 'Append-only account lifecycle history', 'Aditya', '1..many per user'],
  ['core.auth_sessions', 'Added for Question 5', 'Custom-backend sessions, refresh-token rotation, expiry, revocation, compromise', 'Aditya schema; backend operates', '0..many per user'],
  ['core.policy_versions', 'Added for Question 8', 'Immutable catalogue of exact Terms, Privacy, KYC, and Marketing policy versions', 'Aditya schema; policy owner supplies content', 'Shared catalogue']
];

const columnRows = parseColumnDesign(design);

const tableConstraints = [
  ['core.users', 'users_user_id_uq', 'UNIQUE', 'user_id', 'Every application UUID is unique.'],
  ['core.users', 'users_account_status_ck', 'CHECK', 'account_status', 'Only limited, active, suspended, deactivated, deletion_pending, deleted.'],
  ['core.users', 'users_verification_status_ck', 'CHECK', 'verification_status', 'Only pending, verified, rejected, review_required.'],
  ['core.users', 'users_deleted_ck', 'CHECK', 'account_status + deleted_at', 'deleted_at exists exactly for deleted accounts.'],
  ['core.users', 'users_before_write_trg', 'TRIGGER RULE', 'user_id, DOB, timezone, account_status', 'UUID immutable; valid timezone; DOB not future/locked after verification; status changes use controlled function.'],
  ['core.auth_identities', 'auth_identities_provider_subject_uq', 'UNIQUE', 'provider + provider_subject', 'One external identity cannot belong to two application users.'],
  ['core.auth_identities', 'auth_identities_one_active_provider_uq', 'PARTIAL UNIQUE', 'user_id + provider WHERE active', 'One active identity per provider per user.'],
  ['core.auth_identities', 'auth_identities_unlink_consistency_ck', 'CHECK', 'status + unlinked fields', 'Active has no unlink details; non-active requires time and reason.'],
  ['core.auth_identities', 'auth_identities_before_write_trg', 'TRIGGER RULE', 'owner, provider, OTP identity', 'Owner/provider immutable; OTP provider requires matching verified contact; revoked identity cannot reactivate.'],
  ['core.user_contacts', 'user_contacts_user_uq', 'UNIQUE/FK', 'user_id', 'Exactly one current contact row per user; user delete restricted.'],
  ['core.user_contacts', 'user_contacts_email_uq', 'UNIQUE', 'email', 'Same email cannot belong to two users.'],
  ['core.user_contacts', 'user_contacts_phone_uq', 'UNIQUE', 'phone_number', 'Same phone cannot belong to two users.'],
  ['core.user_contacts', 'contact-change triggers', 'TRIGGER RULE', 'email, phone, contact_version', 'Normalize email, increase version, reset verification, cancel old OTP, active becomes limited.'],
  ['core.user_verifications', 'user_verifications_user_uq', 'UNIQUE/FK', 'user_id', 'One verification row per user; owner immutable.'],
  ['core.user_verifications', 'verification result checks', 'CHECK', 'statuses + timestamps/results', 'Verified status requires timestamps and approved result fields; failure/review requires reason.'],
  ['core.user_verifications', 'verification attempt checks', 'CHECK/TRIGGER', 'aadhaar_attempt_count, pan_attempt_count', '0..3 attempts; third pending attempt becomes failed/too_many_attempts.'],
  ['core.user_verifications', 'verification masking checks', 'CHECK', 'aadhaar_masked, pan_masked', 'Only XXXXXXXX1234 and XXXPX1234A-style masked formats.'],
  ['core.user_verifications', 'verification unique references', 'UNIQUE INDEX', 'provider references and hashes', 'Prevents reuse of provider transaction references or identity hashes.'],
  ['core.user_verifications', 'verification ordering trigger', 'TRIGGER RULE', 'contacts, consent, Aadhaar, PAN', 'Contacts and KYC consent before Aadhaar; Aadhaar starts before PAN; PAN verifies after Aadhaar.'],
  ['core.user_otp_challenges', 'uoc_one_pending_uq', 'PARTIAL UNIQUE', 'user_id + channel + purpose WHERE pending', 'Only one pending OTP per channel and purpose.'],
  ['core.user_otp_challenges', 'OTP hash/attempt/resend checks', 'CHECK', 'hashes, attempts, resends', '32-byte HMAC; 0..5 attempts and resends.'],
  ['core.user_otp_challenges', 'OTP time/status checks', 'CHECK/TRIGGER', 'sent, expiry, verified, locked', '10-minute expiry; verified and locked timestamps match status.'],
  ['core.user_otp_challenges', 'OTP immutability trigger', 'TRIGGER RULE', 'owner, channel, purpose, version, hashes', 'Identity fields immutable; HMAC changes only through resend function; stale contact version rejected.'],
  ['core.user_consents', 'user_consents_policy_fk', 'COMPOSITE FK', 'consent_type + policy_version', 'Every decision references a real immutable policy version.'],
  ['core.user_consents', 'user_consents_uq', 'UNIQUE', 'user + type + version + captured_at', 'Prevents an exact duplicate event at the same time.'],
  ['core.user_consents', 'user_consents_append_only_trg', 'TRIGGER RULE', 'entire row', 'Consent events cannot be updated or deleted; withdrawal is a new event.'],
  ['core.user_status_history', 'status-history checks', 'CHECK/FK', 'states, actor, reason, effective time', 'Valid states/reasons; system has no actor ID; others require actor ID; deletion pending needs effective time.'],
  ['core.user_status_history', 'user_status_history_append_only_trg', 'TRIGGER RULE', 'entire row', 'Lifecycle history cannot be updated or deleted.'],
  ['core.policy_versions', 'policy_versions_pkey', 'COMPOSITE PK', 'consent_type + policy_version', 'One record for each policy type/version pair.'],
  ['core.policy_versions', 'policy format/integrity checks', 'CHECK', 'version, hash, URI, times', 'vN.N format; 32-byte hash; HTTPS URI; effective/retired dates ordered.'],
  ['core.policy_versions', 'policy_versions_no_effective_overlap_excl', 'EXCLUSION', 'consent type + effective range', 'Effective policy periods for one consent type cannot overlap.'],
  ['core.policy_versions', 'policy_versions_append_only_trg', 'TRIGGER RULE', 'content + retirement', 'Policy content is immutable; first retirement is allowed only through controlled functions.'],
  ['core.auth_sessions', 'auth_sessions_token_uq', 'UNIQUE', 'refresh_token_hash', 'A refresh-token digest cannot be reused across sessions.'],
  ['core.auth_sessions', 'auth session foreign keys', 'FK', 'user_id + auth_identity_id', 'Session belongs to a real user and linked identity; deletes restricted.'],
  ['core.auth_sessions', 'auth_sessions_identity_owner_fk', 'COMPOSITE FK', 'auth_identity_id + user_id', 'The authentication identity must belong to the same session user.'],
  ['core.auth_sessions', 'auth session hash checks', 'CHECK', 'token, IP, user-agent hashes', 'Each protected hash is exactly 32 bytes when present.'],
  ['core.auth_sessions', 'auth_sessions_status_ck', 'CHECK', 'status', 'Only active, revoked, expired, compromised.'],
  ['core.auth_sessions', 'auth_sessions_revocation_ck', 'CHECK', 'status + revocation fields', 'Active has no revocation details; every non-active session requires them.'],
  ['core.auth_sessions', 'auth_sessions_time_ck', 'CHECK', 'created, seen, expiry', 'Expiry after creation and last-seen not before creation.'],
  ['core.auth_sessions', 'auth_sessions_idle_within_absolute_ck', 'CHECK', 'idle/seen + absolute expiry', 'Idle expiry and last-seen cannot exceed absolute expiry.'],
  ['core.auth_sessions', 'auth_sessions_rotation_state_ck', 'CHECK', 'token version + replaced_at', 'Version 1 has no replacement time; rotated versions require one.']
];

const relationships = [
  ['core.auth_identities.user_id', 'core.users.user_id', 'Many-to-one', 'ON DELETE RESTRICT', 'Authentication identity owner'],
  ['core.user_contacts.user_id', 'core.users.user_id', 'One-to-one', 'ON DELETE RESTRICT', 'Current contact owner'],
  ['core.user_verifications.user_id', 'core.users.user_id', 'One-to-one', 'ON DELETE RESTRICT', 'Verification owner'],
  ['core.user_otp_challenges.user_id', 'core.users.user_id', 'Many-to-one', 'ON DELETE RESTRICT', 'OTP owner'],
  ['core.user_consents.user_id', 'core.users.user_id', 'Many-to-one', 'ON DELETE RESTRICT', 'Consent actor'],
  ['core.user_status_history.user_id', 'core.users.user_id', 'Many-to-one', 'ON DELETE RESTRICT', 'Lifecycle subject'],
  ['core.auth_sessions.user_id', 'core.users.user_id', 'Many-to-one', 'ON DELETE RESTRICT', 'Session owner'],
  ['core.auth_sessions.auth_identity_id', 'core.auth_identities.id', 'Many-to-one', 'ON DELETE RESTRICT', 'Identity used for login'],
  ['core.user_consents.(consent_type, policy_version)', 'core.policy_versions.(consent_type, policy_version)', 'Many-to-one', 'ON DELETE RESTRICT', 'Exact policy provenance'],
  ['Other team tables.user_id', 'core.users.user_id', 'Many-to-one', 'Mostly ON DELETE RESTRICT', 'Profiles, messaging, connections, safety, jobs, analytics']
];

const valueLists = [
  ['core.users', 'account_status', 'limited, active, suspended, deactivated, deletion_pending, deleted', 'limited'],
  ['core.users', 'verification_status', 'pending, verified, rejected, review_required', 'pending'],
  ['core.users', 'age_eligibility_status', 'unknown, eligible, ineligible, review_required', 'unknown'],
  ['core.users', 'gender', 'male, female, transgender_man, transgender_woman, non_binary, genderqueer, genderfluid, agender, other, prefer_not_to_say', 'prefer_not_to_say'],
  ['core.auth_identities', 'provider', 'email_otp, phone_otp, google, apple', 'None'],
  ['core.auth_identities', 'status', 'active, unlinked, revoked', 'active'],
  ['core.auth_identities', 'unlink_reason', 'user_request, security, admin_action, provider_revoked', 'NULL while active'],
  ['core.user_verifications', 'email_status / phone_status', 'not_started, pending, verified, failed', 'not_started'],
  ['core.user_verifications', 'aadhaar_status / pan_status', 'not_started, pending, verified, failed, review_required', 'not_started'],
  ['core.user_otp_challenges', 'channel', 'email, phone', 'None'],
  ['core.user_otp_challenges', 'purpose', 'signup, login, contact_change, account_recovery', 'None'],
  ['core.user_otp_challenges', 'status', 'pending, verified, expired, locked, cancelled', 'pending'],
  ['core.user_consents / policy_versions', 'consent_type', 'terms_of_service, privacy_notice, kyc_verification, marketing', 'None'],
  ['core.user_consents', 'decision', 'granted, declined, withdrawn', 'None'],
  ['core.user_consents', 'source', 'signup_flow, settings, admin_console, api', 'None'],
  ['core.user_status_history', 'actor_type', 'user, admin, support, system', 'None'],
  ['core.auth_sessions', 'status', 'active, revoked, expired, compromised', 'active'],
  ['core.auth_sessions', 'common revocation_reason', 'user_logout, security_event, account_recovery, refresh_token_reuse, account_suspended, account_deactivated, account_deletion_pending, account_deleted, identity_unlinked, identity_revoked', 'NULL while active; current DB does not constrain this list']
];

const functionRows = [
  ['core.register_user', 'Function', 'Creates user, contact, required signup consents, provider identity or OTP, and registration audit.', 'service_role only'],
  ['core.link_auth_identity', 'Function', 'Links an additional provider to a non-deleted user and rejects duplicates.', 'service_role only'],
  ['core.resend_otp_challenge', 'Function', 'Enforces 60-second cooldown and five resends/hour; rotates OTP HMAC.', 'service_role only'],
  ['core.verify_otp_challenge', 'Function', 'Enforces expiry and attempts; verifies contact; handles signup identity and recovery revocation.', 'service_role only'],
  ['core.issue_auth_session', 'Function', 'Issues one custom-backend session with 30-day absolute and 7-day idle lifetime.', 'service_role only'],
  ['core.rotate_refresh_token', 'Function', 'Replaces current token hash, increments version, or marks reuse as compromised.', 'service_role only'],
  ['core.revoke_auth_session', 'Function', 'Revokes one active session.', 'service_role only'],
  ['core.revoke_all_user_sessions', 'Function', 'Revokes all active sessions for one user.', 'service_role only'],
  ['core.validate_auth_session', 'Function', 'Returns user UUID only for active, unexpired, permitted session and identity.', 'service_role only'],
  ['core.change_account_status', 'Function', 'Validates lifecycle transition and atomically appends status history.', 'service_role only'],
  ['core.user_can_login', 'Function', 'Requires limited/active account and verified email and phone.', 'backend gate'],
  ['core.user_access_ready', 'Function', 'Requires all four verifications, eligible adult, DOB, and required current consents.', 'backend gate'],
  ['core.user_access_level', 'Function', 'Returns blocked_lifecycle, contact_verification, kyc_retry_or_review, onboarding_kyc, or main_app.', 'backend routing'],
  ['core.publish_policy_version', 'Function', 'Atomically retires the current policy and inserts a non-overlapping replacement.', 'service_role only'],
  ['core.retire_policy_version', 'Function', 'Records the first controlled retirement time without changing policy content.', 'service_role only'],
  ['core.policy_version_is_effective', 'Function', 'Checks whether one exact policy version applies at a specified time.', 'service_role only'],
  ['core.user_has_current_consent', 'Function', 'Requires the latest user decision to grant a currently effective policy.', 'backend gate'],
  ['users_before_write_trg', 'Trigger', 'Protects UUID, DOB, timezone, and direct status changes.', 'core.users'],
  ['users_after_insert_trg', 'Trigger', 'Creates verification row and initial limited lifecycle event.', 'core.users'],
  ['user_contacts_after_change_trg', 'Trigger', 'Resets changed contact verification, cancels OTPs, and limits active account.', 'core.user_contacts'],
  ['user_verifications_after_write_trg', 'Trigger', 'Synchronizes overall verification and age state to core.users.', 'core.user_verifications'],
  ['users_revoke_sessions_trg', 'Trigger', 'Revokes sessions for suspended/deactivated/deletion states.', 'core.users'],
  ['auth_identities_revoke_sessions_trg', 'Trigger', 'Revokes sessions when the login identity is unlinked or revoked.', 'core.auth_identities'],
  ['core.audit_identity_event', 'Audit trigger function', 'Writes sanitized identity/session state changes to audit.audit_product_event.', 'protected audit']
];

const flowRows = [
  ['Registration', 'Backend calls core.register_user', 'Create random user UUID, contact, verification/history, Terms/Privacy consent, then provider identity or signup OTP.', 'Atomic: any failure rolls back all rows.'],
  ['Email/phone login', 'Verify OTP', 'Contact becomes verified; signup OTP creates email_otp or phone_otp identity.', 'Plaintext OTP never stored.'],
  ['Provider linking', 'Backend verifies Google/Apple and calls link function', 'Add provider identity to same stable user UUID.', 'Provider subject globally unique.'],
  ['Contact change', 'Update current contact', 'Increase contact_version, reset changed verification, cancel old OTP, return active account to limited.', 'All profile/history remains on same user UUID.'],
  ['KYC', 'Verify contacts + KYC consent, then Aadhaar and PAN', 'Store status, timestamps, attempts, masked values, hashes, provider references.', 'No raw Aadhaar/PAN. PAN verifies after Aadhaar.'],
  ['Main access', 'Backend calls access functions', 'Only all four verified + eligible adult + required consents + active status reaches main_app.', 'Incomplete user remains limited/onboarding.'],
  ['Session issue', 'Successful separate-backend authentication', 'Store only refresh-token hash; issue 30-day/7-day-idle session.', 'Access token remains backend responsibility.'],
  ['Token rotation', 'Client submits refresh token', 'Compare hash, replace with new hash, increment version, extend idle time.', 'Wrong/old hash marks compromise.'],
  ['Logout/recovery/lifecycle', 'Revoke one or all sessions', 'Record non-active status, time, and reason.', 'History retained for audit.'],
  ['Consent withdrawal', 'Insert a withdrawn event', 'Current-consent view selects newest event; previous grant remains.', 'Never update/delete old consent.'],
  ['Policy change', 'Insert v1.1/v2.0', 'Keep old policy immutable; link later consent events to new exact version.', 'Policy content supplied/approved outside DB.'],
  ['Deletion', 'Controlled status transition', 'deletion_pending grace period, legal-hold check, final deleted state, revoke sessions.', 'Physical FK cascade is avoided.']
];

const negativeTests = [
  ['N1', 'Reject duplicate email registration', 'Run core.register_user using an email selected from core.user_contacts.', `SELECT core.register_user(
  'google',
  'duplicate-email-' || extensions.gen_random_uuid()::text,
  (SELECT email FROM core.user_contacts LIMIT 1),
  '+999000000000001',
  'Asia/Kolkata', DATE '2000-01-01', 'prefer_not_to_say',
  'v1.1', 'v1.1', NULL, NULL, 'duplicate-email-test'
);`, 'ERROR: user_contacts_email_uq', 'Negative; statement rolls back'],
  ['N2', 'Reject invalid email', 'Try changing a contact to a malformed email.', `UPDATE core.user_contacts
SET email = 'invalid-email'
WHERE id = (SELECT id FROM core.user_contacts LIMIT 1);`, 'ERROR: user_contacts_email_normalized_ck', 'Negative; statement rolls back'],
  ['N3', 'Reject future DOB', 'Try inserting tomorrow as date of birth.', `INSERT INTO core.users(date_of_birth)
VALUES (CURRENT_DATE + 1);`, 'ERROR: date_of_birth cannot be in the future', 'Negative; statement rolls back'],
  ['N4', 'Reject unsupported provider', 'Try registering with Facebook.', `SELECT core.register_user(
  'facebook', 'test-subject',
  'provider-' || extensions.gen_random_uuid()::text || '@example.test',
  '+999000000000002', 'Asia/Kolkata', DATE '2000-01-01',
  'prefer_not_to_say', 'v1.1', 'v1.1', NULL, NULL,
  'invalid-provider-test'
);`, 'ERROR: Unsupported provider', 'Negative; no user created'],
  ['N5', 'Protect stable user UUID', 'Try changing a business user UUID.', `UPDATE core.users
SET user_id = extensions.gen_random_uuid()
WHERE id = (SELECT id FROM core.users LIMIT 1);`, 'ERROR: user_id is immutable', 'Negative; statement rolls back'],
  ['N6', 'Block direct status update', 'Try bypassing the lifecycle function.', `UPDATE core.users
SET account_status = 'suspended'
WHERE id = (SELECT id FROM core.users WHERE account_status = 'active' LIMIT 1);`, 'ERROR: Use core.change_account_status()', 'Negative; statement rolls back'],
  ['N7', 'Reject unknown policy version', 'Try granting privacy policy v99.0.', `INSERT INTO core.user_consents(user_id, consent_type, policy_version, decision, source)
SELECT user_id, 'privacy_notice', 'v99.0', 'granted', 'settings'
FROM core.users LIMIT 1;`, 'ERROR: user_consents_policy_fk', 'Negative; statement rolls back'],
  ['N8', 'Protect append-only consent', 'Try changing an existing consent event.', `UPDATE core.user_consents
SET decision = 'withdrawn'
WHERE id = (SELECT id FROM core.user_consents LIMIT 1);`, 'ERROR: append-only relation cannot be updated or deleted', 'Negative; insert withdrawal instead'],
  ['N9', 'Reject raw Aadhaar', 'Try replacing a verified mask with 12 raw digits.', `UPDATE core.user_verifications
SET aadhaar_masked = '123456789012'
WHERE id = (SELECT id FROM core.user_verifications WHERE aadhaar_status = 'verified' LIMIT 1);`, 'ERROR: uv_aadhaar_masked_ck', 'Negative; statement rolls back'],
  ['N10', 'Reject invalid PAN mask', 'Try replacing a verified mask with a full-style PAN.', `UPDATE core.user_verifications
SET pan_masked = 'ABCDE1234F'
WHERE id = (SELECT id FROM core.user_verifications WHERE pan_status = 'verified' LIMIT 1);`, 'ERROR: uv_pan_masked_ck', 'Negative; statement rolls back'],
  ['N11', 'Reject short refresh-token hash', 'Try issuing a session with a one-byte hash.', `SELECT core.issue_auth_session(
  ai.user_id, ai.id, decode('01','hex'), 'test-device', NULL, NULL
)
FROM core.auth_identities ai
JOIN core.users u USING (user_id)
JOIN core.user_verifications v USING (user_id)
WHERE ai.status='active' AND u.account_status IN ('limited','active')
  AND v.email_status='verified' AND v.phone_status='verified'
LIMIT 1;`, 'ERROR: Refresh token hash must be 32 bytes', 'Negative; no session created'],
  ['N12', 'Protect immutable policy', 'Try editing an already-published policy.', `UPDATE core.policy_versions
SET document_uri='https://example.test/changed'
WHERE consent_type='privacy_notice' AND policy_version='v1.0';`, 'ERROR: append-only relation cannot be updated or deleted', 'Negative; insert new version']
];

const reviewRows = [
  ['Architecture', 'Separate backend authentication confirmed', 'Accepted', 'core.auth_sessions is application-managed; Supabase auth schema is not the session source.'],
  ['Original scope', 'Seven Excel tables retained', 'Accepted', 'users, identities, contacts, verifications, OTP, consents, lifecycle history.'],
  ['Supporting table', 'core.auth_sessions', 'Tech-lead review', 'Added for Question 5: custom session and refresh-token revocation.'],
  ['Supporting table', 'core.policy_versions', 'Tech-lead review', 'Added for Question 8: exact immutable accepted-policy provenance.'],
  ['Session design', 'Keep or remove session_family_id', 'Decision needed', 'Current rotation updates one row; family ID has limited value unless token generations use separate rows/history.'],
  ['Session design', 'Constrain revocation_reason values', 'Decision needed', 'Currently non-null is enforced, but value is free text.'],
  ['Session operations', 'Expired status maintenance', 'Decision needed', 'Validation rejects expired timestamps; worker/backend should optionally mark stored status expired.'],
  ['Session operations', 'Access-token revocation strategy', 'Decision needed', 'Use short-lived access token plus session check/cache for sensitive or immediate revocation.'],
  ['Policy governance', 'Approved policy owner and immutable storage location', 'Decision needed', 'Tech/product/legal owner supplies content, dates, URI, and hash.'],
  ['Security', 'HMAC key management and rotation', 'Decision needed before real data', 'Keys must remain in backend secret manager; never in DB rows or Git.'],
  ['Data scope', 'Synthetic data only', 'Accepted', 'No real Aadhaar, PAN, OTP, token, or personal identity data in review project.'],
  ['Deployment', 'Git migrations are executable source of truth', 'Accepted', 'Only reviewed migrations are applied by lead/integrator.']
];

// Cover sheet
const cover = workbook.addWorksheet('00 Cover', { properties: { tabColor: { argb: `FF${colors.navy}` } }, views: [{ showGridLines: false }] });
cover.columns = Array.from({ length: 8 }, () => ({ width: 16 }));
cover.mergeCells('A1:H3');
cover.getCell('A1').value = 'ADITYA\nIDENTITY DATABASE DESIGN';
cover.getCell('A1').font = { name: 'Aptos Display', size: 28, bold: true, color: { argb: `FF${colors.white}` } };
cover.getCell('A1').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.navy}` } };
cover.getCell('A1').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getRow(1).height = 38; cover.getRow(2).height = 38; cover.getRow(3).height = 38;
cover.mergeCells('A5:H5');
cover.getCell('A5').value = 'Enterprise project: users, authentication, verification, consent, sessions, and account lifecycle';
cover.getCell('A5').font = { name: 'Aptos', size: 14, italic: true, color: { argb: `FF${colors.blue}` } };
cover.getCell('A5').alignment = { horizontal: 'center', wrapText: true };
const coverFacts = [
  ['Owner', 'Aditya — team lead and identity database owner'],
  ['Database', 'Supabase PostgreSQL — linked project internship'],
  ['Architecture', 'Separate backend authentication; core schema is the application source of truth'],
  ['Implemented scope', '7 original Excel tables + 2 requirement-derived supporting tables'],
  ['Constraint levels', 'Column-level constraints and table/cross-column constraints are documented separately'],
  ['Security', 'RLS enabled; client roles denied; service_role backend only; synthetic data only'],
  ['Document date', '11 November 2026'],
  ['Executable source of truth', 'supabase/migrations/*.sql']
];
let coverRow = 8;
for (const [label, value] of coverFacts) {
  cover.mergeCells(coverRow, 1, coverRow, 2);
  cover.mergeCells(coverRow, 3, coverRow, 8);
  cover.getCell(coverRow, 1).value = label;
  cover.getCell(coverRow, 3).value = value;
  cover.getCell(coverRow, 1).font = { bold: true, color: { argb: `FF${colors.white}` } };
  cover.getCell(coverRow, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.blue}` } };
  cover.getCell(coverRow, 3).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${coverRow % 2 ? colors.white : colors.paleBlue}` } };
  for (let c = 1; c <= 8; c += 1) {
    const cell = cover.getCell(coverRow, c);
    cell.border = border(); cell.alignment = { vertical: 'middle', wrapText: true };
  }
  cover.getRow(coverRow).height = 30;
  coverRow += 1;
}
cover.mergeCells('A18:H20');
cover.getCell('A18').value = 'How to use this workbook\n1. Review the catalogue and column design.  2. Confirm both constraint levels.  3. Review DDL and backend functions.  4. Run SQL tests separately in Supabase SQL Editor.  5. Record tech-lead decisions in the final sheet.';
cover.getCell('A18').alignment = { vertical: 'middle', horizontal: 'left', wrapText: true };
cover.getCell('A18').font = { size: 12, bold: true, color: { argb: `FF${colors.navy}` } };
cover.getCell('A18').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightGreen}` } };
cover.getCell('A18').border = border();
cover.mergeCells('A22:H23');
cover.getCell('A22').value = 'YELLOW HIGHLIGHT = change implemented in the Aditya hardening update on 11 November 2026';
cover.getCell('A22').font = { size: 12, bold: true, color: { argb: `FF${colors.black}` } };
cover.getCell('A22').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.changeYellow}` } };
cover.getCell('A22').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getCell('A22').border = border();

addGridSheet('01 Table Catalogue', 'Aditya Table Catalogue', 'Original Excel scope is distinguished from later requirement-derived support tables.', ['Table', 'Source', 'Purpose', 'Responsibility', 'Cardinality'], tables, [28, 24, 58, 30, 20], colors.teal);

const columnSheet = addGridSheet('02 Column Design', 'Complete Column Design', 'Every implemented Aditya-owned column: datatype, null/default behavior, and business meaning.', ['Table', 'Column group', 'Column', 'Datatype', 'Required / default', 'Meaning and enforced rule'], columnRows, [27, 24, 30, 22, 27, 70], colors.blue);
for (let r = 5; r <= columnSheet.rowCount; r += 1) columnSheet.getRow(r).height = 42;

const columnConstraintRows = columnRows.map(row => [row[0], row[2], row[3], row[4] || 'See rule', row[5], 'Column level']);
addGridSheet('03 Column Constraints', 'Constraint Level 1 — Column Constraints', 'Datatype, required/default, format, allowed value, and per-column validation.', ['Table', 'Column', 'Datatype', 'Nullability / default', 'Constraint or validation rule', 'Level'], columnConstraintRows, [27, 30, 20, 28, 76, 15], colors.green);

addGridSheet('04 Table Constraints', 'Constraint Level 2 — Table and Cross-Column Constraints', 'Named PK, FK, unique, check, index, append-only, and trigger-enforced rules.', ['Table', 'Constraint / rule name', 'Kind', 'Columns / scope', 'Business rule'], tableConstraints, [27, 38, 20, 36, 82], colors.purple);

addGridSheet('05 Relationships', 'Foreign Keys and Module Relationships', 'All Aditya parent/child relationships use the stable random core.users.user_id business key.', ['Child column(s)', 'Parent column(s)', 'Cardinality', 'Delete behavior', 'Purpose'], relationships, [44, 44, 20, 24, 52], colors.teal);

addGridSheet('06 Allowed Values', 'Controlled Values and Status Codes', 'Application and database code must use these values exactly.', ['Table', 'Column', 'Allowed values', 'Default / note'], valueLists, [34, 35, 95, 40], colors.amber);

// Exact DDL sheet
const ddlRows = [];
for (const [table] of tables) {
  const sourceSql = ['core.policy_versions', 'core.auth_sessions'].includes(table) ? lifecycleSql : coreSql;
  let ddl = extractCreate(sourceSql, table);
  const alters = extractAlterStatements(lifecycleSql, table);
  const hardeningAlters = extractAlterStatements(hardeningSql, table);
  if (alters.length || hardeningAlters.length) ddl += `\n\n-- Later ALTER statements\n${[...alters,...hardeningAlters].join('\n\n')}`;
  ddlRows.push([table, table.startsWith('core.policy') || table.startsWith('core.auth_sessions') ? '20261110100000_identity_lifecycle_completion.sql' : '20261109090000_core_identity.sql', ddl]);
}
const ddlSheet = addGridSheet('07 DDL Statements', 'Exact Table DDL', 'Copied from the implemented migration files. Git migrations—not this workbook—remain the executable source of truth.', ['Table', 'Migration source', 'CREATE TABLE and related ALTER TABLE DDL'], ddlRows, [28, 52, 125], colors.navy);
for (let r = 5; r <= ddlSheet.rowCount; r += 1) {
  ddlSheet.getCell(r, 3).font = { name: 'Consolas', size: 9, color: { argb: `FF${colors.black}` } };
  ddlSheet.getRow(r).height = 240;
}

addGridSheet('08 Functions Triggers', 'Backend Functions, Triggers, and Security Gates', 'Sensitive operations are controlled through service-role backend functions and database triggers.', ['Name', 'Type', 'What it handles', 'Access / table'], functionRows, [42, 24, 92, 30], colors.purple);

addGridSheet('09 Business Flows', 'End-to-End Business Flows', 'How registration, verification, access, sessions, consent, and deletion operate together.', ['Flow', 'Starting action', 'Database behavior', 'Important result'], flowRows, [28, 48, 90, 56], colors.teal);

const testRows = [...parseReadOnlyTests(testSql), ...negativeTests];
const testSheet = addGridSheet('10 SQL Tests', 'SQL Verification Tests', 'Run one query at a time in Supabase SQL Editor. Read-only tests expect PASS; negative tests expect the stated error.', ['Test ID', 'Test name', 'What it proves', 'SQL query', 'Expected output', 'Safety'], testRows, [13, 43, 65, 110, 48, 28], colors.green);
for (let r = 5; r <= testSheet.rowCount; r += 1) {
  testSheet.getCell(r, 4).font = { name: 'Consolas', size: 9 };
  testSheet.getRow(r).height = 125;
}

const reviewSheet = addGridSheet('11 Tech Lead Review', 'Tech-Lead Review and Decisions', 'Use this sheet during the design discussion. Update status only through a reviewed workbook revision or Git change.', ['Area', 'Decision / topic', 'Current status', 'Explanation or required action'], reviewRows, [26, 50, 24, 95], colors.red);
for (let r = 5; r <= reviewSheet.rowCount; r += 1) {
  const status = reviewSheet.getCell(r, 3);
  if (/Decision needed|review/i.test(String(status.value))) {
    status.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightAmber}` } };
    status.font = { bold: true, color: { argb: `FF${colors.amber}` } };
  } else {
    status.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightGreen}` } };
    status.font = { bold: true, color: { argb: `FF${colors.green}` } };
  }
}

// Workbook-wide finishing touches.
for (const ws of workbook.worksheets) {
  if (ws.name !== '00 Cover') highlightChangedRows(ws);
  ws.properties.defaultRowHeight = 18;
  ws.pageSetup.paperSize = 9; // A4
  ws.pageSetup.fitToPage = true;
  ws.pageSetup.horizontalCentered = true;
  ws.eachRow(row => row.eachCell(cell => { if (!cell.alignment) cell.alignment = { vertical: 'top', wrapText: true }; }));
}

let writtenOutput = output;
try {
  await workbook.xlsx.writeFile(output);
} catch (error) {
  if (error?.code !== 'EBUSY') throw error;
  writtenOutput = path.join(docsDir, 'Aditya_Identity_Database_Design_YELLOW_CHANGES.xlsx');
  await workbook.xlsx.writeFile(writtenOutput);
  console.log(`Original workbook is open/locked; wrote highlighted copy instead.`);
}
console.log(writtenOutput);
console.log(`Sheets: ${workbook.worksheets.length}`);
console.log(`Column design rows: ${columnRows.length}`);
console.log(`SQL tests: ${testRows.length}`);
