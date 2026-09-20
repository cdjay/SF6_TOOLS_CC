import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectRecovery, states } from './recovery.mjs';

function fixture() {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
    'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new',
    'guard_time', 'damage_time', 'hit_stop', 'act_st', 'pose_st'];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id',
    ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  const c = { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped',
    metadata: { replay_id: 'TEST', version: 20004000, players: [
      { fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: 5, samples: Array.from({ length: 5 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame'].includes(n) ? i + 1 : n.endsWith('.vital_new') ? 1000 : 0)) };
  set(c, 1, 'act_st', states.DEF); set(c, 2, 'act_st', states.DEF);
  set(c, 1, 'guard_time', 2); set(c, 2, 'guard_time', 1);
  return c;
}
function set(c, i, n, v) { c.samples[i][c.columns.indexOf(`p1.${n}`)] = v; }
test('ordinary guard exit remains a candidate, not an actionable verdict', () => {
  const r = inspectRecovery(fixture()), e = r.episodes[0];
  assert.equal(e.result, 'state_exit_candidate'); assert.equal(e.end.clock.replay_frame, 4);
  assert.equal(e.actionable_frame, null); assert.equal(e.frame_advantage, null);
  assert.equal(e.punish_opportunity, null); assert.equal(r.actionable_timing_verified, false);
});
test('parry is separated from ordinary guard', () => {
  const c = fixture(); set(c, 1, 'act_st', states.PARRY); set(c, 2, 'act_st', states.PARRY);
  const r = inspectRecovery(c); assert.equal(r.summary.parry.candidates, 1); assert.equal(r.summary.guard.episodes, 0);
});
test('frame2150 pattern: 1->0 and new damage is not guard recovery', () => {
  const c = fixture(); set(c, 3, 'act_st', states.DAMAGE); set(c, 3, 'vital_new', 800);
  set(c, 3, 'damage_time', 15); set(c, 3, 'hit_stop', 9);
  const e = inspectRecovery(c).episodes[0];
  assert.equal(e.result, 'not_recovery_proof');
  assert.ok(e.reasons.includes('new_hp_loss')); assert.ok(e.reasons.includes('reaction_or_unverified_state'));
});
test('frame1890 pattern: damage count 4->0 during another hit is not recovery', () => {
  const c = fixture();
  for (const i of [1, 2]) { set(c, i, 'guard_time', 0); set(c, i, 'damage_time', i === 1 ? 5 : 4); set(c, i, 'act_st', states.DAMAGE); }
  set(c, 3, 'act_st', states.DAMAGE); set(c, 3, 'hit_stop', 15); set(c, 3, 'vital_new', 364);
  const e = inspectRecovery(c).episodes[0];
  assert.ok(e.reasons.includes('not_one_to_zero')); assert.ok(e.reasons.includes('still_same_reaction_state'));
});
test('retained guard counter does not span damage, throw and getup', () => {
  const c = fixture();
  set(c, 1, 'guard_time', 38); set(c, 2, 'guard_time', 38); set(c, 2, 'act_st', states.DAMAGE);
  set(c, 3, 'guard_time', 38); set(c, 3, 'act_st', states.HOLD);
  set(c, 4, 'guard_time', 38); set(c, 4, 'act_st', states.GETUP);
  const r = inspectRecovery(c);
  assert.equal(r.episodes[0].end.clock.replay_frame, 3);
  assert.equal(r.positive_counter_samples_outside_applicable_state.guard_time, 3);
  assert.equal(r.summary.guard.candidates, 0);
});
test('pause duplicates and clock gaps do not manufacture a recovery', () => {
  const c = fixture(); c.samples.splice(2, 0, [...c.samples[1]]); c.sample_count++;
  assert.equal(inspectRecovery(c).duplicate_samples, 1); assert.equal(inspectRecovery(c).summary.guard.candidates, 1);
  const b = fixture(); b.samples.splice(3, 1); b.sample_count--;
  assert.equal(inspectRecovery(b).episodes[0].result, 'incomplete');
});
test('partial starts, same reaction state, hitstop, and unknown exits are not proof', () => {
  const a = fixture(); a.samples.shift(); a.sample_count--;
  assert.ok(inspectRecovery(a).episodes[0].reasons.includes('partial_start'));
  for (const change of [c => set(c, 3, 'act_st', states.DEF), c => set(c, 3, 'hit_stop', 1), c => set(c, 3, 'act_st', 123)]) {
    const c = fixture(); change(c); assert.equal(inspectRecovery(c).episodes[0].result, 'not_recovery_proof');
  }
});
test('missing evidence, conflicting clocks and unsupported builds fail closed', () => {
  const a = fixture(); set(a, 2, 'damage_time', false); assert.throws(() => inspectRecovery(a), /Unavailable/);
  const b = fixture(); b.metadata.version++; assert.throws(() => inspectRecovery(b), /Unverified/);
  const c = fixture(); c.samples.splice(2, 0, [...c.samples[1]]); c.sample_count++;
  set(c, 2, 'guard_time', 1); assert.throws(() => inspectRecovery(c), /Conflicting/);
});
