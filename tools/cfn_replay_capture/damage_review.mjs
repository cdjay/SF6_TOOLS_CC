import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { inspectEvents } from './events.mjs';

const contextFields = ['vital_new', 'focus_new', 'mSuperGauge', 'act_st', 'action_id',
  'action_frame_raw', 'hit_st', 'guard_time', 'damage_time', 'hit_stop', 'x_raw', 'y_raw',
  'facing_right', 'pl_input_new', 'pl_sw_new', 'mComboCount', 'combo_cnt', 'mComboDamage'];
const clockFields = ['round', 'battle_round', 'replay_frame', 'stage_frame'];
const flagNames = { hit: '命中', guard: '防御', counter: '普通康', punish: '确反康' };

// Counter-linked groups are review candidates, not verified causal combo identities.
export function inspectDamageReview(capture) {
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const get = (r, n) => r?.[ix[n]];
  const optional = (r, n) => Number.isSafeInteger(get(r, n)) ? get(r, n) : null;
  const key = r => clockFields.map(n => get(r, n)).join(':');
  const keyOf = c => clockFields.map(n => c[n]).join(':');
  const snapshot = r => ({ frame: get(r, 'replay_frame'),
    native_advantage_unattributed: optional(r, 'display_stun_frame'),
    players: [1, 2].map(s => Object.fromEntries(contextFields.map(n => [n, optional(r, `p${s}.${n}`)]))) });
  const counter = (r, s) => {
    const n = optional(r, `p${s}.mComboCount`), engine = optional(r, `p${s}.combo_cnt`);
    const damage = optional(r, `p${s}.mComboDamage`);
    return n != null && n >= 0 && n === engine && damage != null && damage >= 0 ? { n, damage } : null;
  };
  const held = (r,s,source) => optional(r,`p${s}.act_st`)===38 && optional(r,`p${source}.act_st`)===37
    && optional(r,`p${s}.damage_source`)===source;
  const entries = [], groups = [], rounds = [];
  for (const round of [...new Set(capture.samples.map(r => get(r, 'round')))].sort((a, b) => a - b)) {
    const evidence = inspectEvents(capture, round);
    const eventMap = new Map();
    for (const e of evidence.events.filter(e => e.hp_loss > 0)) {
      const k = keyOf(e.clock);
      if (!eventMap.has(k)) eventMap.set(k, []);
      eventMap.get(k).push(e);
    }
    let prev = null, history = [], active = new Map();
    for (const row of capture.samples) {
      if (get(row, 'round') !== round || get(row, 'battle_round') !== round) {
        prev = null; history = []; active.clear(); continue;
      }
      if (prev && key(prev) === key(row)) continue;
      const continuous = prev && ['replay_frame', 'stage_frame'].every(n => get(row, n) === get(prev, n) + 1)
        && get(row, 'fight_st') === get(prev, 'fight_st');
      if (!continuous) { history = []; active.clear(); }
      const losses = eventMap.get(key(row)) ?? [];
      const matchedSources = new Set();
      for (const e of losses) {
        const source = e.damage_source_observed;
        const validSource = [1, 2].includes(source) && source !== e.side;
        const before = continuous && validSource ? counter(prev, source) : null;
        const now = validSource ? counter(row, source) : null;
        const heldPair=validSource && held(prev,e.side,source) && held(row,e.side,source);
        const matchesLoss = amount => amount === e.hp_loss || (e.hp_after === 0 && e.hp_loss === e.hp_before && amount > e.hp_loss)
          || (e.hp_after===1 && heldPair && amount>e.hp_loss);
        // Guard damage may carry into the next native total; KO may clip actual HP loss.
        const carried = before && now && matchesLoss(now.damage - before.damage);
        const first = before && now && before.n === 0 && now.n === 1 && (matchesLoss(now.damage) || carried);
        const next = before && now && now.n === before.n + 1 && carried;
        const terminal=before && now && heldPair && e.hp_before===1 && e.hp_after===0
          && now.n===before.n && now.damage===before.damage
          && [e.side,source].every(s=>get(prev,`p${s}.action_id`)===get(row,`p${s}.action_id`))
          && active.get(source) && now.damage>active.get(source).damage;
        let group = next || terminal ? active.get(source) : null;
        if (group && (group.receiver !== e.side || group.last_native_count !== before.n)) group = null;
        if (!group) {
          group = { id: groups.length + 1, round: round + 1, receiver: e.side,
            source_observed: source, first_observed_frame: e.clock.replay_frame,
            first_hit_candidate: !!first, grouping: first ? 'native_counter_candidate' : 'unresolved',
            damage: 0, entry_ids: [], last_native_count: now?.n ?? null,
            cause: null, missed_followup: null, attack_owner_verified: false };
          groups.push(group);
          if (first) active.set(source, group);
          else if (validSource) active.delete(source);
        }
        if (group.grouping === 'native_counter_candidate') matchedSources.add(source);
        const entry = { id: entries.length + 1, group_id: group.id, round: round + 1,
          frame: e.clock.replay_frame, receiver: e.side, hp_loss: e.hp_loss,
          hp_before: e.hp_before, hp_after: e.hp_after, source_observed: source,
          new_flags: e.flag_onsets, retained_flags_not_a_verdict: e.flags_present,
          native_counter_before: before, native_counter_at_damage: now,
          context_before: history.map(snapshot), at_damage: snapshot(row),
          ko_damage_clipped: e.hp_after === 0 && now != null && before != null
            && (next ? now.damage - before.damage : now.damage) > e.hp_loss,
          cause: null, followup_opportunity: null };
        entries.push(entry);
        group.entry_ids.push(entry.id); group.damage += e.hp_loss;
        group.last_frame = e.clock.replay_frame; group.last_native_count = now?.n ?? null;
      }
      // A reset, mismatch, missing sample or unaccounted counter advance breaks linking.
      for (const [s,group] of active) {
        if (matchedSources.has(s)) continue;
        const a = counter(prev, s), b = counter(row, s);
        const victim=group.receiver;
        const countOnly=continuous && a && b && b.n===a.n+1 && b.damage===a.damage && group.last_native_count===a.n
          && get(prev,`p${victim}.vital_new`)===get(row,`p${victim}.vital_new`) && get(row,`p${victim}.vital_new`)>0
          && [32,38].includes(get(prev,`p${victim}.act_st`)) && [32,38].includes(get(row,`p${victim}.act_st`))
          && get(row,`p${victim}.damage_source`)===s;
        if(countOnly){group.last_native_count=b.n;group.count_only_contacts=(group.count_only_contacts??0)+1;}
        else if (!continuous || !a || !b || b.n === 0 || a.n !== b.n || a.damage !== b.damage) active.delete(s);
      }
      history.push(row);
      if (history.length > 30) history.shift();
      prev = row;
    }
    const selected = entries.filter(e => e.round === round + 1);
    const totals = { p1: 0, p2: 0 };
    for (const e of selected) totals[`p${e.receiver}`] += e.hp_loss;
    if (selected.length !== evidence.counts.hp_loss_observations
      || [1, 2].some(s => totals[`p${s}`] !== evidence.counts.hp_loss_by_player[`p${s}`])) {
      throw new Error('Damage coverage mismatch');
    }
    rounds.push({ round: round + 1, damage_observations: selected.length, hp_loss_by_player: totals,
      boundaries: evidence.boundaries, excluded_transition_samples: evidence.counts.excluded_transition_samples });
  }
  return { schema: 'sf6cc.cfn-damage-review.experimental.v1', replay_id: capture.metadata.replay_id,
    build: capture.metadata.version, capture_stop_reason: capture.stop_reason,
    damage_threshold: null, full_replay_verified: false, rounds, groups, entries,
    limits: ['Every observed positive HP delta is retained, including chip or unclassified damage.',
      'Native counter candidates require matching counters, continuous clocks and matching damage increments.',
      'Counter grouping is not proof of attack ownership, first contact or a completed combo.',
      'Damage amount alone does not identify throws, parry mistakes, anti-airs or player skill.',
      'Retained flags, current actions and raw advantage signs are not causal verdicts.',
      'Unobserved loss across gaps is not reconstructed; no runtime or navigation changes.'] };
}

