import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const review = path.join(root, 'docs', 'review');
const source = path.join(review, 'extracted');
const workbooks = fs.readdirSync(source).filter(f => f.endsWith('.json')).map(f =>
  JSON.parse(fs.readFileSync(path.join(source, f), 'utf8').replace(/^\uFEFF/, '')));
const cells = row => Object.fromEntries(row.cells.map(c => [c.address.replace(/\d+$/, ''), c.value]));
const duplicates = (rows, key) => Object.entries(Object.groupBy(rows, key))
  .filter(([, items]) => items.length > 1).map(([value, items]) => ({value, rows: items.map(x => x.row)}));
const tablePattern = /^(core|safety|analytics|audit)\.\w+$/;
const summaries = [];
const inventory = [];
const valueGroups = [];
for (const book of workbooks) {
  const dictionary = book.sheets.find(s => s.name === 'Data Dictionary');
  const columnRows = dictionary.rows.map(r => ({...cells(r), row:r.row})).filter(r => tablePattern.test((r.A ?? '').trim()));
  const tables = Object.groupBy(columnRows, r => r.A.trim());
  const tableSheet = book.sheets.find(s => s.name === 'Tables');
  const declarations = tableSheet.rows.map(cells).filter(r => tablePattern.test((r.B ?? '').trim())).map(r => r.B.trim());
  const owner = book.source.split('_')[0].split(' ')[0];
  const tableDetails = Object.entries(tables).map(([table, entries]) => {
    const normalized = entries.map(r => ({row:r.row, column:r.C, type:owner === 'Skanda' ? null : r.D,
      definition: r}));
    const repeatedColumns = duplicates(normalized, r => r.column);
    const detail = {table, owner, source:book.source, dictionaryRows:entries.length,
      uniqueColumnLabels:new Set(entries.map(r => r.C)).size, repeatedColumns, columns:normalized};
    inventory.push(detail);
    return {table, dictionaryRows:detail.dictionaryRows, uniqueColumnLabels:detail.uniqueColumnLabels, repeatedColumns};
  });
  const groups = [];
  const listSheet = book.sheets.find(s => ['Value Lists','Value list'].includes(s.name));
  let table = null, group = null;
  const koushik = owner === 'Koushik';
  for (const row of listSheet.rows) {
    const c = cells(row);
    const match = (c.A ?? '').match(/^(core|safety|analytics|audit)\.\w+/);
    if (match) {table = match[0]; group = null; continue;}
    const arrow = (koushik ? c.A : c.B) === '↳' || c.A === '↳';
    const label = koushik ? c.A : c.B;
    if (table && !arrow && label && label !== 'Column') {
      group = {source:book.source, sheet:listSheet.name, table, column:label, row:row.row,
        guidance:koushik ? c.B : c.C, notes:koushik ? c.D : c.E, entries:[]};
      groups.push(group);
    } else if (arrow && group) {
      group.entries.push({row:row.row, value:koushik ? c.B : c.C, meaning:koushik ? c.C : c.D, notes:koushik ? c.D : c.E});
    }
  }
  valueGroups.push(...groups);
  summaries.push({owner,source:book.source,sha256:book.sha256,sheets:book.sheets.map(s => ({name:s.name,rows:s.rows.length})),
    declaredTables:declarations,dictionaryTables:tableDetails,
    declaredWithoutDictionary:declarations.filter(t => !tables[t]),
    dictionaryWithoutDeclaration:Object.keys(tables).filter(t => !declarations.includes(t))});
}
const thanushree = workbooks.find(b => b.source.startsWith('Thanushree'));
const interestRows = thanushree.sheets.find(s => s.name === 'Interest Catalog').rows.map(r => ({row:r.row,...cells(r)})).filter(r => r.G === 'active' || r.G === 'deprecated');
const allRows = thanushree.sheets.find(s => s.name === 'All Values').rows.map(r => ({row:r.row,...cells(r)})).filter(r => r.B?.startsWith('core.') && r.C && r.F);
const safetyBook = workbooks.find(b => b.source.startsWith('Tejaswini'));
const taxonomyRows = safetyBook.sheets.find(s => s.name === 'Approved Taxonomy').rows.map(r => ({row:r.row,...cells(r)})).filter(r => r.B !== 'Category' && r.B && r.C);
const prajwalBook = workbooks.find(b => b.source.startsWith('Prajwal'));
const intents = prajwalBook.sheets.find(s => s.name === 'Seed Intents').rows.map(r => ({row:r.row,...cells(r)})).filter(r => /^int_\d+$/.test(r.B));
const catalogs = {
  interests:{rows:interestRows.length,categories:[...new Set(interestRows.map(r=>r.B))],
    subcategoryPairs:new Set(interestRows.map(r=>r.B+'|'+r.C)).size,
    duplicateSlugs:duplicates(interestRows,r=>r.E),duplicateLabelsWithinSubcategory:duplicates(interestRows,r=>r.B+'|'+r.C+'|'+r.D),
    maximumSlugLength:Math.max(...interestRows.map(r=>r.E.length)),intents:[...new Set(interestRows.map(r=>r.F).filter(Boolean))]},
  allValuesSections:Object.fromEntries(Object.entries(Object.groupBy(allRows,r=>r.C)).map(([kind,rows])=>[kind,{rows:rows.length,duplicates:duplicates(rows,r=>r.F)}])),
  safetyTaxonomy:{rows:taxonomyRows.length,categories:[...new Set(taxonomyRows.map(r=>r.B))],distinctSubcategories:new Set(taxonomyRows.map(r=>r.C)).size,duplicatePairs:duplicates(taxonomyRows,r=>r.B+'|'+r.C)},
  connectionIntents:{rows:intents.length,categories:Object.fromEntries(Object.entries(Object.groupBy(intents,r=>r.C)).map(([k,rs])=>[k,rs.length])),
    duplicateCodes:duplicates(intents,r=>r.D),duplicateLabels:duplicates(intents,r=>r.E),duplicateCategorySortOrders:duplicates(intents,r=>r.C+'|'+r.F),maxCategoryLength:Math.max(...intents.map(r=>r.C.length))}
};
const output = {workbooks:summaries,catalogs,valueGroups};
fs.writeFileSync(path.join(review,'workbook-analysis.json'),JSON.stringify(output,null,2)+'\n');
fs.writeFileSync(path.join(review,'column-inventory.json'),JSON.stringify(inventory,null,2)+'\n');
const csv = [['owner','table','dictionary_rows','unique_column_labels','source'],...inventory.map(t=>[t.owner,t.table,t.dictionaryRows,t.uniqueColumnLabels,t.source])]
  .map(row=>row.map(x=>'"'+String(x).replaceAll('"','""')+'"').join(',')).join('\n');
fs.writeFileSync(path.join(review,'table-inventory.csv'),csv+'\n');
console.log(JSON.stringify({workbooks:summaries.map(b=>({owner:b.owner,sheets:b.sheets.length,tables:b.dictionaryTables,declaredWithoutDictionary:b.declaredWithoutDictionary})),catalogs},null,2));
