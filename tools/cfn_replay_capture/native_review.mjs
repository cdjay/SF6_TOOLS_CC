import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { inspectOpportunities } from './opportunities.mjs';
import { inspectEvents } from './events.mjs';

// Timing only. Reach, invulnerability and attack ownership are independent evidence.
export function frameCondition(opponentAdvantage, startup, delay = 0) {
  if (!Number.isSafeInteger(opponentAdvantage) || opponentAdvantage >= 0
    || !Number.isSafeInteger(startup) || startup < 1 || !Number.isSafeInteger(delay) || delay < 0) return null;
  const sum = opponentAdvantage + startup + delay;
  return { sum, timely: sum <= 0 };
}

export function guardNativeEvidence(rows, ix, start, end, opponent) {
  const get = (r, n) => r?.[ix[n]];
  const changes = [], actionChanges = [];
  let finalValue = null, complete = Number.isSafeInteger(end), lastChange = null, observed = 0;
  for (let i = 0; i < rows.length; i++) {
    const r = rows[i], prev = rows[i - 1], f = get(r, 'replay_frame');
    if (f < start || f >= end) continue;
    observed++;
    const n = get(r, 'display_stun_frame');
    const fresh = prev && f === get(prev, 'replay_frame') + 1
      && get(r, 'stage_frame') === get(prev, 'stage_frame') + 1
      && get(r, 'display_prev_frame') === get(r, 'stage_frame')
      && get(prev, 'display_prev_frame') === get(prev, 'stage_frame');
    if (!fresh || !Number.isSafeInteger(n)) complete = false;
    finalValue = Number.isSafeInteger(n) ? n : null;
    if (fresh && Number.isSafeInteger(n) && Number.isSafeInteger(get(prev, 'display_stun_frame'))
      && n !== get(prev, 'display_stun_frame')) {
      changes.push({ frame: f, value: n }); lastChange = f;
    }
  }
  complete = complete && observed === end - start;
  if (lastChange != null) for (let i = 1; i < rows.length; i++) {
    const r = rows[i], prev = rows[i - 1], f = get(r, 'replay_frame');
    if (f <= lastChange || f > end) continue;
    const prefix = `p${opponent}.`;
    if (['action_id', 'engine_style_index', 'engine_loop_count'].some(n => get(r, prefix + n) !== get(prev, prefix + n))
      || get(r, prefix + 'action_frame_raw') < get(prev, prefix + 'action_frame_raw')) {
      actionChanges.push({ frame: f, before: get(prev, prefix + 'action_id'), after: get(r, prefix + 'action_id') });
    }
  }
  return { final_value: finalValue, changes, complete_display_interval: complete,
    update_observed: changes.length > 0, opponent_action_changes_after_update: actionChanges,
    sign_basis_verified: false };
}

function responseEvidence(rows, ix, o) {
  const get = (r, n) => r?.[ix[n]], p = (r, s, n) => get(r, `p${s}.${n}`);
  const at = rows.findIndex(r => get(r, 'replay_frame') === o.guard_end);
  const out = { attack_frame: null, first_active_frame: null, observed_startup: null,
    delay_from_guard_exit: null, attack_action: null, stop: null, observed_through: null };
  if (at < 1) { out.stop = 'missing_endpoint'; return out; }
  let attack = null, continuousStartup = true;
  for (let i = at; i < rows.length && i < at + 30; i++) {
    const r = rows[i], prev = rows[i - 1], f = get(r, 'replay_frame');
    if (f !== get(prev, 'replay_frame') + 1 || get(r, 'stage_frame') !== get(prev, 'stage_frame') + 1
      || get(r, 'fight_st') !== get(prev, 'fight_st')) { out.stop = 'clock_or_flow_change'; break; }
    out.observed_through = f;
    if (p(r, o.defender, 'guard_time') > 0 || p(r, o.defender, 'vital_new') < p(prev, o.defender, 'vital_new')
      || [32, 34, 35, 37, 38].includes(p(r, o.defender, 'act_st'))) { out.stop = 'new_reaction'; break; }
    if (!attack && [29, 30, 31].includes(p(r, o.defender, 'act_st'))) {
      attack = r;
      out.attack_frame = f; out.attack_action = p(r, o.defender, 'action_id');
      out.delay_from_guard_exit = f - o.guard_end;
      continuousStartup = p(r, o.defender, 'action_frame_raw') === 0;
    }
    if (!attack) continue;
    if (['action_id', 'engine_style_index', 'engine_loop_count'].some(n => p(r, o.defender, n) !== p(attack, o.defender, n))) {
      out.stop = 'attack_changed'; break;
    }
    if (r !== attack && (p(r, o.defender, 'action_frame_raw') !== p(prev, o.defender, 'action_frame_raw') + 65536
      || p(prev, o.defender, 'hit_stop') !== 0)) continuousStartup = false;
    if (get(r, 'display_prev_frame') === get(r, 'stage_frame')
      && get(prev, 'display_prev_frame') === get(prev, 'stage_frame')
      && get(prev, 'meter_start_frame') === get(r, 'meter_start_frame')
      && p(r, o.defender, 'display_meter_size') === 80
      && p(r, o.defender, 'display_meter_index') === (p(prev, o.defender, 'display_meter_index') + 1) % 80
      && ['empty', 'not_add', 'not_whole'].every(n => p(r, o.defender, 'display_meter_' + n) === 0)
      && p(r, o.defender, 'display_meter_type') === 13) {
      out.first_active_frame = f;
      if (continuousStartup) out.observed_startup = f - out.attack_frame + 1;
      out.stop = 'active_cell_observed'; break;
    }
  }
  out.stop ??= 'observation_limit';
  return out;
}

