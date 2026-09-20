import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { inspectDamageReview } from './damage_review.mjs';
import { states } from './recovery.mjs';
import { meterCell } from './meter_evidence.mjs';
import { nearbyGuardEvidence } from './native_review.mjs';

const attacks = new Set([states.ATCK, states.SPECIAL, states.SUPER]);
const guards = new Set([states.DEF, states.JDEF]);
const reaction = new Set([states.DAMAGE, states.HOLD]);
const movement = new Set([states.WALK, states.DUCK_WALK, states.DASH]);

// CFN native input constants, not the training RawInputCodec's direction encoding.
export function relativeDirection(mask, facing) {
  if (!Number.isSafeInteger(mask) || mask < 0 || ![0, 1].includes(facing)) return null;
  if ((mask & 12) === 12 || (mask & 3) === 3) return null;
  const back = !!(mask & (facing === 1 ? 4 : 8));
  const forward = !!(mask & (facing === 1 ? 8 : 4));
  return { back, forward, down: !!(mask & 2), up: !!(mask & 1) };
}

function evidenceAt(rows, at, ix, entry, meterProfile) {
  const get = (r, n) => r?.[ix[n]];
  const p = (r, s, n) => get(r, `p${s}.${n}`);
  const s = entry.receiver, other = 3 - s, row = rows[at], before = rows[at - 1];
  const continuous = (a, b) => a && b && ['replay_frame', 'stage_frame'].every(n => get(b, n) === get(a, n) + 1)
    && get(a, 'fight_st') === get(b, 'fight_st');
  let lower = at;
  while (lower > 0 && at - lower < 600 && continuous(rows[lower - 1], rows[lower])) lower--;
  const knownPrevious = lower < at;
  const last = knownPrevious ? before : null;
  const number = value => Number.isSafeInteger(value) ? value : null;
  const f = { frame: entry.frame, receiver: s, source_observed: entry.source_observed,
    previous_state: number(p(last, s, 'act_st')), current_state: number(p(row, s, 'act_st')),
    other_state: number(p(row, other, 'act_st')), new_flags: entry.new_flags,
    previous_y: number(p(last, s, 'y_raw')), other_y: number(p(row, other, 'y_raw')),
    previous_direction: relativeDirection(p(last, s, 'pl_input_new'), p(last, s, 'facing_right')),
    current_direction: relativeDirection(p(row, s, 'pl_input_new'), p(row, s, 'facing_right')),
    facing_changed: knownPrevious && [0, 1].includes(p(last, s, 'facing_right'))
      && [0, 1].includes(p(row, s, 'facing_right')) && p(last, s, 'facing_right') !== p(row, s, 'facing_right'),
    counter_at_damage: entry.native_counter_at_damage?.n ?? null,
    guard_end: null, wakeup_last_frame: null, reaction_start: null, reaction_preceded_by_guard: false,
    attack_start: null, attack_start_observed: false, fresh_active_frames: [],
    contact_observed_during_attack: false, last_meter_type: null, last_meter_status: 'unavailable',
    context_start: get(rows[lower], 'replay_frame'), preceding_guard_damage_frame: null };
  if (!knownPrevious) return f;
  if (meterProfile === 'native_cursor_cell_v1') {
    const cell = meterCell(rows, at - 1, ix, s);
    f.last_meter_status = cell.status;
    if (cell.status === 'advanced_cell') f.last_meter_type = cell.display_meter_type;
  }
  for (let j = Math.max(lower + 1, at - 30); j < at; j++) {
    const r = rows[j], prev = rows[j - 1];
    if (guards.has(p(prev, s, 'act_st')) && p(prev, s, 'guard_time') > 0 && !guards.has(p(r, s, 'act_st')))
      f.guard_end = get(r, 'replay_frame');
    if (p(r, s, 'act_st') === states.GETUP) f.wakeup_last_frame = get(r, 'replay_frame');
  }
  if (reaction.has(f.previous_state)) {
    let start = at - 1;
    while (start > lower && reaction.has(p(rows[start - 1], s, 'act_st'))) start--;
    if (start > lower) {
      f.reaction_start = get(rows[start], 'replay_frame');
      f.reaction_preceded_by_guard = guards.has(p(rows[start - 1], s, 'act_st'));
      if (f.reaction_preceded_by_guard) for (let j = start - 1; j > lower && start - j <= 60; j--) {
        const r = rows[j], prev = rows[j - 1];
        if (guards.has(p(r, s, 'act_st')) && p(r, s, 'vital_new') < p(prev, s, 'vital_new')) {
          f.preceding_guard_damage_frame = get(r, 'replay_frame'); break;
        }
      }
    }
  }
  if (attacks.has(f.previous_state)) {
    let start = at - 1;
    while (start > lower) {
      const a = rows[start - 1], b = rows[start];
      if (!attacks.has(p(a, s, 'act_st')) || ['action_id', 'engine_style_index', 'engine_loop_count']
        .some(n => p(a, s, n) !== p(b, s, n)) || p(b, s, 'action_frame_raw') < p(a, s, 'action_frame_raw')) break;
      start--;
    }
    f.attack_start = get(rows[start], 'replay_frame');
    f.attack_start_observed = start > lower && p(rows[start], s, 'action_frame_raw') === 0;
    for (let j = start; j < at; j++) {
      const r = rows[j], prev = rows[j - 1];
      if (meterProfile === 'native_cursor_cell_v1') {
        const cell = meterCell(rows, j, ix, s);
        if (cell.status === 'advanced_cell' && cell.display_meter_type === 13) f.fresh_active_frames.push(get(r, 'replay_frame'));
      }
      if (prev && (p(r, other, 'vital_new') < p(prev, other, 'vital_new')
        || p(r, other, 'guard_time') > 0
        || (p(r, other, 'hit_st') & ~p(prev, other, 'hit_st') & 0x8184)
        || p(r, other, 'act_st') === states.PARRY)) f.contact_observed_during_attack = true;
    }
  }
  return f;
}