export function damageReviewMarkdown(report) {
  const lines = ['# 全部受伤复核', '', `录像：${report.replay_id}`, '',
    '不设伤害门槛。每次已观察到的掉血均保留，不把小伤害排除。',
    '按连击计数关联的分组只是候选；未确定原因不等于没有原因，也不等于玩家失误。',
    '伤害次数不等于命中次数；削血、投技或持续伤害尚需核对。', '',
    '| 局 | 掉血变化次数 | 1P受伤 | 2P受伤 |', '|---:|---:|---:|---:|'];
  for (const r of report.rounds) lines.push(`| ${r.round} | ${r.damage_observations} | ${r.hp_loss_by_player.p1} | ${r.hp_loss_by_player.p2} |`);
  lines.push('', '## 复核分组', '', '| 编号 | 局 | 受伤方 | 首次观察→末次伤害 | 合计伤害 | 掉血次数 | 分组依据 |',
    '|---:|---:|---|---|---:|---:|---|');
  for (const g of report.groups) lines.push(`| ${g.id} | ${g.round} | ${g.receiver}P | ${g.first_observed_frame}→${g.last_frame} | ${g.damage} | ${g.entry_ids.length} | ${g.first_hit_candidate ? '连击计数关联，首击待核对' : '归属未确定，单独保留'} |`);
  lines.push('', '## 全部伤害明细', '', '| 编号 | 分组 | 局 | 帧 | 受伤方 | 伤害 | 本帧新增标记 | 原因 |',
    '|---:|---:|---:|---:|---|---:|---|---|');
  for (const e of report.entries) lines.push(`| ${e.id} | ${e.group_id} | ${e.round} | ${e.frame} | ${e.receiver}P | ${e.hp_loss} | ${e.new_flags.map(n => flagNames[n]).join('、') || '无新增'} | 待核对 |`);
  lines.push('', '每项的受伤前最多30帧状态及当帧状态保存在同名JSON中，不跨缺帧、局数或流程变化拼接。',
    '是否可确认绿冲或接后续，需要另查招式取消条件、资源、距离和实际时机；不凭低伤害判断水平。', '');
  return lines.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, output, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error('Usage: node damage_review.mjs capture.json output-base');
  const report = inspectDamageReview(JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, '')));
  writeFileSync(output + '.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  writeFileSync(output + '.md', damageReviewMarkdown(report), { flag: 'wx' });
  console.log(JSON.stringify({ observations: report.entries.length, review_groups: report.groups.length, rounds: report.rounds }));
}
