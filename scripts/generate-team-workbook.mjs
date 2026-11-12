import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ExcelJS from 'exceljs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const migrationDir = path.join(root, 'supabase', 'migrations');
const output = path.join(root, 'docs', 'Team_Database_Complete_Design.xlsx');

// The workbook is generated from every versioned migration so later ALTER TABLE
// changes cannot silently disappear from the documentation.
const migrationNames = fs.readdirSync(migrationDir)
  .filter(name => /^\d+_.+\.sql$/i.test(name))
  .sort();

const migrations = migrationNames.map(name => ({
  name,
  sql: fs.readFileSync(path.join(migrationDir, name), 'utf8')
}));

const colors = {
  navy: '17365D', blue: '1F4E78', teal: '0F6B78', green: '2E7D32',
  amber: 'C65911', red: 'C00000', purple: '7030A0', gray: '666666',
  white: 'FFFFFF', black: '1F1F1F', paleBlue: 'EAF3F8', lightBlue: 'D9EAF7',
  lightGreen: 'E2F0D9', lightAmber: 'FCE4D6', lightRed: 'F4CCCC', lightGray: 'F2F2F2',
  changeYellow: 'FFFF00'
};

const highlightedMigrations = [
  '20261110100500_reconcile_live_catalog.sql',
  '20261111100000_aditya_gap_hardening.sql',
  '20261112100000_account_erasure_workflow.sql',
  '20261112101000_account_erasure_security.sql'
];

