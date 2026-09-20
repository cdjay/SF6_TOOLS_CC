import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { inspectRecovery, states } from './recovery.mjs';

const engineFields = ['engine_action_id', 'engine_action_frame_raw', 'engine_margin_start_raw',
  'engine_frame_num_raw', 'engine_speed_raw', 'engine_state_flags', 'engine_battle_version',
  'engine_loop_count', 'engine_style_index'];
const attackStates = new Set([states.ATCK, states.SPECIAL, states.SUPER]);
const ordinaryStates = new Set([states.FOOTWORK, states.SIT, states.SITD, states.STAND,
  states.STAND_TURN, states.SIT_TURN, states.WALK, states.DUCK_WALK, states.DASH]);

export function inspectBoundaries(capture, round = 0) {
  const recovery = inspectRecovery(capture, round);
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const required = [1, 2].flatMap(s => engineFields.map(n => `p${s}.${n}`));
  if (required.some(n => ix[n] === undefined)) throw new Error('Missing engine evidence columns');
  const rows = [], byFrame = new Map();
  const get = (r, s, n) => r[ix[`p${s}.${n}`]];
  for (const row of capture.samples) {
    if (row[ix.round] !== round || row[ix.battle_round] !== round) continue;
    if (required.some(n => !Number.isSafeInteger(row[ix[n]]))) throw new Error('Unavailable engine evidence');
    for (const s of [1, 2]) {
      if (get(row, s, 'action_id') !== get(row, s, 'engine_action_id')
          || get(row, s, 'action_frame_raw') !== get(row, s, 'engine_action_frame_raw')) {
        throw new Error('Engine identity/progress differs from existing getter');
      }
    }
    const f = row[ix.replay_frame];
    if (byFrame.has(f)) continue; // inspectRecovery has rejected conflicting clocks and replay passes.
    byFrame.set(f, rows.length); rows.push(row);
  }
  const snapshot = (r, s) => ({ replay_frame: r[ix.replay_frame], stage_frame: r[ix.stage_frame],
    ...Object.fromEntries(['action_id', 'act_st', 'hit_stop', 'vital_new', 'x_raw', 'y_raw',
      ...engineFields].map(n => [n, get(r, s, n)])) });
  const contiguous = (a, b) => b && b[ix.replay_frame] === a[ix.replay_frame] + 1
    && b[ix.stage_frame] === a[ix.stage_frame] + 1;
  const changes = (a, b, s) => {
    const reasons = [];
    if (get(a, s, 'action_id') !== get(b, s, 'action_id')) reasons.push('action_changed');
    else if (get(b, s, 'action_frame_raw') < get(a, s, 'action_frame_raw')) reasons.push('progress_decreased');
    for (const n of ['act_st', 'engine_margin_start_raw', 'engine_style_index', 'engine_loop_count']) {
      if (get(a, s, n) !== get(b, s, n)) reasons.push(n + '_changed');
    }
    if (get(b, s, 'vital_new') < get(a, s, 'vital_new')) reasons.push('hp_loss');
    return reasons;
  };
  const observations = recovery.episodes.filter(e => e.kind === 'guard' && e.result === 'state_exit_candidate').map(e => {
    const side = 3 - e.side, start = byFrame.get(e.start.clock.replay_frame), end = byFrame.get(e.end.clock.replay_frame);
    const o = { defender: e.side, opponent: side, guard_start: e.start.clock.replay_frame,
      defender_exit: e.end.clock.replay_frame, guard_refreshes: e.refreshes,
      opponent_at_guard_start: snapshot(rows[start], side), opponent_at_defender_exit: snapshot(rows[end], side),
      changes_during_guard: [], boundary: null, observed_frame_difference: null,
      result: 'unresolved', actionable_frame: null, frame_advantage: null, punish_opportunity: null,
      attack_owner_verified: false };
    for (let i = start + 1; i <= end; i++) {
      if (!contiguous(rows[i - 1], rows[i])) throw new Error('Noncontiguous guard episode');
      const reasons = changes(rows[i - 1], rows[i], side);
      if (reasons.length) o.changes_during_guard.push({ before: snapshot(rows[i - 1], side),
        after: snapshot(rows[i], side), reasons });
    }
    if (o.changes_during_guard.length) { o.result = 'opponent_changed_during_guard'; return o; }
    const current = rows[end];
    if (!attackStates.has(get(current, side, 'act_st'))) { o.result = 'opponent_not_in_attack_state'; return o; }
    if (get(current, side, 'engine_margin_start_raw') <= 0
        || get(current, side, 'action_frame_raw') >= get(current, side, 'engine_margin_start_raw')) {
      o.result = 'margin_unusable_or_already_reached'; return o;
    }
    // Observe only the first boundary. Never follow a subsequent attack and assign its length to this one.
    for (let i = end + 1; i < rows.length && rows[i][ix.replay_frame] <= o.defender_exit + 120; i++) {
      const before = rows[i - 1], after = rows[i];
      if (!contiguous(before, after)) { o.result = 'clock_gap'; return o; }
      const reasons = changes(before, after, side);
      const sameAction = get(before, side, 'action_id') === get(after, side, 'action_id');
      if (sameAction && get(after, side, 'action_frame_raw') >= get(after, side, 'engine_margin_start_raw')) {
        reasons.push('margin_reached');
      }
      if (!reasons.length) continue;
      o.boundary = { before: snapshot(before, side), after: snapshot(after, side), reasons };
      o.observed_frame_difference = after[ix.replay_frame] - o.defender_exit;
      const margin = get(before, side, 'engine_margin_start_raw'), frame = get(before, side, 'action_frame_raw');
      const speed = get(before, side, 'engine_speed_raw');
      const aligned = margin > 0 && frame < margin && speed > 0 && frame + speed >= margin;
      const disrupted = reasons.some(n => ['hp_loss', 'progress_decreased', 'engine_margin_start_raw_changed',
        'engine_style_index_changed', 'engine_loop_count_changed'].includes(n) && (sameAction || n === 'hp_loss'));
      const quiet = get(before, side, 'hit_stop') === 0 && get(after, side, 'hit_stop') === 0;
      o.boundary.margin_step_aligned = aligned;
      o.result = aligned && quiet && !disrupted && ordinaryStates.has(get(after, side, 'act_st'))
        ? 'ordinary_state_at_margin_observed' : 'boundary_not_recovery_proof';
      return o;
    }
    o.result = rows.at(-1)[ix.replay_frame] < o.defender_exit + 120 ? 'capture_end' : 'observation_limit';
    return o;
  });
  return { schema: 'sf6cc.cfn-boundary-evidence.experimental.v1', replay_id: capture.metadata.replay_id,
    version: capture.metadata.version, round, integrity: recovery.integrity, observations,
    summary: observations.reduce((out, o) => { out[o.result] = (out[o.result] ?? 0) + 1; return out; }, {}),
    actionable_timing_verified: false, full_replay_verified: false,
    limitations: ['Frame differences describe observed states, not earliest legal action or frame advantage.',
      'Margin-step alignment does not prove recovery or cancel legality. Flags remain uninterpreted.',
      'Opposing player identity does not establish attack ownership; projectiles and multi-hit sequences need separate evidence.',
      'No startup, range, resource or input-buffer conditions verified; no missed-punish verdict.'] };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, output, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error('Usage: node boundaries.mjs capture.json output.json');
  const report = inspectBoundaries(JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, '')));
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify({ summary: report.summary, observations: report.observations.map(o => ({
    defender: o.defender, start: o.guard_start, exit: o.defender_exit, result: o.result,
    boundary: o.boundary?.after.replay_frame, observed_frame_difference: o.observed_frame_difference })) }, null, 2));
}
