import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { classifyDamageStart, inspectDamageCauses } from './damage_causes.mjs';

const bundled = join(process.env.LOCALAPPDATA || '', 'Programs', 'Lua', 'bin', 'lua.exe');
const lua = process.env.LUA_EXE || (existsSync(bundled) ? bundled : 'lua');
test('runtime classification matches offline rules across state, flag, direction and context evidence', () => {
  const cases = [];
  for (const previous_state of [0, 8, 9, 10, 27, 28, 29, 30, 31, 32, 35, 38, 39]) {
    for (const new_flags of [[], ['guard'], ['counter'], ['punish']]) {
      for (const variant of [
        {}, { source_observed: 0 }, { current_state: 27, counter_at_damage: 0 },
        { current_state: 38, other_state: 37 }, { previous_y: 65536, other_y: 65536 },
        { previous_y: 65536 }, { guard_end: 95 }, { wakeup_last_frame: 96 },
        { attack_start_observed: true, fresh_active_frames: [90], last_meter_type: 8 },
        { attack_start_observed: true, fresh_active_frames: [90], last_meter_type: 8, contact_observed_during_attack: true },
        { reaction_preceded_by_guard: true, reaction_start: 80 },
        { facing_changed: true, other_y: 65536 },
        { previous_direction: { back: false }, current_direction: { back: false } },
        { previous_direction: { back: true, down: true }, other_y: 65536 },
        { previous_direction: { forward: true } },
      ]) cases.push({ frame: 100, receiver: 1, source_observed: 2, previous_state,
        current_state: 32, other_state: 29, new_flags, previous_y: 0, other_y: 0,
        counter_at_damage: 1, fresh_active_frames: [], ...variant });
    }
  }
  const result = spawnSync(lua, ['tools/test_cfn_damage_review.lua', '--rules-json'], {
    input: JSON.stringify(cases), encoding: 'utf8', maxBuffer: 4 * 1024 * 1024,
  });
  assert.equal(result.status, 0, result.stderr || result.error?.message);
  assert.deepEqual(JSON.parse(result.stdout), cases.map(f => {
    const { rule, level } = classifyDamageStart(f);
    return { rule, level };
  }));
});

test('runtime damage grouping matches offline totals, guard carry, KO clipping, resets and gaps', () => {
  const fields = ['vital_new','focus_new','mSuperGauge','action_id','action_frame_raw','x_raw','y_raw','z_raw',
    'facing_right','hit_st','pl_input_new','pl_sw_new','damage_source','hit_stop','act_st','damage_type',
    'guard_time','damage_time','mComboCount','combo_cnt','mComboDamage'];
  const columns = ['round','battle_round','replay_frame','stage_frame','thread_id','fight_st',
    ...[1,2].flatMap(s => fields.map(f => `p${s}.${f}`))];
  const make = (frame, hp, count, damage, guard = false) => columns.map(n => ({
    replay_frame: frame, stage_frame: frame, thread_id: 1, fight_st: 2,
    'p1.vital_new': hp, 'p2.vital_new': 10000, 'p1.damage_source': 2,
    'p2.mComboCount': count, 'p2.combo_cnt': count, 'p2.mComboDamage': damage,
    'p1.act_st': guard ? 27 : 32, 'p1.hit_st': guard ? 4 : 0,
  })[n] ?? 0);
  for (const samples of [
    [make(191,1000,0,0),make(192,900,0,100,true),make(193,700,1,300),make(194,0,2,1100)],
    [make(191,1000,0,0),make(192,700,1,300),make(193,700,0,0),make(194,500,1,200)],
    [make(191,1000,0,0),make(193,700,1,300),make(194,500,2,500)],
    [make(191,1000,0,0),make(192,900,0,100,true),make(193,850,0,150,true)],
  ]) {
    const capture = {schema:'sf6cc.cfn-state-capture.experimental.v1',state:'stopped',columns,samples,
      sample_count:samples.length,metadata:{version:20004000,replay_id:'TEST',players:[{fighter_id:1,control_mode:0},{fighter_id:2,control_mode:0}]}};
    const reference = inspectDamageCauses(capture);
    const result = spawnSync(lua, ['tools/test_cfn_damage_review.lua','--json'], {
      input: JSON.stringify(capture),encoding:'utf8',maxBuffer:4*1024*1024,
    });
    assert.equal(result.status,0,result.stderr);
    const actual = JSON.parse(result.stdout);
    assert.equal(actual.error,undefined);
    assert.equal(actual.observations,reference.damage_observations);
    assert.deepEqual(actual.items.map(i => [i.round+1,i.frame,i.receiver,i.damage,i.damage_observations,i.classification.rule,i.review_frame]),
      reference.items.map(i => [i.round,i.first_damage_frame,i.receiver,i.damage,i.damage_observations,i.classification.rule,i.locate.frame]));
  }
});