export function nearbyGuardEvidence(rows, ix, at) {
  const get=(r,n)=>r?.[ix[n]], guard=(r,s)=>[27,28].includes(get(r,`p${s}.act_st`)) && get(r,`p${s}.guard_time`)>0;
  let lower=at, best=null;
  while(lower>0 && at-lower<600 && ['replay_frame','stage_frame'].every(n=>get(rows[lower],n)===get(rows[lower-1],n)+1)
    && get(rows[lower],'fight_st')===get(rows[lower-1],'fight_st')) lower--;
  for(const side of [1,2]) for(let j=at-1;j>=lower;j--) {
    if(get(rows[at],'replay_frame')-get(rows[j],'replay_frame')>30) break;
    if(!guard(rows[j],side)) continue;
    if(guard(rows[j+1],side)) return null;
    if(!best || j>best.last) best={last:j,side};
    break;
  }
  if(!best) return null;
  let start=best.last;
  while(start>lower && guard(rows[start-1],best.side)) start--;
  if(start===lower) return null;
  const first=get(rows[start],'replay_frame'), end=get(rows[best.last+1],'replay_frame');
  const e=guardNativeEvidence(rows.slice(lower,at+1),ix,first,end,3-best.side);
  if(!e.complete_display_interval || !e.update_observed) return null;
  return {value:e.final_value,frame:e.changes.at(-1).frame,guard_side:best.side,guard_start:first,guard_end:end,sign_basis_verified:false};
}

export function inspectNativeReview(capture) {
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  for (const n of ['display_stun_frame', 'display_prev_frame']) if (ix[n] == null) throw new Error('Missing native advantage evidence');
  const rounds = [...new Set(capture.samples.map(r => r[ix.round]))].sort((a, b) => a - b);
  const observations = [];
  for (const round of rounds) {
    const original = inspectOpportunities(capture, round);
    const events = inspectEvents(capture, round).events;
    let rows = capture.samples.filter(r => r[ix.round] === round && r[ix.battle_round] === round);
    rows = rows.filter((r, i) => !i || r[ix.replay_frame] !== rows[i - 1][ix.replay_frame]);
    const ko = rows.find(r => r[ix['p1.vital_new']] === 0 || r[ix['p2.vital_new']] === 0);
    if (ko) rows = rows.filter(r => r[ix.replay_frame] <= ko[ix.replay_frame]);
    for (const o of original.observations) {
      if (ko && o.guard_start > ko[ix.replay_frame]) continue;
      const native = guardNativeEvidence(rows, ix, o.guard_start, o.guard_end ?? Infinity, o.opponent);
      const response = responseEvidence(rows, ix, o);
      const formula = frameCondition(native.final_value, response.observed_startup, response.delay_from_guard_exit);
      const negative = native.complete_display_interval && native.update_observed && native.final_value <= -4;
      const at = rows.findIndex(r => r[ix.replay_frame] === o.guard_end);
      let contextEnd = o.guard_end;
      if (at >= 0) for (let i = at + 1; i < Math.min(at + 30, rows.length); i++) {
        if (rows[i][ix.replay_frame] !== rows[i - 1][ix.replay_frame] + 1
          || rows[i][ix.stage_frame] !== rows[i - 1][ix.stage_frame] + 1
          || rows[i][ix.fight_st] !== rows[i - 1][ix.fight_st]) break;
        contextEnd = rows[i][ix.replay_frame];
      }
      observations.push({ round: round + 1, defender: o.defender, guard_start: o.guard_start, guard_end: o.guard_end,
        guard_exit_result: o.guard_exit_result, native, response,
        selection: negative ? 'negative_value_review' : native.update_observed ? 'other_final_value' : 'update_not_witnessed',
        // The sign origin is not globally verified. Keep arithmetic conditional, never a verdict.
        timing_if_native_is_attacker_relative: formula,
        fresh_blue_frames: o.fresh_blue_frames, blue_stop: o.blue_stop,
        distance: o.horizontal_separation_raw == null ? null : o.horizontal_separation_raw / 65536,
        nearby_events: events.filter(e => at >= 0 && e.clock.replay_frame >= o.guard_end && e.clock.replay_frame <= contextEnd)
          .map(e => ({ frame: e.clock.replay_frame, side: e.side, hp_loss: e.hp_loss,
          new_flags: e.flag_onsets, damage_source_observed: e.damage_source_observed })),
        punish_verdict: null, reach_verified: false });
    }
  }
  return { schema: 'sf6cc.cfn-native-review.experimental.v1', replay_id: capture.metadata.replay_id,
    capture_stop_reason: capture.stop_reason, sample_count: capture.sample_count, observations,
    limits: ['Global sign basis is not universally verified; retain raw signs, do not assign all values to P1.',
      'No observed numeric change does not prove stale data: a new contact may have the same value.',
      'Keep only final guard-episode values for screening, not intermediate multihit values.',
      'Changed opponent action, invulnerability, reach and actual contact must be reviewed separately.',
      'Observed startup is first fresh active cell after an uninterrupted 1x action progression, not a move database.',
      'Nearby outcomes are within30 frames, not proof of causal attack ownership or missed punish.',
      'No game control or deployed detector change is performed by this report.'] };
}

