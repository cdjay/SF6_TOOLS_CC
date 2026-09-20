import test from 'node:test';
import assert from 'node:assert/strict';
import { inspectDamageReview, damageReviewMarkdown } from './damage_review.mjs';

function fixture(count = 8) {
  const fields = ['vital_new', 'focus_new', 'mSuperGauge', 'action_id', 'action_frame_raw',
    'x_raw', 'y_raw', 'z_raw', 'facing_right', 'hit_st', 'pl_input_new', 'pl_sw_new',
    'damage_source', 'hit_stop', 'act_st', 'damage_type', 'mComboCount', 'combo_cnt', 'mComboDamage'];
  const columns = ['round', 'replay_frame', 'battle_round', 'stage_frame', 'thread_id', 'fight_st',
    ...[1, 2].flatMap(s => fields.map(n => `p${s}.${n}`))];
  return { schema: 'sf6cc.cfn-state-capture.experimental.v1', state: 'stopped', stop_reason: 'manual',
    metadata: { replay_id: 'TEST', version: 20004000, players: [
      { fighter_id: 21, control_mode: 1 }, { fighter_id: 32, control_mode: 0 }] },
    columns, sample_count: count, samples: Array.from({ length: count }, (_, i) => columns.map(n =>
      ['replay_frame', 'stage_frame'].includes(n) ? i + 191 : n.endsWith('.vital_new') ? 10000 : 0)) };
}
function from(c, i, n, v) { for (; i < c.samples.length; i++) c.samples[i][c.columns.indexOf(n)] = v; }
function hit(c, i, count, damage, side = 2) {
  from(c, i, `p${side}.vital_new`, 10000 - damage);
  from(c, i, `p${side}.damage_source`, 3 - side);
  for (const n of ['mComboCount', 'combo_cnt']) from(c, i, `p${3 - side}.${n}`, count);
  from(c, i, `p${3 - side}.mComboDamage`, damage);
}

