import test from 'node:test';
import assert from 'node:assert/strict';
import { classifyDamageStart, relativeDirection, inspectDamageCauses, damageCausesMarkdown } from './damage_causes.mjs';
import { states as S } from './recovery.mjs';

const facts = overrides => ({ frame: 100, receiver: 2, source_observed: 1,
  previous_state: S.ATCK, current_state: S.DAMAGE, other_state: S.ATCK,
  new_flags: [], previous_y: 0, other_y: 0, guard_end: null, wakeup_last_frame: null,
  previous_direction: null, current_direction: null, facing_changed: false,
  counter_at_damage: 1, fresh_active_frames: [], attack_start_observed: false,
  contact_observed_during_attack: false, last_meter_type: null, ...overrides });
const rule = overrides => classifyDamageStart(facts(overrides)).rule;

test('CFN directions are facing-aware and never use the training horizontal encoding', () => {
  assert.equal(relativeDirection(4, 1).back, true);
  assert.equal(relativeDirection(4, 0).forward, true);
  assert.equal(relativeDirection(8, 0).back, true);
  assert.equal(relativeDirection(6, 1).down, true);
  for (const [mask, facing] of [[12, 1], [3, 1], [false, 1], [8, false], [-1, 1], [8, 2]])
    assert.equal(relativeDirection(mask, facing), null);
});
test('damage during confirmed guard is not a broken defense', () => {
  assert.equal(rule({ current_state: S.DEF, new_flags: ['hit', 'guard'], counter_at_damage: 0 }), 'guard_damage');
  assert.notEqual(rule({ current_state: S.DEF, new_flags: [], counter_at_damage: 0 }), 'guard_damage');
});
test('paired cinematic states preserve prior context but never prove a throw', () => {
  assert.equal(rule({ current_state: S.HOLD, other_state: S.CATCH }), 'attack_caught');
  assert.equal(rule({ current_state: S.HOLD, other_state: S.CATCH, previous_state: S.PARRY }), 'parry_caught');
  assert.equal(rule({ current_state: S.HOLD, other_state: S.CATCH, previous_state: S.WALK }), 'caught');
  assert.notEqual(rule({ current_state: S.HOLD, other_state: S.WALK }), 'caught');
  for (const previous_state of [S.ATCK,S.PARRY,S.WALK]) {
    const c=classifyDamageStart(facts({current_state:S.HOLD,other_state:S.CATCH,previous_state}));
    assert.notEqual(c.level,'observed');assert.doesNotMatch(c.title,/抓|投技/);
  }
});
test('unknown or self damage source does not identify opponent-caused damage', () => {
  for (const source_observed of [0, -1, 2]) assert.equal(rule({ source_observed, new_flags: ['counter'] }), 'unresolved');
});
test('fresh counter and punish remain distinct from carried flags', () => {
  assert.equal(rule({ new_flags: ['counter'] }), 'attack_counter');
  assert.equal(rule({ new_flags: ['punish'] }), 'attack_punished');
  assert.equal(rule({ new_flags: [] }), 'unresolved');
});
test('whiff candidate needs complete action, observed active cells, no contact and current meter evidence', () => {
  const base = { new_flags: ['punish'], attack_start_observed: true, fresh_active_frames: [90, 91], last_meter_type: 8 };
  assert.equal(rule(base), 'whiff_punish_candidate');
  for (const change of [{ attack_start_observed: false }, { fresh_active_frames: [] },
    { contact_observed_during_attack: true }, { last_meter_type: null }])
    assert.equal(rule({ ...base, ...change }), 'attack_punished');
  assert.equal(classifyDamageStart(facts(base)).level, 'inferred');
});
test('wakeup strike, wakeup button and distant wakeup are different', () => {
  assert.equal(rule({ previous_state: S.GETUP, new_flags: ['counter'] }), 'wakeup_hit');
  assert.equal(rule({ wakeup_last_frame: 96, new_flags: ['counter'] }), 'wakeup_button_counter');
  assert.equal(rule({ wakeup_last_frame: 80, new_flags: ['counter'] }), 'attack_counter');
});
test('air attack state is not identified from damage magnitude', () => {
  assert.equal(rule({ previous_y: 65536, other_y: 65536, new_flags: ['counter'] }), 'air_attack_counter');
  assert.equal(rule({ previous_y: 65536, new_flags: ['counter'] }), 'air_ground_counter');
});
test('recent guard attack is a process category, not a minus-frame verdict', () => {
  const c = classifyDamageStart(facts({ guard_end: 95, new_flags: ['counter'] }));
  assert.equal(c.rule, 'guard_button_counter'); assert.equal(c.mistake, null);
  assert.equal(rule({ guard_end: 60, new_flags: ['counter'] }), 'attack_counter');
});
test('preexisting reactions do not become new independent defensive failures', () => {
  assert.equal(rule({ previous_state: S.DAMAGE, reaction_preceded_by_guard: true, reaction_start: 50 }), 'guard_reaction_followup');
  assert.equal(rule({ previous_state: S.HOLD }), 'reaction_followup');
});
test('side-change and crouch guard conclusions remain qualified', () => {
  assert.equal(rule({ previous_state: S.WALK, facing_changed: true, other_y: 65536 }), 'side_change_air_hit');
  const c = classifyDamageStart(facts({ previous_state: S.DEF, other_y: 65536, previous_direction: relativeDirection(6, 1) }));
  assert.equal(c.rule, 'crouch_guard_air_hit'); assert.equal(c.level, 'inferred');
  assert.match(c.check, /缺少命中属性/);
});
test('guard release requires missing back on both sides of the damage update', () => {
  const base = { previous_state: S.DEF, previous_direction: relativeDirection(0, 1), current_direction: relativeDirection(0, 1) };
  assert.equal(rule(base), 'guard_not_held');
  assert.equal(rule({ ...base, current_direction: relativeDirection(4, 1) }), 'guard_broken');
});
test('dash and forward walk are distinct from unspecified moving hit', () => {
  assert.equal(rule({ previous_state: S.DASH }), 'dash_intercepted');
  assert.equal(rule({ previous_state: S.WALK, previous_direction: relativeDirection(8, 1) }), 'forward_walk_hit');
  assert.equal(rule({ previous_state: S.WALK }), 'movement_hit');
});

