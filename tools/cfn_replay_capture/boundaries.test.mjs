import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectBoundaries } from './boundaries.mjs';
import { states } from './recovery.mjs';

function set(c, i, side, name, value) {
  c.samples[i][c.columns.indexOf(`p${side}.${name}`)] = value;
  if (name === 'action_id' || name === 'action_frame_raw') {
    c.samples[i][c.columns.indexOf(`p${side}.engine_${name}`)] = value;
  }
}
function fixture() {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
    'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new',
    'guard_time', 'damage_time', 'hit_stop', 'act_st', 'pose_st', 'engine_action_id',
    'engine_action_frame_raw', 'engine_margin_start_raw', 'engine_frame_num_raw',
    'engine_speed_raw', 'engine_state_flags', 'engine_battle_version', 'engine_loop_count', 'engine_style_index'];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id',
    ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  const c = { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped',
    metadata: { replay_id: 'TEST', version: 20004000, players: [
      { fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: 8, samples: Array.from({ length: 8 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame'].includes(n) ? i + 1 : n.endsWith('.vital_new') ? 1000 : 0)) };
  for (let i = 0; i < 8; i++) {
    set(c, i, 2, 'action_id', i < 6 ? 88 : 9);
    set(c, i, 2, 'action_frame_raw', (i < 6 ? 10 + i : i - 6) * 65536);
    set(c, i, 2, 'act_st', i < 6 ? states.ATCK : states.WALK);
    set(c, i, 2, 'engine_margin_start_raw', (i < 6 ? 16 : 23) * 65536);
    set(c, i, 2, 'engine_frame_num_raw', 69 * 65536);
    set(c, i, 2, 'engine_speed_raw', 65536);
  }
  for (const i of [1, 2]) { set(c, i, 1, 'act_st', states.DEF); set(c, i, 1, 'guard_time', 3 - i); }
  return c;
}
const first = c => inspectBoundaries(c).observations[0];

test('margin-aligned standing/movement is an observation, never frame advantage', () => {
  const r = inspectBoundaries(fixture()), o = r.observations[0];
  assert.equal(o.result, 'ordinary_state_at_margin_observed');
  assert.equal(o.observed_frame_difference, 3); assert.equal(o.boundary.after.replay_frame, 7);
  assert.equal(o.boundary.margin_step_aligned, true);
  assert.equal(o.frame_advantage, null); assert.equal(o.actionable_frame, null);
  assert.equal(o.punish_opportunity, null); assert.equal(o.attack_owner_verified, false);
  assert.equal(r.actionable_timing_verified, false);
});

test('same Action can leave attack state at its margin without changing identity', () => {
  const c = fixture();
  set(c, 6, 2, 'action_id', 88); set(c, 6, 2, 'action_frame_raw', 16 * 65536);
  set(c, 6, 2, 'engine_margin_start_raw', 16 * 65536);
  const o = first(c); assert.equal(o.result, 'ordinary_state_at_margin_observed');
  assert.ok(o.boundary.reasons.includes('margin_reached'));
});

test('intervening opponent actions cannot donate their duration to the first action', () => {
  const c = fixture(); set(c, 2, 2, 'action_id', 99);
  const o = first(c); assert.equal(o.result, 'opponent_changed_during_guard');
  assert.equal(o.changes_during_guard.length, 2); // Returning to the same ID does not erase the change.
  assert.equal(o.boundary, null); assert.equal(o.observed_frame_difference, null);
});

test('same-ID restart or style switch during guard breaks the observed sequence', () => {
  for (const [field, value] of [['action_frame_raw', 0], ['engine_style_index', 1], ['engine_loop_count', 1]]) {
    const c = fixture(); set(c, 2, 2, field, value);
    assert.equal(first(c).result, 'opponent_changed_during_guard');
  }
});

test('new attack, block, HP loss or hitstop at the boundary is not an ordinary-state observation', () => {
  for (const [field, value] of [['act_st', states.SPECIAL], ['act_st', states.DEF], ['vital_new', 800], ['hit_stop', 9]]) {
    const c = fixture(); set(c, 6, 2, field, value);
    assert.equal(first(c).result, 'boundary_not_recovery_proof');
  }
});

test('early movement, zero margin and unknown state do not imply recovery', () => {
  const a = fixture(); set(a, 4, 2, 'act_st', states.WALK);
  assert.equal(first(a).result, 'boundary_not_recovery_proof');
  const b = fixture(); for (let i = 0; i < 6; i++) set(b, i, 2, 'engine_margin_start_raw', 0);
  assert.equal(first(b).result, 'margin_unusable_or_already_reached');
  const c = fixture(); set(c, 6, 2, 'act_st', 999);
  assert.equal(first(c).result, 'boundary_not_recovery_proof');
});

test('duplicates, gaps and capture end cannot invent a boundary', () => {
  const a = fixture(); a.samples.splice(2, 0, [...a.samples[1]]); a.sample_count++;
  assert.equal(first(a).observed_frame_difference, 3);
  const b = fixture(); b.samples.splice(4, 1); b.sample_count--;
  assert.equal(first(b).result, 'clock_gap'); assert.equal(first(b).boundary, null);
  const c = fixture(); c.samples = c.samples.slice(0, 5); c.sample_count = 5;
  assert.equal(first(c).result, 'capture_end');
});

test('fractional fixed-point progress is not rounded before margin checks', () => {
  const c = fixture(); set(c, 5, 2, 'action_frame_raw', 16 * 65536 - 1);
  assert.equal(first(c).result, 'ordinary_state_at_margin_observed');
});

test('missing data, getter disagreement and unsupported builds fail closed', () => {
  const a = fixture(); set(a, 2, 2, 'engine_frame_num_raw', false);
  assert.throws(() => first(a), /Unavailable engine/);
  const b = fixture(); set(b, 2, 2, 'engine_action_id', 777);
  assert.throws(() => first(b), /differs from existing/);
  const c = fixture(); c.metadata.version++;
  assert.throws(() => first(c), /Unverified/);
  const d = fixture(); const col = d.columns.indexOf('p1.engine_state_flags');
  d.columns.splice(col, 1); for (const r of d.samples) r.splice(col, 1);
  assert.throws(() => first(d), /Missing engine/);
});
