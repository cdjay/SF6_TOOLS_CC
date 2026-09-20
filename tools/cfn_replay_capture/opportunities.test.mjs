import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectOpportunities, opportunityMarkdown } from './opportunities.mjs';

function fixture() {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw', 'x_raw', 'y_raw', 'z_raw',
    'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new', 'guard_time', 'damage_time', 'hit_stop', 'act_st', 'pose_st',
    'damage_source', 'damage_type', 'engine_action_id', 'engine_action_frame_raw', 'engine_margin_start_raw',
    'engine_frame_num_raw', 'engine_speed_raw', 'engine_state_flags', 'engine_battle_version', 'engine_loop_count',
    'engine_style_index', ...['size', 'index', 'type', 'empty', 'changed', 'end', 'not_add', 'not_whole'].map(n => 'display_meter_' + n)];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id', 'fight_st',
    'display_prev_frame', 'meter_start_frame', ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  const c = { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped',
    metadata: { replay_id: 'TEST', version: 20004000, frame_meter_profile: 'native_cursor_cell_v1',
      players: [{ fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: 9, samples: Array.from({ length: 9 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame', 'display_prev_frame'].includes(n) ? i + 1 : n.endsWith('.vital_new') ? 1000 : 0)) };
  for (let i = 0; i < 9; i++) {
    for (const s of [1, 2]) {
      set(c, i, s, 'display_meter_size', 80); set(c, i, s, 'display_meter_index', i);
      set(c, i, s, 'engine_speed_raw', 65536);
    }
    set(c, i, 1, 'act_st', i >= 4 ? 29 : 4);
    set(c, i, 1, 'action_id', i >= 4 ? 60 : 6);
    set(c, i, 1, 'action_frame_raw', i * 65536);
    set(c, i, 2, 'x_raw', 123 * 65536 + 1);
    set(c, i, 2, 'act_st', i < 6 ? 29 : 8);
    set(c, i, 2, 'action_id', i < 6 ? 88 : 9);
    set(c, i, 2, 'action_frame_raw', (i < 6 ? i + 10 : i - 6) * 65536);
    set(c, i, 2, 'engine_margin_start_raw', 16 * 65536);
    set(c, i, 2, 'engine_frame_num_raw', 69 * 65536);
    set(c, i, 2, 'display_meter_type', i < 6 ? 8 : 0);
  }
  for (const i of [1, 2]) {
    set(c, i, 1, 'act_st', 27); set(c, i, 1, 'guard_time', 3 - i);
    set(c, i, 1, 'display_meter_type', 10);
  }
  return c;
}
function set(c, i, s, n, v) {
  c.samples[i][c.columns.indexOf(`p${s}.${n}`)] = v;
  if (['action_id', 'action_frame_raw'].includes(n)) c.samples[i][c.columns.indexOf(`p${s}.engine_${n}`)] = v;
}
const first = c => inspectOpportunities(c).observations[0];

test('new blue cells, attack entry and coordinate distance are separate observations', () => {
  const r = inspectOpportunities(fixture()), o = r.observations[0];
  assert.deepEqual(o.fresh_blue_frames, [4, 5, 6]);
  assert.equal(o.response.first_attack_frame, 5); assert.equal(o.response.elapsed_updates, 1);
  assert.equal(o.horizontal_separation_raw, 123 * 65536 + 1);
  assert.equal(o.punish_opportunity, null); assert.equal(o.actionable_frame, null);
  assert.equal(o.reach_verified, false); assert.equal(o.frame_advantage, null);
  assert.match(opportunityMarkdown(r), /不是漏确反判定/);
});

test('retained blue after ordinary movement never extends the counted interval', () => {
  const c = fixture();
  for (let i = 6; i < 9; i++) {
    set(c, i, 2, 'action_id', 88); set(c, i, 2, 'action_frame_raw', (i + 10) * 65536);
    set(c, i, 2, 'display_meter_type', 8); set(c, i, 2, 'display_meter_index', 5);
  }
  const o = first(c); assert.deepEqual(o.fresh_blue_frames, [4, 5, 6]); assert.equal(o.blue_stop, 'held_cursor');
});

test('retained defender yellow is reported without deleting the raw exit candidate', () => {
  const c = fixture(); set(c, 3, 1, 'display_meter_type', 10); set(c, 3, 1, 'display_meter_index', 2);
  const o = first(c); assert.equal(o.defender_cell.status, 'held_cursor');
  assert.equal(o.guard_exit_result, 'state_exit_candidate'); assert.equal(o.punish_opportunity, null);
});

test('type0 with raw DEF and new damage are not promoted to recovery', () => {
  for (const state of [27, 32]) {
    const c = fixture(); set(c, 3, 1, 'act_st', state);
    if (state === 32) set(c, 3, 1, 'vital_new', 900);
    const o = first(c); assert.equal(o.guard_exit_result, 'not_recovery_proof');
    assert.deepEqual(o.fresh_blue_frames, []); assert.equal(o.response, null);
  }
});

test('absent or invalid meter values never become fresh blue', () => {
  for (const [n,v] of [['type', false], ['type', 100], ['index', 80], ['size', 81], ['empty', false], ['end', 2]]) {
    const c = fixture(); set(c, 3, 2, 'display_meter_' + n, v);
    assert.equal(first(c).blue_stop, 'unavailable_or_unknown_cell');
  }
  for (const n of ['empty', 'not_whole', 'not_add']) {
    const c = fixture(); set(c, 3, 2, 'display_meter_' + n, 1);
    assert.equal(first(c).blue_stop, 'excluded_cell_flags');
  }
});

test('display timing, resets, and cursor skips stop rather than interpolate', () => {
  const c = fixture(); c.samples[3][c.columns.indexOf('display_prev_frame')] = 3;
  assert.equal(first(c).blue_stop, 'display_clock_mismatch');
  const b = fixture(); b.samples[3][b.columns.indexOf('meter_start_frame')] = 4;
  assert.equal(first(b).blue_stop, 'meter_reset');
  const d = fixture(); set(d, 3, 2, 'display_meter_index', 9);
  assert.equal(first(d).blue_stop, 'cursor_jump');
});

test('ring wrap is observed only after valid79 and a consecutive clock', () => {
  const c = fixture();
  for (let i = 0; i < 9; i++) set(c, i, 2, 'display_meter_index', (77 + i) % 80);
  assert.deepEqual(first(c).fresh_blue_frames, [4, 5, 6]);
});

test('gaps and ended capture cannot invent later attacks', () => {
  const c = fixture(); c.samples.splice(4, 1); c.sample_count--;
  const o = first(c); assert.deepEqual(o.fresh_blue_frames, [4]); assert.equal(o.blue_stop, 'clock_gap');
  assert.equal(o.response.first_attack_frame, null); assert.equal(o.response.stop, 'clock_gap');
  const b = fixture(); b.samples = b.samples.slice(0, 4); b.sample_count = 4;
  assert.equal(first(b).response.stop, 'capture_end');
});

test('new reactions and changed opponent sequence stop the relevant searches', () => {
  const c = fixture(); set(c, 4, 1, 'act_st', 32); set(c, 4, 1, 'vital_new', 900);
  assert.equal(first(c).response.stop, 'new_reaction'); assert.deepEqual(first(c).fresh_blue_frames, [4]);
  const b = fixture(); set(b, 4, 2, 'action_id', 99);
  assert.equal(first(b).blue_stop, 'opponent_sequence_changed');
  const d = fixture(); set(d, 4, 2, 'hit_stop', 1);
  assert.equal(first(d).blue_stop, 'reaction_or_stop');
});

test('identical duplicates are harmless, conflicting display duplicates are rejected', () => {
  const c = fixture(); c.samples.splice(3, 0, [...c.samples[2]]); c.sample_count++;
  assert.deepEqual(first(c).fresh_blue_frames, [4, 5, 6]);
  set(c, 3, 2, 'display_meter_type', 7);
  assert.throws(() => first(c), /Conflicting duplicate display/);
});

test('unknown build, profile, and missing meter columns fail closed', () => {
  const a = fixture(); a.metadata.version++;
  assert.throws(() => first(a), /Unverified/);
  const b = fixture(); delete b.metadata.frame_meter_profile;
  assert.throws(() => first(b), /Unsupported meter/);
  const c = fixture(), i = c.columns.indexOf('p1.display_meter_end');
  c.columns.splice(i, 1); c.samples.forEach(r => r.splice(i, 1));
  assert.throws(() => first(c), /Missing meter/);
});

test('same-clock flow transitions are retained and stop both observation searches', () => {
  const c = fixture(); c.samples.splice(4, 0, [...c.samples[3]]); c.sample_count++;
  c.samples[4][c.columns.indexOf('fight_st')] = 5;
  const r = inspectOpportunities(c), o = r.observations[0];
  assert.equal(r.duplicate_context_changes.length, 1);
  assert.equal(o.blue_stop, 'flow_transition'); assert.equal(o.response.stop, 'flow_transition');
  assert.deepEqual(o.nearby_events, []);
});

test('attack search does not interpret an attack beyond30 updates as the immediate response', () => {
  const c = fixture();
  const last = c.samples.at(-1);
  for (let i = 9; i < 40; i++) {
    const row = [...last];
    for (const n of ['replay_frame', 'stage_frame', 'display_prev_frame']) row[c.columns.indexOf(n)] = i + 1;
    c.samples.push(row);
  }
  c.sample_count = c.samples.length;
  for (let i = 3; i < 39; i++) set(c, i, 1, 'act_st', 4);
  const o = first(c); assert.equal(o.response.stop, 'observation_limit');
  assert.equal(o.response.observed_through, 33); assert.equal(o.response.first_attack_frame, null);
});
