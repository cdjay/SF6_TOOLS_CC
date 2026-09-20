import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { inspectRecovery, states } from './recovery.mjs';
import { inspectBoundaries } from './boundaries.mjs';
import { inspectEvents } from './events.mjs';
import { meterCell } from './meter_evidence.mjs';

const attacks = new Set([states.ATCK, states.SPECIAL, states.SUPER]);
const clockNames = ['round', 'replay_frame', 'battle_round', 'stage_frame'];
const flags = ['empty', 'changed', 'end', 'not_add', 'not_whole'];
const meterFields = ['size', 'index', 'type', ...flags].map(n => 'display_meter_' + n);

export function inspectOpportunities(capture, round = 0) {
  if (capture.metadata?.frame_meter_profile !== 'native_cursor_cell_v1') throw new Error('Unsupported meter profile');
  const recovery = inspectRecovery(capture, round);
  const boundaries = inspectBoundaries(capture, round);
  const events = inspectEvents(capture, round);
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const required = ['display_prev_frame', 'meter_start_frame', ...[1, 2].flatMap(s => meterFields.map(n => `p${s}.${n}`))];
  if (required.some(n => ix[n] === undefined)) throw new Error('Missing meter columns');
  const get = (r, n) => r?.[ix[n]], p = (r, s, n) => get(r, `p${s}.${n}`);
  const clock = r => Object.fromEntries(clockNames.map(n => [n, get(r, n)]));
  const key = r => clockNames.map(n => get(r, n)).join(':');
  const contiguous = (a, b) => a && b && clockNames.filter(n => n.endsWith('round')).every(n => get(a, n) === get(b, n))
    && get(b, 'replay_frame') === get(a, 'replay_frame') + 1 && get(b, 'stage_frame') === get(a, 'stage_frame') + 1;
  const rows = [], byClock = new Map(), contextChanges = [], contextBarriers = new Set();
  const evidenceColumns = capture.columns.filter(n => /^p[12]\./.test(n) || required.includes(n));
  for (const r of capture.samples) {
    if (get(r, 'round') !== round || get(r, 'battle_round') !== round) continue;
    const k = key(r), existing = byClock.get(k);
    if (existing !== undefined) {
      if (existing !== rows.length - 1) throw new Error('Repeated replay pass');
      if (evidenceColumns.some(n => get(rows[existing], n) !== get(r, n))) throw new Error('Conflicting duplicate display evidence');
      if (get(rows[existing], 'fight_st') !== get(r, 'fight_st')) {
        contextChanges.push({ clock: clock(r), before: get(rows[existing], 'fight_st'), after: get(r, 'fight_st') });
        contextBarriers.add(existing);
      }
      continue;
    }
    byClock.set(k, rows.length); rows.push(r);
  }
  function cell(i, side) {
    return meterCell(rows, i, ix, side);
  }
  const separation = r => Math.abs(p(r, 1, 'x_raw') - p(r, 2, 'x_raw'));
  const sequenceChanged = (a, b, s) => ['action_id', 'engine_style_index', 'engine_loop_count'].some(n => p(a, s, n) !== p(b, s, n))
    || p(b, s, 'action_frame_raw') < p(a, s, 'action_frame_raw');
  const observations = recovery.episodes.filter(e => e.kind === 'guard').map(e => {
    const o = { defender: e.side, opponent: 3 - e.side, guard_start: e.start.clock.replay_frame,
      guard_end: e.end?.clock.replay_frame ?? null, guard_exit_result: e.result, guard_exit_reasons: e.reasons,
      defender_cell: null, opponent_cell: null, horizontal_separation_raw: null,
      fresh_blue_frames: [], blue_stop: null, response: null, nearby_events: [],
      sequence_boundary: null, actionable_frame: null, frame_advantage: null, punish_opportunity: null,
      attack_owner_verified: false, reach_verified: false };
    if (!e.end) return o;
    const start = byClock.get(clockNames.map(n => e.end.clock[n]).join(':'));
    if (start === undefined) throw new Error('Missing guard end clock');
    o.defender_cell = cell(start, e.side); o.opponent_cell = cell(start, o.opponent);
    o.horizontal_separation_raw = separation(rows[start]);
    const boundary = boundaries.observations.find(b => b.defender === e.side && b.defender_exit === o.guard_end);
    o.sequence_boundary = boundary ?? null;
    if (e.result !== 'state_exit_candidate') { o.blue_stop = 'guard_exit_unverified'; return o; }
    // Count only consecutive newly advanced blue cells. Never extend through a held old cell.
    for (let i = start; i < start + 120; i++) {
      const r = rows[i], before = rows[i - 1];
      if (!r) { o.blue_stop = 'capture_end'; break; }
      if (contextBarriers.has(i)) { o.blue_stop = 'flow_transition'; break; }
      if (!contiguous(before, r)) { o.blue_stop = 'clock_gap'; break; }
      if (i > start && sequenceChanged(before, r, o.opponent)) { o.blue_stop = 'opponent_sequence_changed'; break; }
      if ([1, 2].some(s => p(r, s, 'hit_stop') > 0 || p(r, s, 'vital_new') < p(before, s, 'vital_new'))
        || p(r, e.side, 'guard_time') > 0 || [states.DAMAGE, states.CATCH, states.HOLD].includes(p(r, e.side, 'act_st'))) {
        o.blue_stop = 'reaction_or_stop'; break;
      }
      const c = cell(i, o.opponent);
      if (c.status !== 'advanced_cell') { o.blue_stop = c.status; break; }
      if (c.display_meter_type !== 8) { o.blue_stop = 'not_blue'; break; }
      o.fresh_blue_frames.push(get(r, 'replay_frame'));
    }
    o.blue_stop ??= 'observation_limit';
    o.response = { first_attack_frame: null, elapsed_updates: null, action_id: null,
      horizontal_separation_raw: null, stop: null, observed_through: null };
    // This is an observed state entry, not an input timestamp or a reaction-time measurement.
    for (let i = start; i < start + 30; i++) {
      const r = rows[i], before = rows[i - 1];
      if (!r) { o.response.stop = 'capture_end'; break; }
      if (contextBarriers.has(i)) { o.response.stop = 'flow_transition'; break; }
      if (!contiguous(before, r)) { o.response.stop = 'clock_gap'; break; }
      o.response.observed_through = get(r, 'replay_frame');
      if (p(r, e.side, 'vital_new') < p(before, e.side, 'vital_new') || p(r, e.side, 'guard_time') > 0
        || [states.DAMAGE, states.CATCH, states.HOLD, states.SLEEP, states.GETUP].includes(p(r, e.side, 'act_st'))) {
        o.response.stop = 'new_reaction'; break;
      }
      if (attacks.has(p(r, e.side, 'act_st'))) {
        Object.assign(o.response, { first_attack_frame: get(r, 'replay_frame'), elapsed_updates: get(r, 'replay_frame') - o.guard_end,
          action_id: p(r, e.side, 'action_id'), horizontal_separation_raw: separation(r), stop: 'attack_state_observed' });
        break;
      }
    }
    o.response.stop ??= 'observation_limit';
    let last = start;
    while (!contextBarriers.has(last) && last + 1 < rows.length && last + 1 < start + 30
      && !contextBarriers.has(last + 1) && contiguous(rows[last], rows[last + 1])) last++;
    o.nearby_events = contextBarriers.has(start) ? [] : events.events.filter(v => v.clock.replay_frame >= o.guard_end && v.clock.replay_frame <= get(rows[last], 'replay_frame'));
    return o;
  });
  return { schema: 'sf6cc.cfn-opportunity-observations.experimental.v1', replay_id: capture.metadata.replay_id,
    version: capture.metadata.version, round, integrity: recovery.integrity, duplicate_context_changes: contextChanges, observations,
    actionable_timing_verified: false, full_replay_verified: false,
    limitations: ['New blue cells are observations, not a proven punish window or frame advantage.',
      'Held, reset, missing, skipped and excluded cells stop the count; they are not inferred as safe or vulnerable.',
      'Guard state and cell classification disagreements remain unresolved.',
      'Attack entry delay is not human reaction time, input time, move startup or earliest legal action.',
      'Coordinate separation is not hitbox reach. Nearby events are temporal context, not attack attribution.',
      'Blue observation is bounded to120 updates and response/event context to30 updates; absence is not a missed punish.'] };
}

