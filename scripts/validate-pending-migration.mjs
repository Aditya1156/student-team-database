import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const input = process.argv[2];
if (!input) throw new Error('Usage: node scripts/validate-pending-migration.mjs <migration.sql>');
const source = fs.readFileSync(path.resolve(input), 'utf8');
const fixture = process.argv.slice(3).map((file) =>
    fs.readFileSync(path.resolve(file), 'utf8')
      .split(/\r?\n/)
      .filter((line) => !/^\s*(begin|commit);\s*$/i.test(line))
      .join('\n')
  ).join('\n');
const output = path.join(os.tmpdir(), `rollback-${path.basename(input)}`);
fs.writeFileSync(output, `begin;\n${source}\n${fixture}\nrollback;\n`, 'utf8');
process.stdout.write(output);
