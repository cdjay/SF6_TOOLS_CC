import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const SCHEMA = 'sf6cc.cfn-state-capture.experimental.v1';
const clocks = ['round', 'replay_frame', 'battle_round', 'stage_frame'];
const minimumState = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
  'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new'];

function inspect(capture) {
  if (capture.schema !== SCHEMA || capture.state !== 'stopped') throw new Error('Not a stopped CFN experiment capture');
  if (!capture.metadata?.replay_id || !Number.isInteger(capture.metadata.version)) throw new Error('Missing replay identity/version');
  if (!Array.isArray(capture.metadata.players) || capture.metadata.players.length !== 2 ||
      capture.metadata.players.some(p => !Number.isInteger(p.fighter_id) || !Number.isInteger(p.control_mode))) {
    throw new Error('Missing player identity/control mode');
  }
  if (!Array.isArray(capture.columns) || new Set(capture.columns).size !== capture.columns.length) throw new Error('Invalid columns');
  const index = Object.fromEntries(capture.columns.map((name, i) => [name, i]));
  const required = [...clocks, 'thread_id', ...[1, 2].flatMap(side => minimumState.map(name => `p${side}.${name}`))];
  if (required.some(name => index[name] === undefined)) throw new Error('Missing required columns');
  if (!Array.isArray(capture.samples) || capture.samples.length !== capture.sample_count) throw new Error('Invalid sample count');
  const stateNames = capture.columns.filter(n => /^p[12]\./.test(n) && !n.includes('.display_')).sort();
  const byClock = new Map();
  const rounds = new Map();
  const missing = {};
  const continuity = { replay_clock_gaps: 0, stage_clock_gaps: 0, rewinds_or_resets: 0, round_gaps: 0 };
  let previous, threadTransitions = 0;
  const threadIds = new Set();
  for (const row of capture.samples) {
    if (!Array.isArray(row) || row.length !== capture.columns.length || row.some(v => v !== false && !Number.isFinite(v))) {
      throw new Error('Invalid sample values');
    }
    const get = name => row[index[name]];
    if (clocks.some(name => !Number.isInteger(get(name)) || get(name) < 0)) throw new Error('Invalid clock');
    const round = get('round'), replay = get('replay_frame'), stage = get('stage_frame');
    const thread = get('thread_id');
    if (!Number.isSafeInteger(thread) || thread < 0) throw new Error('Invalid thread identity');
    threadIds.add(thread);
    if (previous) {
      if (thread !== previous.thread) threadTransitions++;
      if (round < previous.round || (round === previous.round && (replay < previous.replay || stage < previous.stage))) continuity.rewinds_or_resets++;
      else if (round > previous.round + 1) continuity.round_gaps++;
      else if (round === previous.round) {
        if (replay > previous.replay + 1) continuity.replay_clock_gaps++;
        if (stage > previous.stage + 1) continuity.stage_clock_gaps++;
      }
    }
    previous = { round, replay, stage, thread };
    const range = rounds.get(round) ?? { round, first_replay_frame: replay, last_replay_frame: replay,
      first_stage_frame: stage, last_stage_frame: stage, samples: 0 };
    range.first_replay_frame = Math.min(range.first_replay_frame, replay);
    range.last_replay_frame = Math.max(range.last_replay_frame, replay);
    range.first_stage_frame = Math.min(range.first_stage_frame, stage);
    range.last_stage_frame = Math.max(range.last_stage_frame, stage);
    range.samples++;
    rounds.set(round, range);
    for (const name of stateNames) if (get(name) === false) missing[name] = (missing[name] ?? 0) + 1;
    const key = clocks.map(get).join(':');
    const fingerprint = JSON.stringify(stateNames.map(get));
    let entry = byClock.get(key);
    if (!entry) { entry = new Map(); byClock.set(key, entry); }
    entry.set(fingerprint, row);
  }
  return { index, stateNames, byClock, summary: {
    replay_id: capture.metadata.replay_id, version: capture.metadata.version,
    requested_speed: capture.requested_speed, speed_label_is_user_supplied: true,
    sample_count: capture.sample_count, unique_clocks: byClock.size,
    conflicting_clocks: [...byClock.values()].filter(variants => variants.size > 1).length,
    rounds: [...rounds.values()], continuity, missing_core_values: missing,
    stop_reason: capture.stop_reason, reported_issues: capture.issue_counts,
    max_samples_between_render_callbacks: capture.render_tick_max_samples,
    sampling_policy: capture.metadata.sampling_policy ?? 'legacy_fixed_thread',
    observed_thread_ids: [...threadIds].sort((a, b) => a - b), thread_transitions: threadTransitions,
    full_replay_verified: false,
  } };
}

export function summarize(capture) { return inspect(capture).summary; }

export function compare(reference, candidate) {
  const a = inspect(reference), b = inspect(candidate);
  const identity = meta => JSON.stringify({ id: meta.replay_id, version: meta.version,
    seed: meta.random_seed, players: meta.players.map(p => [p.fighter_id, p.playing_fighter_id, p.control_mode]) });
  if (identity(reference.metadata) !== identity(candidate.metadata)) throw new Error('Captures are not the same replay/build/players');
  if (JSON.stringify(a.stateNames) !== JSON.stringify(b.stateNames)) throw new Error('State columns differ');
  let shared = 0, different = 0, onlyReference = 0, onlyCandidate = 0;
  const examples = [];
  for (const [key, variants] of a.byClock) {
    const other = b.byClock.get(key);
    if (!other) { onlyReference++; continue; }
    shared++;
    if (variants.size !== other.size || [...variants.keys()].some(v => !other.has(v))) {
      different++;
      if (examples.length < 12) examples.push({ clock: key, reference_variants: variants.size, candidate_variants: other.size });
    }
  }
  for (const key of b.byClock.keys()) if (!a.byClock.has(key)) onlyCandidate++;
  const uncertain = [a.summary, b.summary].some(s =>
    s.conflicting_clocks > 0 || Object.keys(s.missing_core_values).length > 0 ||
    Object.values(s.continuity).some(n => n > 0) || !['manual', 'left_replay'].includes(s.stop_reason) ||
    Object.keys(s.reported_issues ?? {}).length > 0);
  return {
    reference: a.summary, candidate: b.summary,
    shared_clocks: shared, different_clocks: different, only_reference_clocks: onlyReference, only_candidate_clocks: onlyCandidate,
    examples,
    observed_intervals_match: shared > 0 && !different && !onlyReference && !onlyCandidate && !uncertain,
    full_replay_verified: false,
    note: 'Only captured intervals compared. Full-round start/end coverage, clock alignment, hook timing, UI freshness and real playback speed require live validation. No punish verdicts are produced.',
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const outputAt = args.indexOf('--output');
  const output = outputAt >= 0 ? args[outputAt + 1] : null;
  if (outputAt >= 0) args.splice(outputAt, 2);
  if (args.length < 1 || args.length > 2 || (outputAt >= 0 && !output)) {
    throw new Error('Usage: node analyze.mjs capture.json [comparison.json] [--output report.json]');
  }
  const captures = args.map(path => JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, '')));
  const result = captures.length === 2 ? compare(...captures) : summarize(captures[0]);
  const text = JSON.stringify(result, null, 2) + '\n';
  if (output) writeFileSync(output, text, { flag: 'wx' });
  else process.stdout.write(text);
}
