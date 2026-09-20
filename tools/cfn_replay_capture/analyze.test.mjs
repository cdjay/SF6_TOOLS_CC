import test from 'node:test';
import assert from 'node:assert/strict';
import { summarize, compare } from './analyze.mjs';

const pfields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
  'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new'];
function capture(speed = '1x') {
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'render_tick', 'thread_id',
    ...[1, 2].flatMap(s => pfields.map(n => `p${s}.${n}`)), 'p1.display_atk_margin'];
  return { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped',
    metadata: { replay_id: 'TEST', version: 123, random_seed: 5,
      players: [{ fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, requested_speed: speed, stop_reason: 'manual', issue_counts: {}, sample_count: 20,
    samples: Array.from({ length: 20 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame'].includes(n) ? i : n === 'render_tick' ? Math.floor(i / (speed === '8x' ? 8 : 1)) : 0)),
  };
}
test('different render groupings do not change per-tick comparison', () => {
  const result = compare(capture(), capture('8x'));
  assert.equal(result.observed_intervals_match, true);
  assert.equal(result.full_replay_verified, false);
});
test('sequential thread changes are reported separately from data integrity', () => {
  const a = capture(), b = capture('8x');
  b.metadata.sampling_policy = 'non_overlapping_update_callbacks_v1';
  for (let i = 10; i < 20; i++) b.samples[i][b.columns.indexOf('thread_id')] = 12;
  const result = compare(a, b);
  assert.equal(result.observed_intervals_match, true);
  assert.equal(result.candidate.thread_transitions, 1);
  assert.deepEqual(result.candidate.observed_thread_ids, [0, 12]);
  assert.equal(result.full_replay_verified, false);
});
test('overlap failure still blocks a successful comparison', () => {
  const a = capture(); a.stop_reason = 'overlapping_update'; a.issue_counts.overlapping_update = 1;
  assert.equal(compare(a, structuredClone(a)).observed_intervals_match, false);
});
test('missing accelerated frame is not hidden', () => {
  const b = capture('8x'); b.samples.splice(5, 1); b.sample_count--;
  const result = compare(capture(), b);
  assert.equal(result.observed_intervals_match, false); assert.equal(result.only_reference_clocks, 1);
  assert.equal(result.candidate.continuity.replay_clock_gaps, 1);
});
test('same frame with different HP is a mismatch', () => {
  const b = capture('8x'); b.samples[5][b.columns.indexOf('p2.vital_new')] = 99;
  assert.equal(compare(capture(), b).different_clocks, 1);
});
test('duplicate same-clock variants remain ambiguous even if repeated in both files', () => {
  const a = capture(); const row = [...a.samples[5]]; row[a.columns.indexOf('p1.action_id')] = 12;
  a.samples.splice(6, 0, row); a.sample_count++;
  assert.equal(summarize(a).conflicting_clocks, 1); assert.equal(compare(a, structuredClone(a)).observed_intervals_match, false);
});
test('identical pause duplicates do not create false state differences', () => {
  const b = capture(); b.samples.splice(6, 0, [...b.samples[5]]); b.sample_count++;
  assert.equal(compare(capture(), b).observed_intervals_match, true);
});
test('different UI timing is not confused with core simulation mismatch', () => {
  const b = capture('8x'); b.samples[5][b.columns.indexOf('p1.display_atk_margin')] = -6;
  assert.equal(compare(capture(), b).observed_intervals_match, true);
});
test('rewinds prevent positive comparison claim', () => {
  const a = capture(); a.samples.push([...a.samples[0]]); a.sample_count++;
  assert.equal(compare(a, structuredClone(a)).observed_intervals_match, false);
});
test('absent values cannot match each other as evidence', () => {
  const a = capture(); a.samples[0][a.columns.indexOf('p1.hit_st')] = false;
  assert.equal(compare(a, structuredClone(a)).observed_intervals_match, false);
});
test('identity/build/control mode mismatch rejected', () => {
  for (const change of [a => a.metadata.version++, a => a.metadata.players[0].control_mode = 0,
    a => a.metadata.replay_id = 'OTHER', a => a.metadata.random_seed++]) {
    const b = capture(); change(b); assert.throws(() => compare(capture(), b));
  }
});
test('malformed data rejected; empty intervals cannot pass', () => {
  const a = capture(); a.samples[0].pop(); assert.throws(() => summarize(a));
  const b = capture(); b.samples = []; b.sample_count = 0;
  assert.equal(compare(b, structuredClone(b)).observed_intervals_match, false);
});