function highlightAdityaHardeningRows(ws, headerRow = 4) {
  for (let rowNo = headerRow + 1; rowNo <= ws.rowCount; rowNo += 1) {
    const row = ws.getRow(rowNo);
    const text = row.values.slice(1).map(value => String(value ?? '')).join(' ').toLowerCase();
    if (!highlightedMigrations.some(name => text.includes(name.toLowerCase()))) continue;
    row.eachCell({ includeEmpty: true }, cell => {
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.changeYellow}` } };
      cell.font = { ...(cell.font ?? {}), color: { argb: `FF${colors.black}` } };
    });
  }
}

const ownerColors = {
  Aditya: colors.navy,
  Thanushree: '4472C4',
  Prajwal: '548235',
  Koushik: 'BF9000',
  Rajath: '8064A2',
  Tejaswini: 'C00000',
  Skanda: '008C95',
  Mahera: 'C55A11'
};

const ownership = {
  Aditya: [
    'core.users', 'core.auth_identities', 'core.user_contacts', 'core.user_verifications',
    'core.user_otp_challenges', 'core.user_consents', 'core.user_status_history',
    'core.policy_versions', 'core.auth_sessions', 'core.account_deletion_matrix'
  ],
  Thanushree: [
    'core.interest_categories', 'core.interest_subcategories', 'core.interests',
    'core.prompt_catalogue', 'core.profiles', 'core.user_interests',
    'core.profile_prompts', 'core.notification_preferences', 'core.user_languages'
  ],
  Prajwal: [
    'core.connection_intents', 'core.connection_requests', 'core.blocks',
    'core.user_pseudonyms', 'core.profile_media'
  ],
  Koushik: [
    'core.outbox_events', 'core.notifications', 'core.account_data_jobs',
    'core.account_data_job_steps', 'core.media_deletion_jobs'
  ],
  Rajath: [
    'core.discovery_dismissals', 'core.acknowledgements', 'core.conversations',
    'core.conversation_participants', 'core.messages', 'core.message_read_cursors'
  ],
  Tejaswini: [
    'safety.admin_users', 'safety.report_category_subcategories', 'safety.reports',
    'safety.moderation_actions', 'safety.moderation_appeals', 'safety.legal_holds'
  ],
  Skanda: [
    'analytics.product_events', 'analytics.discovery_impressions',
    'safety.report_evidence', 'audit.audit_product_event'
  ],
  Mahera: [
    'core.notification_categories', 'core.notification_category_channels',
    'core.connection_closed_reasons', 'core.notification_category_preferences',
    'core.device_tokens', 'core.connections', 'core.relations'
  ]
};

const memberSources = [
  ['Aditya', 'Aditya_Data_Dictionary (4).xlsx', 'Identity, authentication, contacts, KYC, OTP, consent, lifecycle', 7, '2 supporting tables plus the shared deletion-governance matrix were later added'],
  ['Thanushree', 'Thanushree_kh_Data_Dictionary.xlsx', 'Interests, profiles, prompts, preferences, languages', 9, 'Profile and catalogue module'],
  ['Prajwal', 'Prajwal_Data_Dictionary_Final (2).xlsx', 'Connection intents/requests, blocks, pseudonyms, profile media', 5, 'Social discovery entry module'],
  ['Koushik', 'Koushik_Data_Dictionary Updated Original 1 (1).xlsx', 'Outbox, notifications, exports/deletion jobs, job steps', 5, 'Asynchronous operations module'],
  ['Rajath', 'Rajath_Value-List.xlsx', 'Dismissals, acknowledgements, conversations, messages, participants, cursors', 6, 'Messaging and discovery interaction module'],
  ['Tejaswini', 'Tejaswini_safety_value_list.xlsx', 'Reports, taxonomy, moderation, appeals, legal holds, staff', 6, 'Safety module'],
  ['Skanda', 'Skanda_Data_Dictionary_Final.xlsx', 'Product analytics, discovery analytics, evidence, audit', 4, 'Analytics and audit module'],
  ['Mahera', 'Mahera_Data_Dictionary_FinalLast5.xlsx', 'Notification registries/preferences, device tokens, connections, relations', 7, 'Notification delivery and social relationship module']
];

const purposes = {
  'core.users': 'Master application account and lifecycle state',
  'core.auth_identities': 'Authentication providers linked to a stable user',
  'core.user_contacts': 'Current unique email and phone',
  'core.user_verifications': 'Email, phone, Aadhaar, PAN, and age verification',
  'core.user_otp_challenges': 'OTP signup, login, contact change, and recovery state',
  'core.user_consents': 'Append-only user consent decisions',
  'core.user_status_history': 'Append-only account lifecycle history',
  'core.account_deletion_matrix': 'Reviewed action and legal-hold behavior for account erasure by relation',
  'core.policy_versions': 'Immutable policy-document catalogue',
  'core.auth_sessions': 'Custom-backend login sessions and refresh-token state',
  'core.interest_categories': 'Top-level interest catalogue categories',
  'core.interest_subcategories': 'Interest subcategories within categories',
  'core.interests': 'Curated selectable interests',
  'core.prompt_catalogue': 'Versioned profile prompt definitions',
  'core.profiles': 'User profile presentation and discovery state',
  'core.user_interests': 'User-selected interests and primary interest',
  'core.profile_prompts': 'User answers to profile prompts',
  'core.notification_preferences': 'User-wide notification and quiet-hour preferences',
  'core.user_languages': 'Languages selected by a user',
  'core.connection_intents': 'Catalogue of connection intent options',
  'core.connection_requests': 'Requests from one user to another',
  'core.blocks': 'User block relationships and lifecycle',
  'core.user_pseudonyms': 'Purpose-specific public or analytics aliases',
  'core.profile_media': 'Profile media metadata and lifecycle',
  'core.notification_categories': 'Notification category registry',
  'core.notification_category_channels': 'Allowed category/channel combinations',
  'core.connection_closed_reasons': 'Connection closure reason registry',
  'core.notification_category_preferences': 'Per-user category/channel preference and snooze state',
  'core.device_tokens': 'Protected device registrations for push notifications',
  'core.connections': 'Canonical accepted connection between two users',
  'core.relations': 'User reactions/relations on profile or prompt context',
  'core.discovery_dismissals': 'Profiles dismissed during discovery',
  'core.acknowledgements': 'Structured user acknowledgement events',
  'core.conversations': 'Direct conversation metadata',
  'core.conversation_participants': 'Conversation membership and participant state',
  'core.messages': 'Ordered messages inside conversations',
  'core.message_read_cursors': 'Per-user last-read message cursor',
  'core.outbox_events': 'Transactional events for asynchronous workers',
  'core.notifications': 'User notification records and delivery state',
  'core.account_data_jobs': 'Account export, deletion, or privacy jobs',
  'core.account_data_job_steps': 'Individual processing steps for account-data jobs',
  'core.media_deletion_jobs': 'Asynchronous media deletion work',
  'safety.admin_users': 'Safety and moderation staff identities',
  'safety.report_category_subcategories': 'Approved safety report taxonomy pairs',
  'safety.reports': 'User-submitted safety reports',
  'safety.moderation_actions': 'Actions taken after safety review',
  'safety.moderation_appeals': 'Appeals against moderation actions',
  'safety.legal_holds': 'Legal preservation and restricted-action controls',
  'analytics.product_events': 'Pseudonymous product telemetry events',
  'analytics.discovery_impressions': 'Pseudonymous discovery impression telemetry',
  'safety.report_evidence': 'Protected evidence attached to reports',
  'audit.audit_product_event': 'Append-only security and operational audit events'
};

function ownerFor(table) {
  return Object.entries(ownership).find(([, tables]) => tables.includes(table))?.[0] ?? 'Shared/Lead';
}

function splitTopLevel(text) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let single = false;
  let double = false;
  let dollarTag = null;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (dollarTag) {
      if (text.startsWith(dollarTag, i)) { i += dollarTag.length - 1; dollarTag = null; }
      continue;
    }
    if (!single && !double && ch === '$') {
      const tag = text.slice(i).match(/^\$[A-Za-z0-9_]*\$/)?.[0];
      if (tag) { dollarTag = tag; i += tag.length - 1; continue; }
    }
    if (!double && ch === "'" && text[i - 1] !== '\\') {
      if (single && text[i + 1] === "'") { i += 1; continue; }
      single = !single; continue;
    }
    if (!single && ch === '"') { double = !double; continue; }
    if (single || double) continue;
    if (ch === '(' || ch === '[') depth += 1;
    else if (ch === ')' || ch === ']') depth -= 1;
    else if (ch === ',' && depth === 0) {
      parts.push(text.slice(start, i).trim()); start = i + 1;
    }
  }
  const final = text.slice(start).trim();
  if (final) parts.push(final);
  return parts;
}

function extractCreateTables() {
  const tables = [];
  for (const migration of migrations) {
    const re = /create table\s+(?:if not exists\s+)?([a-z_][\w]*\.[a-z_][\w]*)\s*\(([\s\S]*?)\n\);/gi;
    for (const match of migration.sql.matchAll(re)) {
      tables.push({
        name: match[1].toLowerCase(),
        body: match[2],
        ddl: match[0].trim(),
        migration: migration.name,
        order: tables.length + 1
      });
    }
  }
  return tables;
}

function parseColumnDefinition(table, definition, migration, source = 'CREATE TABLE') {
  const first = definition.match(/^([a-z_][\w]*)\s+([\s\S]+)$/i);
  if (!first) return null;
  const column = first[1];
  const rest = first[2].trim();
  const marker = rest.search(/\s+(?:generated\s|not\s+null|default\s|primary\s+key|unique(?:\s|$)|references\s|constraint\s|check\s*\()/i);
  const datatype = (marker === -1 ? rest : rest.slice(0, marker)).trim();
  const rules = marker === -1 ? '' : rest.slice(marker).trim();
  const defaultMatch = rules.match(/default\s+(.+?)(?=\s+(?:constraint|references|check|unique|primary\s+key|not\s+null)\b|$)/i);
  const generated = /generated\s+always\s+as\s+identity/i.test(rules);
  const required = /not\s+null|primary\s+key/i.test(rules);
  const pk = /primary\s+key/i.test(rules);
  const unique = /\bunique\b/i.test(rules);
  return {
    table, owner: ownerFor(table), column, datatype,
    required: required ? 'NOT NULL' : 'Nullable',
    defaultValue: generated ? 'Generated identity' : (defaultMatch?.[1]?.trim() ?? ''),
    primaryKey: pk ? 'Yes' : '', unique: unique ? 'Yes' : '',
    rules, migration, source
  };
}

const tableDefs = extractCreateTables();
const tableByName = new Map(tableDefs.map(table => [table.name, table]));
const columns = [];
const constraints = [];
const relationships = [];
const alterStatements = new Map();

for (const table of tableDefs) {
  for (const segment of splitTopLevel(table.body)) {
    if (/^(constraint\s+|primary\s+key|unique\s*\(|check\s*\()/i.test(segment)) {
      const name = segment.match(/^constraint\s+([a-z_][\w]*)/i)?.[1] ?? `${table.name.replace('.', '_')}_inline_rule`;
      const kind = /foreign\s+key/i.test(segment) ? 'FOREIGN KEY'
        : /primary\s+key/i.test(segment) ? 'PRIMARY KEY'
          : /unique/i.test(segment) ? 'UNIQUE'
            : /check/i.test(segment) ? 'CHECK' : 'TABLE RULE';
      constraints.push({ table: table.name, owner: ownerFor(table.name), name, kind, definition: segment, migration: table.migration });
      const fk = segment.match(/foreign\s+key\s*\(([^)]+)\)\s+references\s+([\w.]+)\s*\(([^)]+)\)(?:\s+on\s+delete\s+([a-z ]+))?/i);
      if (fk) relationships.push({ child: table.name, childColumns: fk[1].trim(), parent: fk[2], parentColumns: fk[3].trim(), deleteRule: fk[4]?.trim() ?? 'NO ACTION', owner: ownerFor(table.name), constraint: name });
      continue;
    }
    const column = parseColumnDefinition(table.name, segment, table.migration);
    if (!column) continue;
    columns.push(column);
    if (column.primaryKey) constraints.push({ table: table.name, owner: column.owner, name: `${table.name.replace('.', '_')}_${column.column}_pk`, kind: 'PRIMARY KEY (inline)', definition: `${column.column} ${column.rules}`, migration: table.migration });
    if (column.unique) constraints.push({ table: table.name, owner: column.owner, name: `${table.name.replace('.', '_')}_${column.column}_uq`, kind: 'UNIQUE (inline)', definition: `${column.column} ${column.rules}`, migration: table.migration });
    const fk = column.rules.match(/references\s+([\w.]+)\s*\(([^)]+)\)(?:\s+on\s+delete\s+([a-z ]+?))?(?=\s+(?:constraint|check|unique)|$)/i);
    if (fk) relationships.push({ child: table.name, childColumns: column.column, parent: fk[1], parentColumns: fk[2].trim(), deleteRule: fk[3]?.trim() ?? 'NO ACTION', owner: column.owner, constraint: 'Inline FK' });
  }
}

// Apply ADD COLUMN, ALTER COLUMN SET NOT NULL, and ADD CONSTRAINT migrations.
for (const migration of migrations) {
  const alterRe = /alter table\s+([a-z_][\w]*\.[a-z_][\w]*)\s+([\s\S]*?);/gi;
  for (const match of migration.sql.matchAll(alterRe)) {
    const table = match[1].toLowerCase();
    if (!tableByName.has(table)) continue;
    if (!alterStatements.has(table)) alterStatements.set(table, []);
    alterStatements.get(table).push(`-- ${migration.name}\n${match[0].trim()}`);
    for (const operation of splitTopLevel(match[2])) {
      const addColumn = operation.match(/^add column\s+([\s\S]+)$/i);
      if (addColumn) {
        const parsed = parseColumnDefinition(table, addColumn[1], migration.name, 'ALTER TABLE ADD COLUMN');
        if (parsed && !columns.some(c => c.table === table && c.column === parsed.column)) columns.push(parsed);
        continue;
      }
      const setNotNull = operation.match(/^alter column\s+([a-z_][\w]*)\s+set not null/i);
      if (setNotNull) {
        const existing = columns.find(c => c.table === table && c.column === setNotNull[1]);
        if (existing) { existing.required = 'NOT NULL'; existing.rules = `${existing.rules} ALTERED TO NOT NULL`.trim(); }
        continue;
      }
      const addConstraint = operation.match(/^add constraint\s+([a-z_][\w]*)\s+([\s\S]+)$/i);
      if (addConstraint) {
        const definition = addConstraint[2];
        const kind = /foreign\s+key/i.test(definition) ? 'FOREIGN KEY' : /unique/i.test(definition) ? 'UNIQUE' : /check/i.test(definition) ? 'CHECK' : 'TABLE RULE';
        constraints.push({ table, owner: ownerFor(table), name: addConstraint[1], kind, definition, migration: migration.name });
        const fk = definition.match(/foreign\s+key\s*\(([^)]+)\)\s+references\s+([\w.]+)\s*\(([^)]+)\)(?:\s+on\s+delete\s+([a-z ]+))?/i);
        if (fk) relationships.push({ child: table, childColumns: fk[1].trim(), parent: fk[2], parentColumns: fk[3].trim(), deleteRule: fk[4]?.trim() ?? 'NO ACTION', owner: ownerFor(table), constraint: addConstraint[1] });
      }
    }
  }
}

// Indexes are important cross-row constraints and performance structures.
const indexes = [];
for (const migration of migrations) {
  const re = /create\s+(unique\s+)?index\s+([a-z_][\w]*)\s+on\s+([a-z_][\w]*\.[a-z_][\w]*)\s*([\s\S]*?);/gi;
  for (const match of migration.sql.matchAll(re)) {
    if (!tableByName.has(match[3].toLowerCase())) continue;
    indexes.push({ table: match[3].toLowerCase(), owner: ownerFor(match[3].toLowerCase()), name: match[2], kind: match[1] ? 'UNIQUE INDEX' : 'INDEX', definition: match[4].trim(), migration: migration.name });
  }
}
constraints.push(...indexes);

// Function and trigger inventory with exact executable definition.
const routines = [];
const triggers = [];
for (const migration of migrations) {
  const functionRe = /create or replace function\s+([\w.]+)\s*\(([\s\S]*?)\)\s*returns\s+([^\r\n]+)[\s\S]*?\$\$;/gi;
  for (const match of migration.sql.matchAll(functionRe)) {
    const ddl = match[0].trim();
    const touched = [...ddl.matchAll(/(?:from|join|update|insert into|delete from)\s+([a-z_][\w]*\.[a-z_][\w]*)/gi)].map(m => m[1]);
    const owners = [...new Set(touched.map(ownerFor))].join(', ') || 'Shared/Lead';
    routines.push({ name: match[1], signature: match[2].replace(/\s+/g, ' ').trim(), returns: match[3].trim(), security: /security definer/i.test(ddl) ? 'SECURITY DEFINER' : 'Invoker', owners, migration: migration.name, ddl });
  }
  const triggerRe = /create trigger\s+([a-z_][\w]*)\s+([\s\S]*?);/gi;
  for (const match of migration.sql.matchAll(triggerRe)) {
    const ddl = match[0].trim();
    const table = ddl.match(/\son\s+([\w.]+)/i)?.[1] ?? '';
    triggers.push({ name: match[1], table, owner: ownerFor(table), migration: migration.name, ddl });
  }
}

const workbook = new ExcelJS.Workbook();
workbook.creator = 'Student Enterprise Database Team';
workbook.lastModifiedBy = 'OpenAI Codex';
workbook.created = new Date('2026-11-11T00:00:00+05:30');
workbook.modified = new Date('2026-11-11T00:00:00+05:30');
workbook.title = 'Complete Team Database Design';
workbook.subject = 'All eight team members: implemented schema, columns, constraints, foreign keys, DDL, routines, and tests';
workbook.company = 'Student Enterprise Database Project';

function border() {
  return {
    top: { style: 'thin', color: { argb: 'FFD0D7DE' } }, left: { style: 'thin', color: { argb: 'FFD0D7DE' } },
    bottom: { style: 'thin', color: { argb: 'FFD0D7DE' } }, right: { style: 'thin', color: { argb: 'FFD0D7DE' } }
  };
}

function styleTitle(ws, title, subtitle, lastColumn, color = colors.navy) {
  ws.mergeCells(1, 1, 1, lastColumn);
  const titleCell = ws.getCell(1, 1);
  titleCell.value = title;
  titleCell.font = { name: 'Aptos Display', size: 20, bold: true, color: { argb: `FF${colors.white}` } };
  titleCell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${color}` } };
  titleCell.alignment = { vertical: 'middle', horizontal: 'left' };
  ws.getRow(1).height = 34;
  ws.mergeCells(2, 1, 2, lastColumn);
  const subtitleCell = ws.getCell(2, 1);
  subtitleCell.value = subtitle;
  subtitleCell.font = { name: 'Aptos', size: 10, italic: true, color: { argb: `FF${colors.gray}` } };
  subtitleCell.alignment = { vertical: 'middle', wrapText: true };
  ws.getRow(2).height = 30;
}

