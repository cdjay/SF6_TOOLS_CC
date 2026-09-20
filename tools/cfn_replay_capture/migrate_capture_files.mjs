import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const decode = bytes => new TextDecoder('utf-8', { fatal: true }).decode(bytes);
const tokens = text => text.match(/"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\],:]/g);

export function formatJson(text) {
  const value = JSON.parse(text);
  // Preserve original numeric lexemes, including IDs beyond JS integer precision.
  const input = tokens(text), out = [];
  let depth = 0;
  const newline = () => out.push('\n', '  '.repeat(depth));
  for (let i = 0; i < input.length; i++) {
    const token = input[i], previous = input[i - 1], next = input[i + 1];
    if (token === '{' || token === '[') {
      out.push(token); depth++;
      if (next !== '}' && next !== ']') newline();
    } else if (token === '}' || token === ']') {
      depth--;
      if (previous !== '{' && previous !== '[') newline();
      out.push(token);
    } else if (token === ',') { out.push(token); newline(); }
    else if (token === ':') out.push(': ');
    else out.push(token);
  }
  const formatted = out.join('') + '\n';
  JSON.parse(formatted);
  if (JSON.stringify(tokens(formatted)) !== JSON.stringify(input)) throw new Error('JSON token mismatch');
  return { value, formatted };
}

export function archiveName(name, value) {
  const prefix = name.startsWith('cfn-capture-') ? 'cfn-capture-' :
    name.startsWith('cfn-jump-trace-') ? 'cfn-jump-trace-' : null;
  if (!prefix) return name;
  const id = prefix === 'cfn-capture-' ? value.metadata?.replay_id : value.replay_id;
  if (typeof id !== 'string' || !/^[A-Za-z0-9_]{1,64}$/.test(id)) throw new Error(`Invalid replay ID: ${name}`);
  const tail = name.slice(prefix.length);
  const pattern = prefix === 'cfn-capture-' ? /^\d{8}-\d{6}(?:-\d+)?\.json$/ :
    /^\d{8}-\d{6}-(?:plugin|native)\.json$/;
  if (pattern.test(tail)) return prefix + id + '-' + tail;
  if (tail.startsWith(id + '-') && pattern.test(tail.slice(id.length + 1))) return name;
  throw new Error(`Unrecognized archive name or mismatched replay ID: ${name}`);
}

export function planMigration(directory) {
  const root = fs.realpathSync(directory);
  const names = fs.readdirSync(root);
  const occupied = new Set(names.map(n => n.toLowerCase())), targets = new Set();
  return names.filter(n => /^cfn-.*\.json$/i.test(n)).sort().map(name => {
    const source = path.join(root, name);
    if (!fs.lstatSync(source).isFile()) throw new Error(`Not a regular file: ${name}`);
    const bytes = fs.readFileSync(source);
    const { value, formatted } = formatJson(decode(bytes));
    const target = archiveName(name, value), key = target.toLowerCase();
    if (targets.has(key) || (target !== name && occupied.has(key))) throw new Error(`Target collision: ${target}`);
    targets.add(key);
    return { source, target: path.join(root, target), name, newName: target,
      bytes, formatted, before: hash(bytes), after: hash(formatted) };
  });
}

export function applyMigration(plan, backupDirectory) {
  const backup = path.resolve(backupDirectory);
  if (fs.existsSync(backup)) throw new Error('Backup directory must be new');
  for (const entry of plan) {
    if (hash(fs.readFileSync(entry.source)) !== entry.before) throw new Error(`Source changed: ${entry.name}`);
    if (entry.target !== entry.source && fs.existsSync(entry.target)) throw new Error(`Target appeared: ${entry.newName}`);
  }
  fs.mkdirSync(backup, { recursive: true });
  for (const entry of plan) fs.writeFileSync(path.join(backup, entry.name), entry.bytes, { flag: 'wx' });
  fs.writeFileSync(path.join(backup, 'migration-manifest.json'), JSON.stringify(plan.map(e => ({
    source: e.source, target: e.target, before: e.before, after: e.after
  })), null, 2) + '\n', { flag: 'wx' });
  const touched = [];
  try {
    for (const entry of plan) {
      const fd = fs.openSync(entry.target, entry.target === entry.source ? 'w' : 'wx');
      touched.push(entry);
      try { fs.writeFileSync(fd, entry.formatted); } finally { fs.closeSync(fd); }
      if (hash(fs.readFileSync(entry.target)) !== entry.after) throw new Error(`Readback failed: ${entry.newName}`);
    }
    for (const entry of plan) if (entry.target !== entry.source) fs.unlinkSync(entry.source);
  } catch (error) {
    for (const entry of touched) {
      fs.writeFileSync(entry.source, entry.bytes);
      if (entry.target !== entry.source && fs.existsSync(entry.target)) fs.unlinkSync(entry.target);
    }
    throw error;
  }
  return backup;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [directory, backup, flag] = process.argv.slice(2);
  if (!directory || (flag && flag !== '--apply')) throw new Error('Usage: node migrate_capture_files.mjs DATA_DIR BACKUP_DIR [--apply]');
  const plan = planMigration(directory);
  console.log(JSON.stringify({ files: plan.length, renamed: plan.filter(e => e.name !== e.newName).length,
    entries: plan.map(e => ({ from: e.name, to: e.newName, bytes: Buffer.byteLength(e.formatted) })) }, null, 2));
  if (flag === '--apply') {
    if (!backup) throw new Error('Backup directory is required');
    console.log('Backup: ' + applyMigration(plan, backup));
  }
}
