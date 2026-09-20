import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { summarize } from './analyze.mjs';

// Native ACT_ST constants observed for build 20004000, not character Action IDs.
// Source and limitations: docs/research/CFN_REPLAY_CAPTURE.md.
export const states = Object.freeze({ FOOTWORK: 0, SIT: 1, SITD: 3, STAND: 4,
  STAND_TURN: 5, SIT_TURN: 6, WALK: 8, DUCK_WALK: 9, DASH: 10, ATCK_LAND: 13,
  JUMP: 14, JUMP_LAND: 16, SJUMP_DMG: 20, FLYING: 22, FALL: 26, DEF: 27,
  JDEF: 28, ATCK: 29, SPECIAL: 30, SUPER: 31, DAMAGE: 32, SLEEP: 34,
  GETUP: 35, UKEMI: 36, CATCH: 37, HOLD: 38, PARRY: 39, WITHDRAW: 41 });
const stateNames = Object.fromEntries(Object.entries(states).map(([n, v]) => [v, n]));
const profiles = [
  { kind: 'guard', field: 'guard_time', state: states.DEF },
  { kind: 'air_guard', field: 'guard_time', state: states.JDEF },
  { kind: 'parry', field: 'guard_time', state: states.PARRY },
  { kind: 'damage', field: 'damage_time', state: states.DAMAGE },
];
const possibleExitStates = new Set(['FOOTWORK', 'SIT', 'SITD', 'STAND', 'STAND_TURN',
  'SIT_TURN', 'WALK', 'DUCK_WALK', 'DASH', 'JUMP', 'ATCK', 'SPECIAL', 'SUPER'].map(n => states[n]));
const evidenceFields = ['act_st', 'action_id', 'action_frame_raw', 'guard_time', 'damage_time',
  'hit_stop', 'vital_new', 'hit_st', 'pose_st', 'x_raw', 'y_raw'];