function styleGrid(ws, headerRow = 4, headerColor = colors.blue) {
  ws.getRow(headerRow).height = 30;
  ws.getRow(headerRow).eachCell(cell => {
    cell.font = { name: 'Aptos', size: 10, bold: true, color: { argb: `FF${colors.white}` } };
    cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${headerColor}` } };
    cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
    cell.border = border();
  });
  for (let r = headerRow + 1; r <= ws.rowCount; r += 1) {
    ws.getRow(r).eachCell({ includeEmpty: true }, cell => {
      cell.font = { name: 'Aptos', size: 10, color: { argb: `FF${colors.black}` } };
      cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${r % 2 ? colors.white : colors.paleBlue}` } };
      cell.alignment = { vertical: 'top', wrapText: true };
      cell.border = border();
    });
  }
  ws.views = [{ state: 'frozen', ySplit: headerRow }];
  ws.autoFilter = { from: { row: headerRow, column: 1 }, to: { row: headerRow, column: ws.columnCount } };
  ws.pageSetup = { orientation: 'landscape', fitToPage: true, fitToWidth: 1, fitToHeight: 0, paperSize: 9, margins: { left: 0.2, right: 0.2, top: 0.5, bottom: 0.5, header: 0.2, footer: 0.2 } };
  ws.headerFooter.oddFooter = '&LComplete Team Database&CPage &P of &N&R11 Nov 2026';
}