function cause(rule, title, explanation, check, level = 'observed') {
  return { rule, title, explanation, check, level, mistake: null };
}

// Ordered rules consume evidence only. No character Action IDs or replay-frame exceptions.
export function classifyDamageStart(f) {
  const flags = new Set(f.new_flags);
  if (f.source_observed !== 3 - f.receiver)
    return cause('unresolved', '已确认掉血，来源尚未确定', '没有取得对手造成这次伤害的来源记录。',
      '保留伤害和状态，不把未知来源的掉血解释成对手的攻击。', 'unknown');
  if (guards.has(f.current_state) && flags.has('guard') && f.counter_at_damage === 0)
    return cause('guard_damage', '防住了，但仍然掉血', '这一下仍处于防御状态，没有计入连击。应归为防御掉血，不是一次没防住的攻击。',
      '是否应该换用其他防守方式，需要再看当时资源和招式；不能直接判成失误。');
  if (f.current_state === states.HOLD && f.other_state === states.CATCH && f.source_observed === 3 - f.receiver) {
    if (f.previous_state === states.PARRY)
      return cause('parry_caught', '蓝防后受伤（类型待确认）', '蓝防后进入固定受击演出。', '状态也可用于打击技演出，不能据此确认投技。', 'inferred');
    return cause(attacks.has(f.previous_state) ? 'attack_caught' : 'caught', attacks.has(f.previous_state) ? '出招后受伤（类型待确认）' : '受伤类型待确认',
      '双方进入固定动作中的受击演出，但这不证明攻击是投技。',
      '需要直接招式或命中属性证据，不按状态名称或伤害猜测投技。', attacks.has(f.previous_state) ? 'inferred' : 'unknown');
  }
  if (f.previous_state === states.GETUP)
    return cause('wakeup_hit', '起身时被压中', `起身动作直接转入受击${flags.has('counter') ? '，并出现普通康' : ''}，没有观察到成功防御。`,
      '检查起身防守和输入。普通康也不能单独证明成功出了某个具体招式。');
  if (f.wakeup_last_frame != null && f.frame - f.wakeup_last_frame <= 8 && attacks.has(f.previous_state) && flags.has('counter'))
    return cause('wakeup_button_counter', '起身后抢招被打断', '刚起身就进入攻击，攻击过程中被打出普通康。', '优先复盘起身抢招的时机，而不是当作一段无法防御的连招。');
  if (attacks.has(f.previous_state) && flags.has('punish')) {
    const whiff = f.attack_start_observed && f.fresh_active_frames.length > 0 && !f.contact_observed_during_attack
      && [8, 13].includes(f.last_meter_type);
    if (whiff) return cause('whiff_punish_candidate', '出招落空后被惩罚', '本次出招出现了攻击判定，但未观察到对手掉血、防御或蓝防；随后自己被打出确反康。',
      '属于挥空惩罚候选。还需招式判定或画面核对，才能排除打到分身等其他接触。', 'inferred');
    return cause('attack_punished', '出招过程中被确反康', '自己仍在出招状态，对手命中时新增了确反康标记。',
      '已确定惩罚结果；要区分挥空惩罚、被防后确反和特殊动作的可惩罚阶段，还需要接触与招式证据。');
  }
  if (attacks.has(f.previous_state) && flags.has('counter')) {
    if (f.previous_y > 0) return cause(f.other_y > 0 ? 'air_attack_counter' : 'air_ground_counter',
      f.other_y > 0 ? '空中出招被打断' : '空中出招时被地面对手打中',
      `自己处于空中攻击，对手${f.other_y > 0 ? '也在空中' : '在地面'}；本次命中是普通康。`,
      '检查空中攻击的出手时机。没有攻击物归属证据时，不把双方高度直接当作空对空或对空招式证明。');
    if (f.guard_end != null && f.frame - f.guard_end <= 15)
      return cause('guard_button_counter', '防御后抢招被打断', '防御结束后很快出招，出招期间被对手打出普通康。',
        '需要核对前一招的真实帧差和距离；不把所有防御后抢招都判成错误。');
    return cause('attack_counter', '出招被对手抢先打断', '自己仍在出招状态，对手先命中，产生普通康而不是确反康。',
      '检查双方出手时机。不能仅凭普通康认定必然可防或负帧抢招。');
  }
  if (reaction.has(f.previous_state))
    return cause(f.reaction_preceded_by_guard ? 'guard_reaction_followup' : 'reaction_followup',
      f.reaction_preceded_by_guard ? '防御后陷入受击状态，被继续追击' : '受击过程中继续掉血',
      f.reaction_preceded_by_guard ? `${f.preceding_guard_damage_frame != null ? `先在${f.preceding_guard_damage_frame}帧防住但掉血，` : ''}到${f.reaction_start}帧已从防御转入受击，当前这一下不是最初失去防守的时点。` : '掉血之前已经处于受击过程，不能把这一帧当成一次新的防守失误。',
      '应回看进入该状态之前。是否墙撞、眩晕或其他特殊效果，需要额外证据。');
  if (f.facing_changed && f.other_y > 0)
    return cause('side_change_air_hit', '换边时没有挡住空中进攻', '受击前后自身朝向发生变化，对手在空中，这一下未防住。', '重点核对过身和防御方向切换，不能只用受击后的朝向解释前一帧输入。', 'inferred');
  if (guards.has(f.previous_state) && f.current_state === states.DAMAGE) {
    if (f.previous_direction && f.current_direction && !f.previous_direction.back && !f.current_direction.back)
      return cause('guard_not_held', '防御后没有继续维持后方向', '前一刻还在防御动作，受击前后却都没有后方向输入，后续攻击打中了。',
        '重点检查松开防御的时机；状态退出和命中判定的先后仍需逐帧复核。', 'inferred');
    if (f.previous_direction?.back && f.previous_direction.down && f.other_y > 0)
      return cause('crouch_guard_air_hit', '蹲防没有挡住后续空中进攻', '受击前保持下后方向，对手在空中，本次从防御转入受击。',
        '疑似需要站防的攻击。缺少命中属性时，不直接认定是中段或防御输入错误。', 'inferred');
    return cause('guard_broken', '防御转入受击', '之前处于防御，这一下却进入受击，没有继续防住。', '还需攻击高低段、朝向和防守时机才能解释具体原因。');
  }
  if (f.previous_state === states.DASH)
    return cause('dash_intercepted', '冲刺途中被截停', '命中前仍在冲刺状态，对手的攻击先打到了。', '检查突进距离和对手牵制时机，不按伤害大小筛除。');
  if (movement.has(f.previous_state) && f.previous_direction?.forward)
    return cause('forward_walk_hit', '前走时被打中', '受击前处于移动状态，方向输入是朝对手前进，没有保持后方向。',
      '优先检查前走的时机和距离；不是仅凭1000伤害就认定为投技。', 'inferred');
  if (movement.has(f.previous_state))
    return cause('movement_hit', '移动时被打中', '命中之前仍在移动，未进入成功防御。', '还需攻击属性和输入时序区分下段、过身或其他原因。');
  if (f.previous_y > 0) return cause('air_hit', '空中被打中', '受击前位置在空中。', '还需动作归属才能区分对空、空对空或空中受击后续。');
  return cause('unresolved', '已确认掉血，原因证据不足', '当前记录不满足已有受击原因规则。',
    '需要更完整的前置状态、攻击属性或招式关联；保留这次损失，不猜测原因。', 'unknown');
}

