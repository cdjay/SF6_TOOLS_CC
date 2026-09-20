import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { summarize } from './analyze.mjs';

// Current-build HIT_ST constants read from the game, not character Action mappings.
// Evidence and limitations: docs/research/CFN_REPLAY_CAPTURE.md.
const BUILD = 20004000;
const masks = { hit: 0x8000, guard: 0x4, counter: 0x80, punish: 0x100 };
const keyFields = ['round', 'replay_frame', 'battle_round', 'stage_frame'];
const playerFields = ['vital_new', 'hit_st', 'damage_source', 'action_id',
  'action_frame_raw', 'x_raw', 'y_raw', 'hit_stop', 'act_st', 'damage_type'];

export function inspectEvents(capture, round = 0) {
  const integrity = summarize(capture);
  if (capture.metadata.version !== BUILD) throw new Error('Unverified HIT_ST build');
  if (!Number.isInteger(round) || round < 0) throw new Error('Invalid round');
  if (integrity.conflicting_clocks) throw new Error('Conflicting states at the same clock');
  const index = Object.fromEntries(capture.columns.map((n, i) => [n, i]));
  const required = ['fight_st', ...[1, 2].flatMap(s => playerFields.map(n => `p${s}.${n}`))];
  if (required.some(n => index[n] === undefined)) throw new Error('Missing event columns');
  const get = (row, name) => row[index[name]];
  const flags = value => Object.fromEntries(Object.entries(masks).map(([n, mask]) => [n, !!(value & mask)]));
  const snapshot = (row, side) => Object.fromEntries(playerFields.map(n => [n, get(row, `p${side}.${n}`)]));
  const clock = row => Object.fromEntries(keyFields.map(n => [n, get(row, n)]));
  const events = [], actions = [], boundaries = [], baseline = [];
  const seen = new Set();
  let previous = null, segment = 0, first = null, last = null;
  const counts = { unique_samples: 0, duplicate_samples: 0, excluded_transition_samples: 0,
    hp_loss_observations: 0, hp_loss_by_player: { p1: 0, p2: 0 },
    flag_onsets: { hit: 0, guard: 0, counter: 0, punish: 0 } };
  for (const row of capture.samples) {
    if (get(row, 'round') !== round || get(row, 'battle_round') !== round) {
      if (get(row, 'round') === round || get(row, 'battle_round') === round) counts.excluded_transition_samples++;
      previous = null;
      continue;
    }
    if (required.some(n => get(row, n) === false)) throw new Error('Missing event value');
    const key = keyFields.map(n => get(row, n)).join(':');
    if (previous && keyFields.every(n => get(previous, n) === get(row, n))) {
      counts.duplicate_samples++;
      continue;
    }
    // Do not mix replay passes or bridge gaps when deriving a per-frame HP delta.
    if (seen.has(key)) throw new Error('Repeated nonconsecutive clock; separate replay passes first');
    seen.add(key);
    const contiguous = previous && ['replay_frame', 'stage_frame'].every(n => get(row, n) === get(previous, n) + 1);
    if (!contiguous) {
      segment++;
      boundaries.push({ segment, clock: clock(row), reason: previous ? 'clock_gap_or_reset' : 'interval_start' });
      for (const side of [1, 2]) baseline.push({ segment, side, clock: clock(row), flags_present: flags(get(row, `p${side}.hit_st`)) });
    }
    counts.unique_samples++;
    first ??= clock(row);
    last = clock(row);
    if (contiguous) for (const side of [1, 2]) {
      const p = `p${side}.`, before = get(previous, p + 'hit_st') >>> 0, after = get(row, p + 'hit_st') >>> 0;
      const onset = Object.keys(masks).filter(n => (after & masks[n]) && !(before & masks[n]));
      const hpLoss = Math.max(0, get(previous, p + 'vital_new') - get(row, p + 'vital_new'));
      const oldAction = get(previous, p + 'action_id'), newAction = get(row, p + 'action_id');
      const progressBack = get(row, p + 'action_frame_raw') < get(previous, p + 'action_frame_raw');
      if (oldAction !== newAction || progressBack) actions.push({ segment, clock: clock(row), side,
        previous_action_id: oldAction, action_id: newAction,
        kind: oldAction !== newAction ? 'action_id_changed' : 'action_progress_decreased',
        actionable: null });
      if (!hpLoss && !onset.length) continue;
      if (hpLoss) counts.hp_loss_observations++;
      counts.hp_loss_by_player[`p${side}`] += hpLoss;
      for (const name of onset) counts.flag_onsets[name]++;
      events.push({ segment, clock: clock(row), side, hp_before: get(previous, p + 'vital_new'),
        hp_after: get(row, p + 'vital_new'), hp_loss: hpLoss, flag_onsets: onset,
        flags_present: flags(after), hit_st_raw: after, damage_source_observed: get(row, p + 'damage_source'),
        players: [snapshot(row, 1), snapshot(row, 2)],
        horizontal_separation_raw: Math.abs(get(row, 'p1.x_raw') - get(row, 'p2.x_raw')),
        attack_owner_verified: false, outcome: null, punish_opportunity: null });
    }
    previous = row;
  }
  return { schema: 'sf6cc.cfn-event-evidence.experimental.v1', replay_id: capture.metadata.replay_id,
    version: capture.metadata.version, round, first, last, counts, boundaries, baseline,
    capture_integrity: integrity, events, action_observations: actions,
    actionable_times_available: false, full_round_verified: false,
    limitations: ['Flag onsets are observations, not a complete contact count.',
      'HP loss can be chip, throw, persistent damage or another cause; it is not a hit verdict.',
      'A retained counter/punish/guard flag does not classify later HP loss.',
      'Current Action IDs and damage source do not prove attack ownership.',
      'Position separation is not hitbox reach. No move names or punish verdicts are inferred.',
      'Action changes and display_atk_margin are not verified actionable timestamps.'] };
}