function addGridSheet(name, title, subtitle, headers, rows, widths, color = colors.blue) {
  const ws = workbook.addWorksheet(name, { properties: { tabColor: { argb: `FF${color}` } } });
  styleTitle(ws, title, subtitle, headers.length, color);
  ws.addRow([]); ws.addRow(headers);
  rows.forEach(row => ws.addRow(row));
  widths.forEach((width, index) => { ws.getColumn(index + 1).width = width; });
  styleGrid(ws, 4, color);
  return ws;
}

// Cover
const cover = workbook.addWorksheet('00 Cover', { properties: { tabColor: { argb: `FF${colors.navy}` } }, views: [{ showGridLines: false }] });
cover.columns = Array.from({ length: 8 }, () => ({ width: 17 }));
cover.mergeCells('A1:H3');
cover.getCell('A1').value = 'COMPLETE TEAM DATABASE\nDESIGN AND VERIFICATION WORKBOOK';
cover.getCell('A1').font = { name: 'Aptos Display', size: 27, bold: true, color: { argb: `FF${colors.white}` } };
cover.getCell('A1').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.navy}` } };
cover.getCell('A1').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getRow(1).height = 38; cover.getRow(2).height = 38; cover.getRow(3).height = 38;
cover.mergeCells('A5:H5');
cover.getCell('A5').value = 'Eight owners · 51 repository-managed tables · one shared Supabase PostgreSQL database';
cover.getCell('A5').font = { size: 15, italic: true, color: { argb: `FF${colors.blue}` } };
cover.getCell('A5').alignment = { horizontal: 'center' };
const facts = [
  ['Lead', 'Aditya'],
  ['Project', 'Supabase internship — synthetic review data only'],
  ['Architecture', 'Separate backend authentication; Git migrations are the executable source of truth'],
  ['Scope', `${tableDefs.length} tables, ${columns.length} columns, ${constraints.length} constraints/indexes, ${relationships.length} foreign-key relationships`],
  ['Members', 'Aditya, Thanushree, Prajwal, Koushik, Rajath, Tejaswini, Skanda, Mahera'],
  ['Security', 'RLS enabled; direct anon/authenticated access revoked; service backend and sanitized reviewer views'],
  ['Document date', '11 November 2026'],
  ['Review method', 'Each owner reviews their sheet, constraints, DDL, tests, and cross-module relationships']
];
let rowNo = 8;
for (const [label, value] of facts) {
  cover.mergeCells(rowNo, 1, rowNo, 2); cover.mergeCells(rowNo, 3, rowNo, 8);
  cover.getCell(rowNo, 1).value = label; cover.getCell(rowNo, 3).value = value;
  cover.getCell(rowNo, 1).font = { bold: true, color: { argb: `FF${colors.white}` } };
  cover.getCell(rowNo, 1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.blue}` } };
  cover.getCell(rowNo, 3).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${rowNo % 2 ? colors.white : colors.paleBlue}` } };
  for (let c = 1; c <= 8; c += 1) { cover.getCell(rowNo, c).border = border(); cover.getCell(rowNo, c).alignment = { vertical: 'middle', wrapText: true }; }
  cover.getRow(rowNo).height = 30; rowNo += 1;
}
cover.mergeCells('A18:H20');
cover.getCell('A18').value = 'Owner review sequence\n1. Open your member sheet.  2. Confirm every table and column.  3. Review both constraint levels and foreign keys.  4. Inspect exact DDL.  5. Run relevant SQL tests in an isolated/test environment.  6. Record corrections through GitHub migrations.';
cover.getCell('A18').alignment = { vertical: 'middle', wrapText: true };
cover.getCell('A18').font = { size: 12, bold: true, color: { argb: `FF${colors.navy}` } };
cover.getCell('A18').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightGreen}` } };
cover.getCell('A18').border = border();
cover.mergeCells('A22:H23');
cover.getCell('A22').value = 'YELLOW HIGHLIGHT = recently implemented hardening or account-erasure change';
cover.getCell('A22').font = { size: 12, bold: true, color: { argb: `FF${colors.black}` } };
cover.getCell('A22').fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.changeYellow}` } };
cover.getCell('A22').alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
cover.getCell('A22').border = border();

const ownershipRows = memberSources.map(([owner, source, responsibility, originalCount, note]) => [owner, responsibility, originalCount, ownership[owner].length, source, note]);
addGridSheet('01 Ownership', 'Team Ownership and Source Workbooks', 'Implemented table ownership is preserved while cross-module relationships are reviewed together.', ['Owner', 'Main responsibility', 'Original primary tables', 'Implemented owned tables', 'Source workbook', 'Scope note'], ownershipRows, [19, 65, 20, 22, 55, 70], colors.teal);

const catalogueRows = tableDefs.map(table => [table.order, ownerFor(table.name), table.name, purposes[table.name] ?? 'Implemented application relation', columns.filter(c => c.table === table.name).length, constraints.filter(c => c.table === table.name).length, table.migration]);
addGridSheet('02 Table Catalogue', 'Complete Implemented Table Catalogue', 'All repository-managed physical tables in migration dependency order.', ['Order', 'Owner', 'Table', 'Purpose', 'Columns', 'Constraints / indexes', 'Creation migration'], catalogueRows, [10, 18, 40, 72, 12, 20, 48], colors.blue);

const columnRows = columns.sort((a, b) => tableDefs.findIndex(t => t.name === a.table) - tableDefs.findIndex(t => t.name === b.table)).map(c => [c.owner, c.table, c.column, c.datatype, c.required, c.defaultValue, c.primaryKey, c.unique, c.rules, c.source, c.migration]);
const columnSheet = addGridSheet('03 All Columns', 'Complete Implemented Column Dictionary', 'Level 1: datatype, nullability, default, inline constraints, and source for every physical column.', ['Owner', 'Table', 'Column', 'Datatype', 'Required?', 'Default / generation', 'PK', 'Unique', 'Inline rules / references', 'Created through', 'Migration'], columnRows, [18, 38, 31, 25, 15, 30, 10, 11, 95, 24, 48], colors.green);
for (let r = 5; r <= columnSheet.rowCount; r += 1) columnSheet.getRow(r).height = 44;

const constraintRows = constraints.map(c => [c.owner, c.table, c.name, c.kind, c.definition, c.migration]);
const constraintSheet = addGridSheet('04 Table Constraints', 'Table, Cross-Column, and Index Constraints', 'Level 2: primary keys, composite rules, foreign keys, uniqueness, CHECK constraints, and indexes.', ['Owner', 'Table', 'Constraint / index', 'Kind', 'Exact SQL definition', 'Migration'], constraintRows, [18, 38, 44, 20, 115, 48], colors.purple);
for (let r = 5; r <= constraintSheet.rowCount; r += 1) constraintSheet.getRow(r).height = 60;

const relationshipRows = relationships.map(r => [r.owner, r.child, r.childColumns, r.parent, r.parentColumns, r.deleteRule, r.constraint, ownerFor(r.parent)]);
addGridSheet('05 Foreign Keys', 'Foreign-Key and Cross-Module Relationship Map', 'Child owners must review target key type, deletion behavior, and parent-owner contract.', ['Child owner', 'Child table', 'Child column(s)', 'Parent table', 'Parent column(s)', 'ON DELETE', 'Constraint', 'Parent owner'], relationshipRows, [18, 40, 34, 40, 34, 20, 38, 18], colors.teal);

const ddlRows = tableDefs.map(table => {
  const alters = alterStatements.get(table) ?? [];
  const finalDdl = alters.length ? `${table.ddl}\n\n-- Later ALTER TABLE statements\n${alters.join('\n\n')}` : table.ddl;
  return [ownerFor(table.name), table.name, purposes[table.name], table.migration, finalDdl];
});
const ddlSheet = addGridSheet('06 Exact DDL', 'Exact CREATE and ALTER TABLE DDL', 'Executable definitions extracted from versioned migration files, including later column, constraint, and table-security alterations.', ['Owner', 'Table', 'Purpose', 'Creation migration', 'Final CREATE TABLE + related ALTER TABLE DDL'], ddlRows, [18, 40, 62, 48, 125], colors.navy);
for (let r = 5; r <= ddlSheet.rowCount; r += 1) { ddlSheet.getCell(r, 5).font = { name: 'Consolas', size: 9 }; ddlSheet.getRow(r).height = 245; }

const routineRows = routines.map(r => [r.name, r.signature, r.returns, r.security, r.owners, r.migration, r.ddl]);
const routineSheet = addGridSheet('07 Functions', 'Shared Database Functions', 'Transactional routines, authorization gates, worker operations, and security-definer boundaries.', ['Function', 'Parameters', 'Returns', 'Security', 'Related owner(s)', 'Migration', 'Exact DDL'], routineRows, [39, 65, 24, 20, 30, 48, 120], colors.purple);
for (let r = 5; r <= routineSheet.rowCount; r += 1) { routineSheet.getCell(r, 7).font = { name: 'Consolas', size: 8 }; routineSheet.getRow(r).height = 210; }

const triggerRows = triggers.map(t => [t.owner, t.table, t.name, t.migration, t.ddl]);
addGridSheet('08 Triggers', 'Database Trigger Inventory', 'Automatic validation, timestamp, lifecycle, synchronization, append-only, and audit behavior.', ['Owner', 'Table', 'Trigger', 'Migration', 'Exact trigger DDL'], triggerRows, [18, 40, 50, 48, 110], colors.amber);

const securityRows = [
  ['All application tables', 'RLS enabled', 'All core, safety, analytics, and audit physical tables', 'Blocks accidental direct exposure; grants still matter.'],
  ['anon', 'No application schema/table/function privileges', 'core, safety, analytics, audit', 'Frontend anonymous role cannot access protected application relations.'],
  ['authenticated', 'No application schema/table/function privileges', 'core, safety, analytics, audit', 'Separate backend authentication means client JWT role is not the application authorization source.'],
  ['service_role', 'USAGE + table/sequence/function privileges', 'Protected schemas', 'Trusted backend only; key must never reach browser/mobile client.'],
  ['student_database_reviewer', 'SELECT on approved review views only', 'review schema', 'NOLOGIN role and no mutation/privileged routine execution.'],
  ['Append-only data', 'Update/delete rejected', 'consents, lifecycle history, policy versions, audit events', 'Preserves evidence and accountability.'],
  ['Sensitive identity', 'Masked/hash/reference only', 'Aadhaar, PAN, OTP, tokens, IP', 'Raw Aadhaar/PAN, plaintext OTP, and plaintext refresh tokens are forbidden.'],
  ['Review project', 'Synthetic data only', 'All modules', 'Production PII must not be loaded until approved security/privacy review.']
];
addGridSheet('09 Security', 'Security, Roles, RLS, and Sensitive-Data Rules', 'Database administrator access, backend service access, and student reviewer access are separate responsibilities.', ['Subject', 'Control', 'Scope', 'Meaning'], securityRows, [32, 45, 50, 90], colors.red);

function quoted(column) { return column.split(',').map(c => c.trim()).join(', '); }
function fkTest(rel, index) {
  const childCols = rel.childColumns.split(',').map(c => c.trim());
  const parentCols = rel.parentColumns.split(',').map(c => c.trim());
  if (childCols.length !== parentCols.length) return null;
  const joins = childCols.map((c, i) => `p.${parentCols[i]} = c.${c}`).join('\n AND ');
  const notNull = childCols.map(c => `c.${c} IS NOT NULL`).join('\n  AND ');
  return [
    `FK${String(index + 1).padStart(3, '0')}`,
    rel.owner,
    `No orphan: ${rel.child} → ${rel.parent}`,
    `SELECT COUNT(*) AS orphan_rows\nFROM ${rel.child} c\nLEFT JOIN ${rel.parent} p\n  ON ${joins}\nWHERE ${notNull}\n  AND p.${parentCols[0]} IS NULL;`,
    'orphan_rows = 0',
    'Read-only'
  ];
}

const testRows = relationships.map(fkTest).filter(Boolean);
for (const [owner, ownerTables] of Object.entries(ownership)) {
  const list = ownerTables.map(table => `'${table.split('.')[1]}'`).join(', ');
  testRows.push([
    `COUNT-${owner.toUpperCase()}`,
    owner,
    `${owner} table row counts`,
    `SELECT module, relation, row_count\nFROM review.team_module_counts\nWHERE relation IN (${list})\nORDER BY relation;`,
    'One count row per review-visible owned relation',
    'Read-only'
  ]);
}
testRows.push(['RLS-001', 'Lead / all', 'Every application table has RLS enabled', `SELECT schemaname, tablename\nFROM pg_tables\nWHERE schemaname IN ('core','safety','analytics','audit')\n  AND NOT rowsecurity\nORDER BY schemaname, tablename;`, '0 rows', 'Read-only']);
testRows.push(['ADITYA-001', 'Aditya', 'Incomplete verification never reaches main_app', `SELECT u.user_id\nFROM core.users u\nJOIN core.user_verifications v USING (user_id)\nWHERE core.user_access_level(u.user_id)='main_app'\n  AND (v.email_status<>'verified' OR v.phone_status<>'verified'\n    OR v.aadhaar_status<>'verified' OR v.pan_status<>'verified');`, '0 rows', 'Read-only']);
const testSheet = addGridSheet('10 SQL Tests', 'Generated Team SQL Verification Tests', 'Run one query at a time. Foreign-key checks expect zero orphan rows; module-count tests demonstrate populated review data.', ['Test ID', 'Owner', 'Test', 'SQL query', 'Expected', 'Safety'], testRows, [16, 18, 66, 110, 48, 20], colors.green);
for (let r = 5; r <= testSheet.rowCount; r += 1) { testSheet.getCell(r, 4).font = { name: 'Consolas', size: 9 }; testSheet.getRow(r).height = 115; }

const validationRows = [
  ['Schema lint', 'npm test', 'Supabase lint against linked database', 'No warnings/errors'],
  ['Schema contract', 'supabase db query --remote --file supabase/tests/schema_contract.sql --read-only', 'Counts, FK integrity, RLS and synthetic fixture contract', 'schema_contract_ok'],
  ['Identity lifecycle', 'powershell -ExecutionPolicy Bypass -File scripts/validate-identity-lifecycle.ps1', 'Registration, OTP, session, lifecycle, consent, and audit behavior', 'identity_lifecycle_contract_ok'],
  ['Account erasure', 'npm run test:erasure', 'Deletion matrix, tombstone, direct-PII removal, retained evidence, and legal-hold blocking', 'account_erasure_contract_ok'],
  ['Team review', 'powershell -ExecutionPolicy Bypass -File scripts/validate-team-review.ps1', 'Full team synthetic fixture and module review', 'Successful rollback validation'],
  ['Pending migrations', 'npx supabase db push --remote --dry-run', 'Cloud migration history matches repository', 'Database is up to date'],
  ['Workbook regeneration', 'npm run docs:team', 'Rebuild this workbook after schema changes', 'Workbook generated and reopens successfully']
];
addGridSheet('11 Validation Guide', 'Validation Commands and Expected Evidence', 'Behavior tests should run in an isolated transaction/test environment; shared-cloud review queries should remain read-only.', ['Validation', 'Command', 'Coverage', 'Expected result'], validationRows, [28, 85, 85, 45], colors.green);

const checklistItems = [
  'All owned tables are present and correctly named.',
  'Every column datatype, nullability, default, and purpose is correct.',
  'Primary keys and unique keys match the intended business identity.',
  'Foreign-key targets, types, and ON DELETE behavior are accepted by both owners.',
  'Allowed values and category/subcategory pairs are complete and stable.',
  'Status transitions have correct timestamp and NULL consistency rules.',
  'Backend functions enforce actor authorization and concurrency/idempotency.',
  'RLS, service backend, reviewer access, and staff privileges are separated.',
  'Sensitive fields are masked, hashed, encrypted, or excluded as required.',
  'Retention, erasure, legal hold, and soft-delete behavior is accepted.',
  'Valid synthetic operations pass and invalid operations fail.',
  'Owner approves the same migration version deployed by the lead.'
];
const reviewRows = Object.keys(ownership).flatMap(owner => checklistItems.map((item, index) => [owner, index + 1, item, 'Pending owner review', '', '']));
const reviewSheet = addGridSheet('12 Review Checklist', 'Owner Verification Checklist', 'Each owner records evidence, corrections, and sign-off. Pending does not mean rejected; it means evidence has not yet been recorded.', ['Owner', '#', 'Review item', 'Status', 'Evidence / issue', 'Owner note'], reviewRows, [18, 8, 90, 24, 55, 65], colors.red);
for (let r = 5; r <= reviewSheet.rowCount; r += 1) {
  reviewSheet.getCell(r, 4).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightAmber}` } };
  reviewSheet.getCell(r, 4).font = { bold: true, color: { argb: `FF${colors.amber}` } };
}