test('one point and 300 damage are retained without a threshold or skill verdict', () => {
  const c = fixture(); hit(c, 1, 1, 1); hit(c, 3, 2, 301);
  const r = inspectDamageReview(c);
  assert.equal(r.damage_threshold, null);
  assert.deepEqual(r.entries.map(e => e.hp_loss), [1, 300]);
  assert.equal(r.groups.length, 1); assert.equal(r.groups[0].damage, 301);
  assert.equal(r.groups[0].first_hit_candidate, true);
  assert.equal(r.groups[0].cause, null); assert.equal(r.groups[0].missed_followup, null);
  assert.equal(r.groups[0].attack_owner_verified, false);
});
test('retained punish flag is not relabeled as a new punish for the followup', () => {
  const c = fixture(); hit(c, 1, 1, 300); hit(c, 3, 2, 900); from(c, 1, 'p2.hit_st', 0x18100);
  const r = inspectDamageReview(c);
  assert.ok(r.entries[0].new_flags.includes('punish'));
  assert.deepEqual(r.entries[1].new_flags, []);
});
test('a reset ends a group even if the next sequence has identical damage', () => {
  const c = fixture(); hit(c, 1, 1, 300);
  from(c, 2, 'p1.combo_cnt', 0); from(c, 2, 'p1.mComboCount', 0);
  hit(c, 3, 1, 300); from(c, 3, 'p2.vital_new', 9400);
  const r = inspectDamageReview(c);
  assert.equal(r.groups.length, 2); assert.ok(r.groups.every(g => g.first_hit_candidate));
});
test('a capture starting midcombo retains loss but does not invent a first hit', () => {
  const c = fixture(); hit(c, 0, 2, 600); hit(c, 2, 3, 900);
  const r = inspectDamageReview(c);
  assert.equal(r.entries.length, 1); assert.equal(r.groups[0].first_hit_candidate, false);
});
test('counter disagreement or missing counters do not discard damage', () => {
  for (const value of [false, 8]) {
    const c = fixture(); hit(c, 1, 1, 300); from(c, 1, 'p1.combo_cnt', value);
    const r = inspectDamageReview(c);
    assert.equal(r.entries[0].hp_loss, 300); assert.equal(r.groups[0].grouping, 'unresolved');
  }
});
test('unknown sources and possible chip stay unclassified even above 1000', () => {
  const c = fixture(); from(c, 2, 'p1.vital_new', 8500); from(c, 0, 'p1.hit_st', 4);
  const r = inspectDamageReview(c);
  assert.equal(r.entries.length, 1); assert.equal(r.entries[0].cause, null);
  assert.equal(r.groups[0].first_hit_candidate, false);
});
test('KO clipping links only the final observed HP, never overkill damage', () => {
  const c = fixture(); hit(c, 1, 1, 300); hit(c, 3, 2, 10300); from(c, 3, 'p2.vital_new', 0);
  const r = inspectDamageReview(c);
  assert.equal(r.groups.length, 1); assert.equal(r.entries[1].ko_damage_clipped, true);
  assert.equal(r.rounds[0].hp_loss_by_player.p2, 10000);
});
test('non-KO damage mismatch still prevents linking', () => {
  const c = fixture(); hit(c, 1, 1, 300); hit(c, 3, 2, 900); from(c, 3, 'p2.vital_new', 9200);
  assert.equal(inspectDamageReview(c).groups.length, 2);
});
test('carried chip damage does not fragment the following native combo', () => {
  const c = fixture(); hit(c, 1, 0, 200); hit(c, 3, 1, 920); hit(c, 5, 2, 1235);
  const r = inspectDamageReview(c);
  assert.equal(r.groups.length, 2);
  assert.equal(r.groups[1].damage, 1035); assert.equal(r.groups[1].entry_ids.length, 2);
});
test('unaccounted counter advances break the link', () => {
  const c = fixture(); hit(c, 1, 1, 300);
  from(c, 2, 'p1.mComboCount', 2); from(c, 2, 'p1.combo_cnt', 2);
  hit(c, 3, 3, 600);
  assert.equal(inspectDamageReview(c).groups.length, 2);
});
test('missing frames do not invent damage or bridge context and combos', () => {
  const c = fixture(); hit(c, 1, 1, 300); hit(c, 3, 2, 600); hit(c, 5, 3, 900);
  c.samples.splice(2, 1); c.sample_count--;
  const r = inspectDamageReview(c);
  assert.deepEqual(r.entries.map(e => e.hp_loss), [300, 300]);
  assert.equal(r.groups.length, 2);
  assert.ok(r.entries[1].context_before.every(x => x.frame >= 194));
});
test('identical duplicates are ignored and conflicts rejected', () => {
  const c = fixture(); hit(c, 1, 1, 300);
  c.samples.splice(2, 0, [...c.samples[1]]); c.sample_count++;
  assert.equal(inspectDamageReview(c).entries.length, 1);
  c.samples[2][c.columns.indexOf('p2.vital_new')] = 9500;
  assert.throws(() => inspectDamageReview(c), /Conflicting/);
});
test('round transitions keep independent groups and no phantom HP delta', () => {
  const c = fixture(); hit(c, 1, 1, 300);
  from(c, 3, 'round', 1); from(c, 3, 'battle_round', 1);
  hit(c, 3, 0, 0); hit(c, 5, 1, 300);
  const r = inspectDamageReview(c);
  assert.equal(r.groups.length, 2); assert.deepEqual(r.entries.map(e => e.round), [1, 2]);
});
test('same-frame damage to both players is retained separately', () => {
  const c = fixture(); hit(c, 1, 1, 300, 1); hit(c, 1, 1, 600, 2);
  const r = inspectDamageReview(c);
  assert.equal(r.groups.length, 2);
  assert.deepEqual(r.rounds[0].hp_loss_by_player, { p1: 300, p2: 600 });
});
test('context is bounded, frame191 remains absolute, flow changes break context', () => {
  const c = fixture(60); hit(c, 40, 1, 300);
  let r = inspectDamageReview(c);
  assert.equal(r.entries[0].frame, 231); assert.equal(r.entries[0].context_before.length, 30);
  from(c, 39, 'fight_st', 7); r = inspectDamageReview(c);
  assert.equal(r.entries[0].context_before.length, 1);
});
test('report separates observation, grouping and unknown cause', () => {
  const c = fixture(); hit(c, 1, 1, 300);
  const md = damageReviewMarkdown(inspectDamageReview(c));
  assert.match(md, /不设伤害门槛/); assert.match(md, /首击待核对/); assert.match(md, /待核对/);
  assert.match(md, /不凭低伤害判断水平/);
});

function cinematic() {
  const c=fixture(6);
  from(c,0,'p2.vital_new',1000);from(c,1,'p2.vital_new',700);from(c,1,'p2.damage_source',1);
  from(c,1,'p2.act_st',32);from(c,2,'p2.act_st',38);from(c,2,'p1.act_st',37);
  for(const [at,count,damage,hp] of [[1,1,300,700],[2,2,300,700],[3,3,500,500],[4,4,1100,1],[5,4,1100,0]]) {
    from(c,at,'p1.mComboCount',count);from(c,at,'p1.combo_cnt',count);
    from(c,at,'p1.mComboDamage',damage);from(c,at,'p2.vital_new',hp);
  }
  return c;
}
test('count-only cinematic contact and delayed knockout stay in one actual-loss group',()=>{
  const r=inspectDamageReview(cinematic());assert.equal(r.groups.length,1);
  assert.equal(r.groups[0].damage,1000);assert.equal(r.groups[0].entry_ids.length,4);
  assert.equal(r.groups[0].count_only_contacts,1);assert.equal(r.groups[0].last_frame,196);
});
test('cinematic exceptions do not bridge changed sources clocks or ordinary damage mismatches',()=>{
  for(const mode of ['source','gap','reaction']) {
    const c=cinematic();
    if(mode==='source') from(c,2,'p2.damage_source',0);
    if(mode==='gap') { c.samples.splice(2,1);c.sample_count--; }
    if(mode==='reaction') from(c,2,'p2.act_st',0);
    const r=inspectDamageReview(c);assert.ok(r.groups.length>1,mode);
  }
  const c=cinematic();from(c,4,'p2.act_st',0);
  assert.ok(inspectDamageReview(c).groups.length>1);
});