export function nativeReviewMarkdown(report) {
  const lines = ['# 原生硬直差离线复核', '', `录像：${report.replay_id}；记录：${report.sample_count}条。`, '',
    '本报告重新检查三局普通防御交互。负值是保存的原生读数，不自动认定固定属于1P。',
    '按最终读数筛选，不把多段攻击中间出现的负帧直接算作机会。未观察到数值刷新不等于一定是旧值。',
    '计时条件：对手硬直差 + 攻击发生帧 + 出手延迟 ≤ 0。距离、无敌、取消与归属仍需核对。', '',
    '| 局 | 防御方 | 防御起点→结束观察点 | 最终原生值 | 攻击开始→首次判定 | 后续事件 | 核对事项 |',
    '|---:|---|---|---:|---|---|---|'];
  const flagNames = { hit: '命中', guard: '防御', counter: '普通康', punish: '确反康' };
  for (const o of report.observations.filter(o => o.selection === 'negative_value_review')) {
    const r = o.response, notes = [];
    if (o.native.opponent_action_changes_after_update.length) notes.push('读数出现后对手已换动作');
    if (o.guard_exit_result !== 'state_exit_candidate') notes.push('可行动起点未确认');
    if (o.fresh_blue_frames.length) notes.push(`新蓝格${o.fresh_blue_frames.length}帧（辅助证据）`);
    if (o.timing_if_native_is_attacker_relative) notes.push(`若该值为攻击方帧差，计时和=${o.timing_if_native_is_attacker_relative.sum}`);
    const events = o.nearby_events.map(e => `${e.frame}：${e.side}P${e.hp_loss ? `掉血${e.hp_loss}` : '未掉血'}，新增${e.new_flags.map(n => flagNames[n]).join('/') || '无标记'}`);
    lines.push(`| ${o.round} | ${o.defender}P | ${o.guard_start}→${o.guard_end ?? '未知'} | ${o.native.final_value} | ${r.attack_frame ?? '未见'}→${r.first_active_frame ?? '未见'} | ${events.join('；') || '30帧范围未见记录事件'} | ${notes.join('；') || '需核对归属、距离和恢复'} |`);
  }
  lines.push('', '## 所有防御交互', '', '| 局 | 防御方 | 起点→结束 | 最终原生值 | 本段数值变化 |', '|---:|---|---|---:|---|');
  for (const o of report.observations) lines.push(`| ${o.round} | ${o.defender}P | ${o.guard_start}→${o.guard_end ?? '未知'} | ${o.native.final_value ?? '未知'} | ${o.native.changes.map(c => `${c.frame}:${c.value}`).join('，') || '未观察到刷新，不能直接判定归属'} |`);
  lines.push('', '没有出手不自动判为漏确反；没有命中不能直接断言挥空原因。当前游戏候选列表未修改。', '');
  return lines.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, output, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error('Usage: node native_review.mjs capture.json output-base');
  const report = inspectNativeReview(JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, '')));
  writeFileSync(output + '.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  writeFileSync(output + '.md', nativeReviewMarkdown(report), { flag: 'wx' });
  console.log(JSON.stringify({ observations: report.observations.length,
    negative_value_reviews: report.observations.filter(o => o.selection === 'negative_value_review').length }));
}
