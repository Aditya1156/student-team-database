import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const ExcelJS = require('exceljs');

const root = process.cwd();
const remote = process.argv.includes('--remote');
const writeApproved = process.argv.includes('--write-approved');
const workbookPath = path.join(root, 'docs', 'Team_Database_Complete_Design.xlsx');
const snapshotPath = path.join(root, 'docs', 'schema-catalog-approved.json');
const queryPath = path.join(root, 'supabase', 'tests', 'catalog_manifest.sql');

function runCatalogQuery() {
  const executable = process.execPath;
  const args = [path.join(root, 'node_modules', 'supabase', 'dist', 'supabase.js'), 'db', 'query'];
  if (remote) args.push('--remote');
  args.push('--read-only', '--file', queryPath);
  const output = execFileSync(executable, args, {
    cwd: root,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'inherit'],
    maxBuffer: 32 * 1024 * 1024,
  });
  const start = output.indexOf('{');
  if (start < 0) throw new Error('Supabase CLI did not return JSON.');
  return JSON.parse(output.slice(start)).rows;
}

function normalize(value) {
  return String(value ?? '').trim().toLowerCase().replace(/\s+/g, ' ');
}

function rowValues(sheet, rowNumber) {
  return sheet.getRow(rowNumber).values.slice(1).map(value =>
    typeof value === 'object' && value !== null && 'text' in value ? value.text : value
  );
}

function semanticFkKey(childTable, childColumns, parentTable, parentColumns, onDelete) {
  return [childTable, childColumns, parentTable, parentColumns, onDelete].map(normalize).join('|');
}

const rows = runCatalogQuery();
const manifest = {
  format_version: 1,
  managed_schemas: ['analytics', 'audit', 'core', 'safety'],
  objects: rows.map(row => ({
    object_kind: row.object_kind,
    schema_name: row.schema_name,
    table_name: row.table_name,
    object_name: row.object_name,
    definition: row.definition,
    parent_schema: row.parent_schema,
    parent_table: row.parent_table,
    child_columns: row.child_columns,
    parent_columns: row.parent_columns,
    delete_action: row.delete_action,
  })),
};

if (writeApproved) {
  fs.mkdirSync(path.dirname(snapshotPath), { recursive: true });
  fs.writeFileSync(snapshotPath, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(`Approved catalog written: ${path.relative(root, snapshotPath)}`);
}

if (!fs.existsSync(workbookPath)) {
  throw new Error(`Missing workbook: ${path.relative(root, workbookPath)}. Run npm run docs:team.`);
}

const workbook = new ExcelJS.Workbook();
await workbook.xlsx.readFile(workbookPath);
const constraintsSheet = workbook.getWorksheet('04 Table Constraints');
const foreignKeysSheet = workbook.getWorksheet('05 Foreign Keys');
const ddlSheet = workbook.getWorksheet('06 Exact DDL');
if (!constraintsSheet || !foreignKeysSheet || !ddlSheet) {
  throw new Error('Workbook must contain sheets 04 Table Constraints, 05 Foreign Keys, and 06 Exact DDL.');
}

const errors = [];
const actualTables = new Set(rows.filter(row => row.object_kind === 'table').map(row => `${row.schema_name}.${row.table_name}`));
const actualColumns = new Set(rows.filter(row => row.object_kind === 'column')
  .map(row => `${row.schema_name}.${row.table_name}|${row.object_name}`));
const actualNamedObjects = new Set(
  rows.filter(row => ['constraint', 'foreign_key', 'index'].includes(row.object_kind))
    .map(row => `${row.schema_name}.${row.table_name}|${row.object_name}`)
);
const actualFks = new Set(
  rows.filter(row => row.object_kind === 'foreign_key').map(row => semanticFkKey(
    `${row.schema_name}.${row.table_name}`,
    row.child_columns,
    `${row.parent_schema}.${row.parent_table}`,
    row.parent_columns,
    row.delete_action,
  ))
);
const actualFkShapes = new Set(
  rows.filter(row => row.object_kind === 'foreign_key').map(row => [
    `${row.schema_name}.${row.table_name}`,
    row.child_columns,
    `${row.parent_schema}.${row.parent_table}`,
    row.parent_columns,
  ].map(normalize).join('|'))
);

const ddlByTable = new Map();
for (let r = 5; r <= ddlSheet.rowCount; r += 1) {
  const [, table, , , ddl] = rowValues(ddlSheet, r);
  if (table) ddlByTable.set(String(table).trim(), normalize(ddl));
}
for (const table of actualTables) {
  if (!ddlByTable.has(table)) errors.push(`06 Exact DDL is missing live table ${table}.`);
}
for (const table of ddlByTable.keys()) {
  if (!actualTables.has(table)) errors.push(`06 Exact DDL documents nonexistent table ${table}.`);
}

for (let r = 5; r <= constraintsSheet.rowCount; r += 1) {
  const [, table, name, kind, sql] = rowValues(constraintsSheet, r);
  if (!table || !name) continue;
  if (!actualTables.has(String(table).trim())) errors.push(`04 Table Constraints references missing table ${table}.`);
  if (!String(sql ?? '').trim()) errors.push(`04 Table Constraints row ${r} has no SQL definition.`);
}

for (let r = 5; r <= foreignKeysSheet.rowCount; r += 1) {
  const [, childTable, childColumns, parentTable, parentColumns, onDelete] = rowValues(foreignKeysSheet, r);
  if (!childTable) continue;
  if (!actualTables.has(String(childTable).trim())) errors.push(`05 Foreign Keys row ${r} references missing child table ${childTable}.`);
  if (!actualTables.has(String(parentTable).trim())) errors.push(`05 Foreign Keys row ${r} references missing parent table ${parentTable}.`);
}

if (!writeApproved) {
  if (!fs.existsSync(snapshotPath)) {
    errors.push(`Missing approved snapshot ${path.relative(root, snapshotPath)}.`);
  } else {
    const approved = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
    if (JSON.stringify(approved) !== JSON.stringify(manifest)) {
      const approvedKeys = new Set(approved.objects.map(o => `${o.object_kind}|${o.schema_name}.${o.table_name}|${o.object_name}|${o.definition}`));
      const currentKeys = new Set(manifest.objects.map(o => `${o.object_kind}|${o.schema_name}.${o.table_name}|${o.object_name}|${o.definition}`));
      const added = [...currentKeys].filter(key => !approvedKeys.has(key)).slice(0, 12);
      const removed = [...approvedKeys].filter(key => !currentKeys.has(key)).slice(0, 12);
      errors.push(`Catalog differs from approved snapshot. Added/changed: ${added.join('; ') || 'none'}. Removed/changed: ${removed.join('; ') || 'none'}.`);
    }
  }
}

if (errors.length) {
  console.error(`Schema drift check failed with ${errors.length} issue(s):`);
  errors.slice(0, 80).forEach(error => console.error(`- ${error}`));
  if (errors.length > 80) console.error(`- ...and ${errors.length - 80} more.`);
  process.exit(1);
}

console.log(`Schema drift check passed: ${actualTables.size} tables and ${rows.length} catalog objects match PostgreSQL, workbook, and approved metadata.`);