export function opportunityMarkdown(report) {
  const lines = [`# 第${report.round + 1}局反击时机观察`, '', `录像：${report.replay_id}`, '',
    '这是值得回看的片段，不是漏确反判定。帧号使用录像计数。',
    '新蓝格只计入连续前进的格子；旧格停留、换招或缺少数据即停止。出手间隔不是人的反应速度。',
    '位置间距是双方坐标差，不等于招式射程；不能据此判断能否打到。', '',
    '| 防守方 | 防御结束候选帧 | 对手新蓝格 | 玩家攻击开始 | 位置间距 | 核对事项 |',
    '| --- | ---: | --- | --- | ---: | --- |'];
  for (const o of report.observations) {
    const blue = o.fresh_blue_frames, response = o.response;
    const notes = [];
    if (o.guard_exit_result !== 'state_exit_candidate') notes.push('尚不能认定防御后恢复');
    if (o.defender_cell?.status === 'held_cursor') notes.push('防守方格子仍停留');
    if (o.blue_stop === 'held_cursor') notes.push('对手格子停留，停止计数');
    if (o.sequence_boundary?.changes_during_guard.length) notes.push('防御期间对手已换动作或状态');
    if (o.blue_stop && !['held_cursor', 'not_blue', 'opponent_sequence_changed', 'guard_exit_unverified'].includes(o.blue_stop)) notes.push('蓝格区间因证据不足或新反应而截断');
    if (o.blue_stop === 'opponent_sequence_changed') notes.push('对手换动作后停止计数');
    const attack = response?.first_attack_frame != null ? `${response.first_attack_frame}（间隔${response.elapsed_updates}帧）`
      : response ? `观察至${response.observed_through ?? '未知'}帧未见攻击开始` : '未判断';
    lines.push(`| ${o.defender}P | ${o.guard_end ?? '未录完'} | ${blue.length ? `${blue[0]}～${blue.at(-1)}（${blue.length}格）` : '未计入'} | ${attack} | ${o.horizontal_separation_raw == null ? '未知' : (o.horizontal_separation_raw / 65536).toFixed(2)} | ${notes.join('；') || '尚需验证招式速度、距离和条件'} |`);
  }
  lines.push('', '同一片段里出现命中，不等于此前已有确反机会；没有攻击，也不等于漏确反。', '');
  return lines.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, base, ...extra] = process.argv.slice(2);
  if (!input || !base || extra.length) throw new Error('Usage: node opportunities.mjs capture.json output-base');
  const report = inspectOpportunities(JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, '')));
  writeFileSync(base + '.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  writeFileSync(base + '.md', opportunityMarkdown(report), { flag: 'wx' });
  console.log(JSON.stringify({ observations: report.observations.length,
    with_new_blue_cells: report.observations.filter(o => o.fresh_blue_frames.length).length,
    punish_verdicts: 0 }));
}