export function inspectDamageCauses(capture, reviews = null) {
  const ledger = inspectDamageReview(capture);
  const ix = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const byRound = new Map();
  for (const row of capture.samples) {
    if (row[ix.round] !== row[ix.battle_round]) continue;
    const round = row[ix.round] + 1;
    if (!byRound.has(round)) byRound.set(round, []);
    const rows = byRound.get(round), last = rows.at(-1);
    if (last && row[ix.replay_frame] === last[ix.replay_frame] && row[ix.stage_frame] === last[ix.stage_frame]) {
      if (row[ix.fight_st] === last[ix.fight_st]) continue;
      // Retain flow transitions as context barriers, including the KO frame.
    }
    rows.push(row);
  }
  if (reviews && (reviews.replay_id !== capture.metadata.replay_id || reviews.build !== capture.metadata.version
    || JSON.stringify(reviews.players.map(p => [p.fighter_id, p.control_mode]))
      !== JSON.stringify(capture.metadata.players.map(p => [p.fighter_id, p.control_mode])))) throw new Error('Review identity mismatch');
  const appliedReviews = new Set();
  const items = ledger.groups.map(group => {
    const entry = ledger.entries[group.entry_ids[0] - 1], rows = byRound.get(group.round);
    const at = rows.findIndex(r => r[ix.replay_frame] === entry.frame);
    const facts = evidenceAt(rows, at, ix, entry, capture.metadata.frame_meter_profile);
    const classification = classifyDamageStart(facts);
    const review = reviews?.items.find(r => r.round === group.round && r.frame === entry.frame && r.receiver === group.receiver);
    if (review) {
      if (review.first_damage !== entry.hp_loss || review.source !== 'user_verified') throw new Error('Review evidence mismatch');
      appliedReviews.add(review);
    }
    const native = nearbyGuardEvidence(rows, ix, at);
    const rewindFrame = native?.frame ?? facts.preceding_guard_damage_frame ?? facts.reaction_start ?? facts.attack_start ?? entry.frame;
    const earliest = rows[0][ix.replay_frame];
    // Fall back to the observed setup itself, never subtract a global round offset.
    // Navigation must still verify the live round and its actual lower boundary.
    const target = Math.min(entry.frame, Math.max(earliest,
      Math.min(rewindFrame, review?.review_from ?? Infinity)));
    return { id: group.id, round: group.round, first_damage_frame: entry.frame, last_damage_frame: group.last_frame,
      receiver: group.receiver, damage: group.damage, damage_observations: group.entry_ids.length,
      entry_ids: group.entry_ids, grouping: group.grouping, first_hit_candidate: group.first_hit_candidate,
      classification, human_review: review ?? null, facts, native_advantage: native,
      locate: { replay_id: ledger.replay_id, build: ledger.build, round: group.round - 1, frame: target,
        basis_frame: rewindFrame, lead_frames: 0, requires_bounds_check: true },
      followup: { status: 'not_evaluated', required: ['move_cancel_routes', 'resources', 'range', 'timing'] } };
  });
  if (reviews && appliedReviews.size !== reviews.items.length) throw new Error('Some review anchors were not found');
  const accounted = items.flatMap(i => i.entry_ids);
  if (new Set(accounted).size !== ledger.entries.length || accounted.length !== ledger.entries.length)
    throw new Error('Cause coverage mismatch');
  return { schema: 'sf6cc.cfn-damage-causes.experimental.v1', rules_version: 1, replay_id: ledger.replay_id,
    build: ledger.build, capture_stop_reason: ledger.capture_stop_reason, full_replay_verified: false,
    players: reviews?.players ?? capture.metadata.players.map((p, i) => ({ fighter_id: p.fighter_id, control_mode: p.control_mode, label: `${i + 1}P` })),
    damage_observations: ledger.entries.length, rounds: ledger.rounds, items,
    rules_summary: Object.fromEntries([...new Set(items.map(i => i.classification.rule))].map(rule =>
      [rule, items.filter(i => i.classification.rule === rule).length])),
    automatic_unknown: items.filter(i => i.classification.level === 'unknown').length,
    human_review_count: appliedReviews.size };
}