const names = { hit: '命中标记', guard: '防御标记', counter: '普通康标记', punish: '惩罚康标记' };
export function eventMarkdown(report) {
  const n = report.counts;
  const lines = [`# 第${report.round + 1}局事件观察`, '',
    `录像：${report.replay_id}；局数：${report.round + 1}。`, '',
    '这是保存数据的观察清单，不是招式判定或漏确反结论。帧号使用采集记录中的录像计数。', '',
    `- 独立时点：${n.unique_samples}；相同重复记录：${n.duplicate_samples}。`,
    `- 掉血变化：${n.hp_loss_observations}次；1P累计减少${n.hp_loss_by_player.p1}，2P累计减少${n.hp_loss_by_player.p2}。`,
    `- 防御标记新出现：${n.flag_onsets.guard}次；普通康：${n.flag_onsets.counter}次；惩罚康：${n.flag_onsets.punish}次。`,
    '- 标记可能持续，次数不能当作全部命中、防御或康的准确次数。掉血也可能来自削血、投技或持续伤害。',
    '- 当前记录不能确定双方恢复行动的精确时点，也没有验证招式能否够到，因此不判定漏确反。', '',
    '| 录像帧 | 玩家 | 血量变化 | 本帧新出现的标记 |', '|---:|---|---|---|'];
  for (const e of report.events) lines.push(`| ${e.clock.replay_frame} | ${e.side}P | ${e.hp_loss ? `${e.hp_before} → ${e.hp_after}（减少${e.hp_loss}）` : '未减少'} | ${e.flag_onsets.map(n => names[n]).join('、') || '无新增'} |`);
  lines.push('', '已有标记不会在这里逐帧重复列出；有标记但没掉血，不自动认定为普通命中。', '');
  return lines.join('\n');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [input, outputBase, ...extra] = process.argv.slice(2);
  if (!input || !outputBase || extra.length) throw new Error('Usage: node events.mjs capture.json output-base');
  const capture = JSON.parse(readFileSync(input, 'utf8').replace(/^\uFEFF/, ''));
  const report = inspectEvents(capture);
  writeFileSync(outputBase + '.json', JSON.stringify(report, null, 2) + '\n', { flag: 'wx' });
  writeFileSync(outputBase + '.md', eventMarkdown(report), { flag: 'wx' });
  process.stdout.write(JSON.stringify({ counts: report.counts, first: report.first, last: report.last }, null, 2) + '\n');
}
