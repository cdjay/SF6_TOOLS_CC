import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
const require=createRequire(import.meta.url);require('./rule_editor/catalog.js');
const M=require('./rule_editor/model.js'),T=require('./rule_editor/timeline-model.js'),C=M.catalog;
const ix=Object.fromEntries(C.columns.map((k,i)=>[k,i]));
function row(frame,patch={}){const r=C.columns.map(()=>false);for(const [k,v]of Object.entries({round:0,battle_round:0,replay_frame:frame,stage_frame:frame,fight_st:4,
 'p1.vital_new':7000,'p1.vital_max':10000,'p1.x_raw':65536,'p2.x_raw':327680,'p1.pl_input_new':4,'p1.facing_right':1,...patch}))r[ix[k]]=v;return r;}
function capture(rows){return {schema:C.capture_schema,columns:C.columns,metadata:{version:C.build,replay_id:'TEST',players:[{fighter_id:21,control_mode:1},{fighter_id:32,control_mode:0}]},samples:rows};}
test('timeline uses captured frames including 191, gaps and round-local histories',()=>{
 const t=T.parse(capture([row(191),row(192),row(194),row(191,{round:1,battle_round:1})]));
 assert.equal(t.rounds.get(0).first,191);assert.deepEqual(t.facts(0,193,1),{});
 assert.equal(t.facts(0,194,1)['self.previous.health_pct'],undefined);
 assert.equal(t.facts(0,192,1)['self.current.health_pct'],70);
 assert.equal(t.facts(0,192,1).distance,4);
 assert.deepEqual(t.history(0,194,1),[{start:194,end:194,mask:4},{start:191,end:192,mask:4}]);
 assert.deepEqual(t.history(1,191,1),[{start:191,end:191,mask:4}]);
});
test('missing inputs break history and facing transforms only relative facts',()=>{
 const t=T.parse(capture([row(191),row(192,{'p1.pl_input_new':false}),row(193,{'p1.facing_right':0})]));
 assert.equal(t.history(0,193,1)[0].start,193);
 assert.equal(t.facts(0,193,1)['self.current.forward'],true);
 assert.equal(t.facts(0,191,1)['self.current.back'],true);
 assert.equal(T.direction(12,1),null);assert.equal(T.direction(4,false),null);
});
test('raw fact projection matches Lua including absent current samples and flow boundaries',()=>{
 const c=capture([row(191),row(192),row(194),row(195,{fight_st:5})]),t=T.parse(c);
 const items=[191,192,193,194,195].flatMap(frame=>[1,2].map(receiver=>({frame,round:0,receiver})));
 const run=spawnSync(process.env.LUA_EXE||'C:/Users/76025/AppData/Local/Programs/Lua/bin/lua.exe',['tools/test_cfn_workbench.lua','--contexts'],{input:JSON.stringify({capture:c,items}),encoding:'utf8'});
 assert.equal(run.status,0,run.stderr);const actual=JSON.parse(run.stdout);
 for(let i=0;i<items.length;i++){
  const item=items[i],a=actual[i],b=t.facts(0,item.frame,item.receiver);
  for(const k of Object.keys(a))if(k==='duration'||k==='frame'||k==='side'||k==='round'||!t.rounds.get(0).rows.has(item.frame)&&k.endsWith('fighter_id')||!t.rounds.get(0).rows.has(item.frame)&&k.endsWith('control_mode'))delete a[k];
  delete b.frame;delete b.side;delete b.round;
  assert.deepEqual(b,a,`${item.frame}/${item.receiver}`);
 }
});
test('invalid versions conflicting samples and unknown event fields are rejected',()=>{
 assert.throws(()=>T.parse(capture([row(192),row(191)])),/倒放/);
 assert.throws(()=>T.parse(capture([row(191),row(191,{'p1.vital_new':1})])),/冲突/);
 const c=capture([row(191)]);c.metadata.version=1;assert.throws(()=>T.parse(c),/版本/);
 const packet={schema:'sf6cc.replay-workbench.v1',capture:capture([row(191)]),config:M.clone(C.defaults),events:[{id:'a',kind:'damage',side:1,round:0,frame:191,context:{kind:'damage',frame:191,round:1,side:1,evil:2}}]};
 assert.throws(()=>T.parse(packet),/条件数据/);
});
test('event preview keeps first matching rule separate from unknown and disabled conditions',()=>{
 const doc=M.clone(C.defaults);doc.rules=[{id:'one',title:'检查',scope:'damage',enabled:true,priority:'P2',when:{all:[{field:'damage',op:'ge',value:100},{field:'punish',op:'eq',value:true}]}}];
 assert.equal(T.trace(doc.rules[0].when,{damage:200}).result,null);
 assert.equal(M.match(doc,'damage',{damage:200,punish:true}).id,'one');
 doc.rules[0].enabled=false;assert.equal(M.match(doc,'damage',{damage:200,punish:true}),null);
 assert.ok(T.equal({a:1,b:2},{b:2,a:1}));
});