export function damageCausesMarkdown(report) {
  const name = side => `${report.players[side - 1].label}（${side}P）`;
  const lines = ['# 这场录像为什么掉血', '',
    `录像 ${report.replay_id}。全部${report.damage_observations}次掉血归入${report.items.length}段复盘，不设伤害门槛。`,
    '连招后续归回起点，不重复当成新的失误；防住却掉血也单独保留。以下伤害为实际掉血，最后一下不多算超出剩余血量的伤害。',
    '“状态已确认”说明过程有直接记录，不代表已证明所有深层原因。“规则推定”仍需核对；你的实测结论明确标为“你已确认”。',
    `其中${report.human_review_count}段带有你的实测确认。其余为自动过程分类，不等于已经查明每次失误的全部原因。`, '', '## 自动分类概览', ''];
  const category = new Map();
  for (const item of report.items) {
    const title = item.classification.title;
    const x = category.get(title) ?? { count: 0, damage: 0 };
    x.count++; x.damage += item.damage; category.set(title, x);
  }
  for (const [title, x] of category) lines.push(`- ${title}：${x.count}段，合计${x.damage}伤害。`);
  lines.push('', '## 逐段解释');
  for (const round of report.rounds) {
    lines.push('', `### 第${round.round}局`, '');
    for (const item of report.items.filter(i => i.round === round.round)) {
      const c = item.human_review ?? item.classification;
      const level = item.human_review ? '你已确认' : ({ observed: '状态已确认', inferred: '规则推定', unknown: '待查' })[c.level];
      lines.push(`#### ${item.first_damage_frame}帧：${name(item.receiver)}，${c.title}`, '',
        `**损失${item.damage}血。${level}。** ${c.explanation}`,
        item.damage_observations > 1 ? `后续一直记录到${item.last_damage_frame}帧，共${item.damage_observations}次掉血，合并复盘。` : '这里只记录到一次掉血。',
        `复盘重点：${c.check}`,
        `建议从第${item.round}局${item.locate.frame}帧开始看。`, '');
    }
  }
  lines.push('## 暂时不能直接下的结论', '',
    '- 单次轻攻击没有后续，不自动等于确认失败；需要先证明当时可取消、有资源且打得到。',
    '- 出招被普通康，不自动等于负帧乱动；出招被确反康，也不自动等于防御后确反。',
    '- 抓取状态不能区分普通投和当身反制，伤害大小也不能证明蓝防失误。',
    '- 不把本场人工验证的帧号写进通用规则；程序判断和人工结论在结果中分别保存。',
    '- 定位目标已输出为同局帧号，但本轮没有修改游戏面板或发送任何控制按键。', '');
  return lines.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, output, reviewsPath, ...extra] = process.argv.slice(2);
  if (!input || !output || extra.length) throw new Error('Usage: node damage_causes.mjs capture.json output-base [reviews.json]');
  const read = path => JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
  const report = inspectDamageCauses(read(input), reviewsPath ? read(reviewsPath) : null);
  writeFileSync(output + '.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  writeFileSync(output + '.md', damageCausesMarkdown(report), { flag: 'wx' });
  console.log(JSON.stringify({ observations: report.damage_observations, items: report.items.length,
    rules: report.rules_summary, unknown: report.automatic_unknown, reviewed: report.human_review_count }));
}
