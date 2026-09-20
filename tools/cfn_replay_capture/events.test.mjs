import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectEvents, eventMarkdown } from './events.mjs';

function fixture() {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
    'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new',
    'damage_source', 'hit_stop', 'act_st', 'damage_type'];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id', 'fight_st',
    ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  return { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped',
    metadata: { replay_id: 'TEST', version: 20004000, players: [
      { fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: 5, samples: Array.from({ length: 5 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame'].includes(n) ? i + 1 : n.endsWith('.vital_new') ? 1000 : 0)) };
}
function set(c, row, name, value) { c.samples[row][c.columns.indexOf(name)] = value; }
function from(c, start, name, value) { for (let i = start; i < c.samples.length; i++) set(c, i, name, value); }

test('persistent punish flags do not turn each damage tick into a new punish', () => {
  const c = fixture(); from(c, 1, 'p2.hit_st', 0x18100); from(c, 1, 'p2.vital_new', 900);
  from(c, 3, 'p2.vital_new', 800);
  const r = inspectEvents(c);
  assert.equal(r.counts.hp_loss_observations, 2);
  assert.equal(r.counts.flag_onsets.punish, 1);
  assert.deepEqual(r.events[1].flag_onsets, []);
  assert.equal(r.events[1].outcome, null);
  assert.equal(r.events[1].punish_opportunity, null);
});
test('guard plus hit mask with no HP loss is not counted as confirmed damage', () => {
  const c = fixture(); from(c, 1, 'p2.hit_st', 0x18004);
  const r = inspectEvents(c);
  assert.equal(r.events.length, 1); assert.equal(r.events[0].hp_loss, 0);
  assert.deepEqual(r.events[0].flag_onsets, ['hit', 'guard']);
  assert.equal(r.events[0].outcome, null);
});
test('HP loss under retained guard or without any flags stays unclassified', () => {
  for (const flags of [0, 0x18004]) {
    const c = fixture(); from(c, 0, 'p1.hit_st', flags); from(c, 2, 'p1.vital_new', 800);
    const r = inspectEvents(c);
    assert.equal(r.events.length, 1); assert.equal(r.events[0].hp_loss, 200);
    assert.deepEqual(r.events[0].flag_onsets, []); assert.equal(r.events[0].outcome, null);
  }
});
test('capture begins with existing flags: boundary observation, not fresh onset', () => {
  const c = fixture(); from(c, 0, 'p2.hit_st', 0x18080);
  const r = inspectEvents(c); assert.equal(r.events.length, 0);
  assert.equal(r.baseline[1].flags_present.counter, true);
});
test('counter can have a new onset after clearing; signed attacker bits are harmless', () => {
  const c = fixture(); set(c, 1, 'p2.hit_st', 0x18080); set(c, 3, 'p2.hit_st', 0x18080);
  from(c, 0, 'p1.hit_st', -2147483648);
  assert.equal(inspectEvents(c).counts.flag_onsets.counter, 2);
});
test('identical same-clock rows do not double count and conflicts fail closed', () => {
  const c = fixture(); from(c, 1, 'p2.vital_new', 900);
  c.samples.splice(2, 0, [...c.samples[1]]); c.sample_count++;
  assert.equal(inspectEvents(c).counts.hp_loss_observations, 1);
  assert.equal(inspectEvents(c).counts.duplicate_samples, 1);
  set(c, 2, 'p2.vital_new', 800); assert.throws(() => inspectEvents(c), /Conflicting/);
});
test('no HP delta across a missing frame or a round transition', () => {
  const c = fixture(); from(c, 2, 'p2.vital_new', 800);
  c.samples.splice(1, 1); c.sample_count--;
  assert.equal(inspectEvents(c).events.length, 0);
  assert.equal(inspectEvents(c).boundaries[1].reason, 'clock_gap_or_reset');
  const b = fixture(); set(b, 2, 'battle_round', 1); from(b, 2, 'p2.vital_new', 800);
  assert.equal(inspectEvents(b).counts.excluded_transition_samples, 1);
  assert.equal(inspectEvents(b).events.length, 0);
});
test('later rounds are not included in first-round totals', () => {
  const c = fixture(); from(c, 2, 'round', 1); from(c, 2, 'battle_round', 1);
  from(c, 2, 'p1.vital_new', 50);
  assert.equal(inspectEvents(c).counts.hp_loss_by_player.p1, 0);
  assert.equal(inspectEvents(c).counts.unique_samples, 2);
});
test('replay passes may not be silently merged', () => {
  const c = fixture(); c.samples.push([...c.samples[0]]); c.sample_count++;
  assert.throws(() => inspectEvents(c), /Repeated nonconsecutive/);
});
test('action changes, progress decreases and position are not punish proof', () => {
  const c = fixture(); from(c, 1, 'p1.action_id', 600); set(c, 1, 'p1.action_frame_raw', 65536);
  from(c, 0, 'p2.x_raw', 6553600); from(c, 1, 'p2.hit_st', 4); from(c, 1, 'p2.damage_source', 1);
  const r = inspectEvents(c);
  assert.deepEqual(r.action_observations.map(x => x.kind), ['action_id_changed', 'action_progress_decreased']);
  assert.ok(r.action_observations.every(x => x.actionable === null));
  assert.equal(r.events[0].horizontal_separation_raw, 6553600);
  assert.equal(r.events[0].attack_owner_verified, false);
  assert.equal(r.actionable_times_available, false);
});
test('unsupported build and missing event values are rejected', () => {
  const c = fixture(); c.metadata.version++; assert.throws(() => inspectEvents(c), /Unverified/);
  const b = fixture(); set(b, 1, 'p1.hit_stop', false); assert.throws(() => inspectEvents(b), /Missing event value/);
});
test('plain-language report explicitly withholds verdicts', () => {
  const c = fixture(); from(c, 1, 'p1.vital_new', 900);
  const md = eventMarkdown(inspectEvents(c));
  assert.match(md, /不是招式判定或漏确反结论/); assert.match(md, /1000 → 900/);
});