// Individual member review sheets.
for (const [owner, ownerTables] of Object.entries(ownership)) {
  const memberRows = columns
    .filter(c => ownerTables.includes(c.table))
    .map(c => [c.table, purposes[c.table] ?? '', c.column, c.datatype, c.required, c.defaultValue, c.rules, constraints.filter(k => k.table === c.table).length, relationships.filter(rel => rel.child === c.table).length, 'Pending']);
  const sheet = addGridSheet(
    `M ${owner}`.slice(0, 31),
    `${owner} — Owned Tables and Columns`,
    `${ownerTables.length} implemented tables. Review each column, then use the master constraint, FK, DDL, and SQL-test sheets for exact definitions.`,
    ['Table', 'Table purpose', 'Column', 'Datatype', 'Required?', 'Default', 'Inline rule / reference', 'Table rules', 'Outgoing FKs', 'Owner review'],
    memberRows,
    [38, 62, 31, 24, 15, 28, 85, 14, 14, 20],
    ownerColors[owner]
  );
  for (let r = 5; r <= sheet.rowCount; r += 1) {
    sheet.getRow(r).height = 45;
    sheet.getCell(r, 10).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: `FF${colors.lightAmber}` } };
  }
}

for (const ws of workbook.worksheets) {
  if (ws.name !== '00 Cover') highlightAdityaHardeningRows(ws);
  ws.properties.defaultRowHeight = 18;
  ws.pageSetup.paperSize = 9;
  ws.pageSetup.fitToPage = true;
  ws.pageSetup.horizontalCentered = true;
}

await workbook.xlsx.writeFile(output);
console.log(output);
console.log(`Sheets: ${workbook.worksheets.length}`);
console.log(`Tables: ${tableDefs.length}`);
console.log(`Columns: ${columns.length}`);
console.log(`Constraints/indexes: ${constraints.length}`);
console.log(`Relationships: ${relationships.length}`);
console.log(`Functions: ${routines.length}`);
console.log(`Triggers: ${triggers.length}`);
console.log(`SQL tests: ${testRows.length}`);