export function inspectRecovery(capture, round = 0) {
  const integrity = summarize(capture);
  if (capture.metadata.version !== 20004000) throw new Error('Unverified ACT_ST build');
  if (!Number.isInteger(round) || round < 0) throw new Error('Invalid round');
  if (integrity.conflicting_clocks) throw new Error('Conflicting clock states');
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const required = [1, 2].flatMap(s => evidenceFields.map(n => `p${s}.${n}`));
  if (required.some(n => ix[n] === undefined)) throw new Error('Missing recovery evidence');
  const get = (row, side, field) => row[ix[`p${side}.${field}`]];
  const clock = row => ({ round: row[ix.round], replay_frame: row[ix.replay_frame],
    battle_round: row[ix.battle_round], stage_frame: row[ix.stage_frame] });
  const snapshot = row => ({ clock: clock(row), players: [1, 2].map(s => ({
    ...Object.fromEntries(evidenceFields.map(n => [n, get(row, s, n)])),
    state_name: stateNames[get(row, s, 'act_st')] ?? 'UNKNOWN',
  })) });
  const active = new Map(), seen = new Set(), episodes = [];
  const outsideState = { guard_time: 0, damage_time: 0 };
  let previous = null, segment = 0, duplicates = 0;
  function truncate(reason) {
    for (const e of active.values()) {
      e.result = 'incomplete'; e.reasons = [reason]; episodes.push(e);
    }
    active.clear();
  }
  for (const row of capture.samples) {
    if (row[ix.round] !== round || row[ix.battle_round] !== round) {
      truncate('round_boundary'); previous = null; continue;
    }
    if (required.some(n => row[ix[n]] === false)) throw new Error('Unavailable recovery value');
    const key = JSON.stringify(clock(row));
    if (previous && key === JSON.stringify(clock(previous))) { duplicates++; continue; }
    if (seen.has(key)) throw new Error('Repeated replay pass');
    seen.add(key);
    const contiguous = previous && row[ix.replay_frame] === previous[ix.replay_frame] + 1
      && row[ix.stage_frame] === previous[ix.stage_frame] + 1;
    if (!contiguous) { truncate('clock_gap'); segment++; }
    for (const side of [1, 2]) {
      const currentState = get(row, side, 'act_st');
      for (const field of ['guard_time', 'damage_time']) {
        if (get(row, side, field) > 0 && !profiles.some(p => p.field === field && p.state === currentState)) outsideState[field]++;
      }
      for (const profile of profiles) {
        const id = `${side}:${profile.kind}`, count = get(row, side, profile.field);
        let e = active.get(id);
        const inProfile = currentState === profile.state && count > 0;
        if (e && !inProfile) {
          const reasons = [];
          const before = get(previous, side, profile.field);
          if (get(row, side, 'vital_new') < get(previous, side, 'vital_new')) reasons.push('new_hp_loss');
          if (get(row, side, 'hit_stop') !== 0) reasons.push('hit_stop_active');
          if (currentState === profile.state) reasons.push('still_same_reaction_state');
          if (!possibleExitStates.has(currentState)) reasons.push('reaction_or_unverified_state');
          if (before !== 1 || count !== 0) reasons.push('not_one_to_zero');
          if (!e.start_observed) reasons.push('partial_start');
          e.end = snapshot(row); e.last_positive = snapshot(previous);
          e.result = reasons.length ? 'not_recovery_proof' : 'state_exit_candidate';
          e.reasons = reasons;
          episodes.push(e); active.delete(id); e = null;
        }
        if (inProfile) {
          if (!e) {
            e = { side, kind: profile.kind, segment, start: snapshot(row),
              start_observed: !!contiguous && !(get(previous, side, 'act_st') === profile.state && get(previous, side, profile.field) > 0),
              start_with_carried_counter: !!contiguous && get(previous, side, profile.field) > 0,
              positive_samples: 0, refreshes: [], result: null, reasons: [],
              actionable_frame: null, frame_advantage: null, punish_opportunity: null };
            active.set(id, e);
          }
          e.positive_samples++;
          if (contiguous && get(previous, side, 'act_st') === profile.state
            && count > get(previous, side, profile.field) && get(previous, side, profile.field) > 0) {
            e.refreshes.push({ clock: clock(row), from: get(previous, side, profile.field), to: count });
          }
        }
      }
    }
    previous = row;
  }
  truncate('capture_end');
  episodes.sort((a, b) => a.start.clock.replay_frame - b.start.clock.replay_frame || a.side - b.side);
  return { schema: 'sf6cc.cfn-recovery-evidence.experimental.v1', replay_id: capture.metadata.replay_id,
    version: capture.metadata.version, round, integrity, episodes, duplicate_samples: duplicates,
    positive_counter_samples_outside_applicable_state: outsideState,
    summary: Object.fromEntries(profiles.map(p => {
      const list = episodes.filter(e => e.kind === p.kind);
      return [p.kind, { episodes: list.length, candidates: list.filter(e => e.result === 'state_exit_candidate').length,
        not_proof: list.filter(e => e.result === 'not_recovery_proof').length,
        incomplete: list.filter(e => e.result === 'incomplete').length }];
    })), actionable_timing_verified: false,
    limitations: ['State exits are candidates only; no earliest legal attack or cancel conditions verified.',
      'Positive counters outside their reaction state do not extend that reaction.',
      'Defender recovery alone cannot establish attacker recovery, frame advantage, range or a punish.'] };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, output, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error('Usage: node recovery.mjs capture.json output.json');
  const report = inspectRecovery(JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, '')));
  writeFileSync(output, JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  console.log(JSON.stringify({ summary: report.summary,
    positive_counter_samples_outside_applicable_state: report.positive_counter_samples_outside_applicable_state,
    endpoints: report.episodes.map(e => ({ side: e.side, kind: e.kind, start: e.start.clock.replay_frame,
      end: e.end?.clock.replay_frame, result: e.result, reasons: e.reasons })) }, null, 2));
}
