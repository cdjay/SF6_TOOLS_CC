import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { formatJson, archiveName, planMigration, applyMigration } from './migrate_capture_files.mjs';

test('format preserves every number and escaped string exactly', () => {
  const raw = '{"id":76561198012345678,"x":-0,"exp":1e-30,"s":"x\\n\\\"","rows":[[1,false,null],{},[]]}';
  const { formatted } = formatJson(raw);
  assert.ok(formatted.includes('76561198012345678'));
  assert.ok(formatted.includes('-0'));
  assert.ok(formatted.includes('1e-30'));
  assert.deepEqual(JSON.parse(formatted), JSON.parse(raw));
  assert.equal(formatJson(formatted).formatted, formatted);
  assert.throws(() => formatJson('{invalid}'));
});
test('names use embedded replay ID and reject mismatched or unsafe names', () => {
  const doc = { metadata: { replay_id: 'ABC123' }, replay_id: 'ABC123' };
  assert.equal(archiveName('cfn-capture-20260920-032052-10.json', doc), 'cfn-capture-ABC123-20260920-032052-10.json');
  assert.equal(archiveName('cfn-jump-trace-20260920-001718-plugin.json', doc), 'cfn-jump-trace-ABC123-20260920-001718-plugin.json');
  assert.equal(archiveName('cfn-keyboard-ready.json', doc), 'cfn-keyboard-ready.json');
  assert.throws(() => archiveName('cfn-capture-WRONG-20260920-032052.json', doc));
  assert.throws(() => archiveName('cfn-capture-20260920-032052.json', { metadata: { replay_id: '../x' } }));
});
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cfn-migrate-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const data = path.join(dir, 'data'); fs.mkdirSync(data);
  const name = 'cfn-capture-20260920-032052.json';
  const raw = '{"metadata":{"replay_id":"ABC123"},"samples":[[1,2,false]]}';
  fs.writeFileSync(path.join(data, name), raw);
  return { dir, data, name, raw };
}
test('backup, rename, fixed files, unrelated exclusion, rerun and BOM', t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.data, 'cfn-keyboard-ready.json'), '\ufeff{"ready":true}');
  fs.writeFileSync(path.join(f.data, 'unrelated.json'), 'untouched');
  const plan = planMigration(f.data); assert.equal(plan.length, 2);
  const backup = path.join(f.dir, 'backup'); applyMigration(plan, backup);
  assert.equal(fs.readFileSync(path.join(backup, f.name), 'utf8'), f.raw);
  assert.equal(fs.existsSync(path.join(f.data, f.name)), false);
  assert.equal(fs.readFileSync(path.join(f.data, 'unrelated.json'), 'utf8'), 'untouched');
  const second = planMigration(f.data);
  assert.ok(second.every(e => e.name === e.newName && e.before === e.after));
  assert.throws(() => applyMigration(second, backup));
});
test('preflight aborts before edits on malformed input, collision or changed source', t => {
  const f = fixture(t), invalid = path.join(f.data, 'cfn-bad.json');
  fs.writeFileSync(invalid, '{'); assert.throws(() => planMigration(f.data)); fs.unlinkSync(invalid);
  const collision = path.join(f.data, 'cfn-capture-ABC123-20260920-032052.json');
  fs.writeFileSync(collision, f.raw); assert.throws(() => planMigration(f.data)); fs.unlinkSync(collision);
  const plan = planMigration(f.data);
  fs.appendFileSync(path.join(f.data, f.name), ' ');
  assert.throws(() => applyMigration(plan, path.join(f.dir, 'backup')));
  assert.equal(fs.existsSync(path.join(f.dir, 'backup')), false);
});