function fixture() {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
    'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new',
    'damage_source', 'hit_stop', 'act_st', 'damage_type', 'mComboCount', 'combo_cnt', 'mComboDamage',
    'guard_time', 'engine_loop_count', 'engine_style_index', 'display_meter_size', 'display_meter_index',
    'display_meter_type', 'display_meter_empty', 'display_meter_changed', 'display_meter_end',
    'display_meter_not_add', 'display_meter_not_whole'];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id', 'fight_st',
    'display_prev_frame', 'meter_start_frame', ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  return { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped', stop_reason: 'left_replay',
    metadata: { replay_id: 'TEST', version: 20004000, frame_meter_profile: 'native_cursor_cell_v1', players: [
      { fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: 12, samples: Array.from({ length: 12 }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame', 'display_prev_frame'].includes(n) ? i + 191
        : n.endsWith('.vital_new') ? 10000 : n.endsWith('.display_meter_size') ? 80
          : n.endsWith('.display_meter_index') ? i : 0)) };
}
function set(c, i, n, v) { c.samples[i][c.columns.indexOf(n)] = v; }
function from(c, i, n, v) { for (; i < c.samples.length; i++) set(c, i, n, v); }
function attackAndHit(c) {
  from(c, 2, 'p2.act_st', S.ATCK); from(c, 2, 'p2.action_id', 777);
  for (let j = 2; j < 8; j++) set(c, j, 'p2.action_frame_raw', (j - 2) * 65536);
  from(c, 4, 'p2.display_meter_type', 13); from(c, 6, 'p2.display_meter_type', 8);
  from(c, 8, 'p2.act_st', S.DAMAGE); from(c, 8, 'p2.hit_st', 0x8100);
  from(c, 8, 'p2.vital_new', 9700); from(c, 8, 'p2.damage_source', 1);
  from(c, 8, 'p1.mComboCount', 1); from(c, 8, 'p1.combo_cnt', 1); from(c, 8, 'p1.mComboDamage', 300);
}
test('full pipeline links state, fresh meter cells, damage and same-round target', () => {
  const c = fixture(); attackAndHit(c); const r = inspectDamageCauses(c);
  assert.equal(r.items.length, 1); assert.equal(r.items[0].classification.rule, 'whiff_punish_candidate');
  assert.deepEqual(r.items[0].facts.fresh_active_frames, [195, 196]);
  assert.equal(r.items[0].locate.round, 0); assert.equal(r.items[0].locate.frame, 193);
  assert.equal(r.items[0].locate.lead_frames, 0);
  assert.equal(r.capture_stop_reason, 'left_replay'); assert.equal(r.full_replay_verified, false);
});
test('held or stale meter cells cannot create whiff evidence', () => {
  for (const field of ['p2.display_meter_index', 'display_prev_frame']) {
    const c = fixture(); attackAndHit(c); from(c, 1, field, 0);
    assert.equal(inspectDamageCauses(c).items[0].classification.rule, 'attack_punished');
  }
});
test('observed opponent defense prevents a false whiff label', () => {
  const c = fixture(); attackAndHit(c); set(c, 5, 'p1.guard_time', 5);
  assert.equal(inspectDamageCauses(c).items[0].classification.rule, 'attack_punished');
});
test('a clock gap cannot contribute the start of an attack', () => {
  const c = fixture(); attackAndHit(c); c.samples.splice(3, 1); c.sample_count--;
  assert.equal(inspectDamageCauses(c).items[0].classification.rule, 'attack_punished');
});
test('same-clock flow changes remain context barriers instead of discarding the KO report', () => {
  const c = fixture(); attackAndHit(c);
  const copy = [...c.samples[5]]; copy[c.columns.indexOf('fight_st')] = 1;
  c.samples.splice(6, 0, copy); c.sample_count++;
  const r = inspectDamageCauses(c);
  assert.equal(r.damage_observations, 1); assert.equal(r.items[0].facts.attack_start_observed, false);
});
test('counter reset means a new incident, not an extended combo', () => {
  const c = fixture(); attackAndHit(c);
  from(c, 9, 'p1.combo_cnt', 0); from(c, 9, 'p1.mComboCount', 0);
  from(c, 10, 'p1.combo_cnt', 1); from(c, 10, 'p1.mComboCount', 1);
  from(c, 10, 'p2.vital_new', 9400);
  assert.equal(inspectDamageCauses(c).items.length, 2);
});
test('delayed damage after guard reaction points back to the earlier contact', () => {
  const c = fixture();
  from(c, 2, 'p2.act_st', S.DEF); from(c, 3, 'p2.hit_st', 4);
  from(c, 3, 'p2.damage_source', 1); from(c, 3, 'p2.vital_new', 9800);
  from(c, 3, 'p1.mComboDamage', 200);
  from(c, 5, 'p2.act_st', S.DAMAGE);
  from(c, 8, 'p2.vital_new', 9400); from(c, 8, 'p1.mComboCount', 1);
  from(c, 8, 'p1.combo_cnt', 1); from(c, 8, 'p1.mComboDamage', 600);
  const r = inspectDamageCauses(c);
  assert.equal(r.items.length, 2);
  assert.equal(r.items[1].classification.rule, 'guard_reaction_followup');
  assert.equal(r.items[1].facts.reaction_start, 196);
  assert.equal(r.items[1].facts.preceding_guard_damage_frame, 194);
  assert.equal(r.items[1].locate.frame, 194);
});
test('human review is identity-bound and stored separately, never a classifier exception', () => {
  const c = fixture(); attackAndHit(c);
  const reviews = { replay_id: 'TEST', build: 20004000, players: c.metadata.players.map((p, i) => ({ ...p, label: `${i + 1}P` })),
    items: [{ round: 1, frame: 199, receiver: 2, first_damage: 300, source: 'user_verified',
      title: '人工核验', explanation: '实测结论', check: '检查距离', review_from: 192 }] };
  const r = inspectDamageCauses(c, reviews);
  assert.equal(r.human_review_count, 1); assert.equal(r.items[0].classification.rule, 'whiff_punish_candidate');
  assert.match(damageCausesMarkdown(r), /你已确认/);
  assert.throws(() => inspectDamageCauses(c, { ...reviews, replay_id: 'OTHER' }), /identity/);
  assert.throws(() => inspectDamageCauses(c, { ...reviews, items: [{ ...reviews.items[0], first_damage: 301 }] }), /evidence/);
  assert.throws(() => inspectDamageCauses(c, { ...reviews, items: [{ ...reviews.items[0], frame: 999 }] }), /anchors/);
});
