import test from 'node:test';
import assert from 'node:assert/strict';
import { frameCondition, guardNativeEvidence } from './native_review.mjs';

test('minus four includes a fastest four-frame attack, not a mandatory trade', () => {
  assert.deepEqual(frameCondition(-4, 4), { sum: 0, timely: true });
  assert.deepEqual(frameCondition(-6, 6), { sum: 0, timely: true });
  assert.deepEqual(frameCondition(-6, 5, 1), { sum: 0, timely: true });
  assert.deepEqual(frameCondition(-6, 6, 1), { sum: 1, timely: false });
  assert.equal(frameCondition(-3, 4).timely, false);
});

test('unknown, positive and invalid inputs are not punish arithmetic', () => {
  for (const args of [[null, 4], [-4, null], [4, 4], [0, 4], [-4, 0], [-4, 4, -1], [-4, 4, null], [-4, 4.5]])
    assert.equal(frameCondition(...args), null);
});

const columns = ['replay_frame', 'stage_frame', 'display_prev_frame', 'display_stun_frame',
  'p1.action_id', 'p1.action_frame_raw', 'p1.engine_style_index', 'p1.engine_loop_count'];
const ix = Object.fromEntries(columns.map((n, i) => [n, i]));
const fixture = nums => nums.map((n, i) => [i + 1, i + 1, i + 1, n, 600, i * 65536, 0, 0]);

test('multihit intermediate disadvantage is not the final guard value', () => {
  const e = guardNativeEvidence(fixture([0, -15, -13, -3, -3]), ix, 2, 5, 1);
  assert.equal(e.final_value, -3); assert.deepEqual(e.changes.map(c => c.value), [-15, -13, -3]);
  assert.equal(e.sign_basis_verified, false);
});

test('unwitnessed same number remains unverified rather than falsely fresh or stale', () => {
  const e = guardNativeEvidence(fixture([-6, -6, -6, -6]), ix, 2, 4, 1);
  assert.equal(e.final_value, -6); assert.equal(e.update_observed, false);
});

test('new hit at guard exit cannot overwrite the guard episode value', () => {
  const e = guardNativeEvidence(fixture([0, -6, -6, 3]), ix, 2, 4, 1);
  assert.equal(e.final_value, -6); assert.equal(e.changes.length, 1);
});

test('changed attacker and incomplete display timing are explicit barriers', () => {
  const rows = fixture([0, -8, -8, -8]); rows[2][ix['p1.action_id']] = 953; rows[3][ix['p1.action_id']] = 953;
  let e = guardNativeEvidence(rows, ix, 2, 4, 1);
  assert.deepEqual(e.opponent_action_changes_after_update, [{ frame: 3, before: 600, after: 953 }]);
  rows[2][ix.display_prev_frame] = 1;
  e = guardNativeEvidence(rows, ix, 2, 4, 1); assert.equal(e.complete_display_interval, false);
});

test('a truncated guard episode is never a complete native interval', () => {
  assert.equal(guardNativeEvidence(fixture([0, -6, -6]), ix, 2, 5, 1).complete_display_interval, false);
  assert.equal(guardNativeEvidence(fixture([0, -6, -6]), ix, 2, Infinity, 1).complete_display_interval, false);
});
