import test from 'node:test';import assert from 'node:assert/strict';
import {createRequire} from 'node:module';import {spawnSync} from 'node:child_process';import {readFileSync} from 'node:fs';
const require=createRequire(import.meta.url);require('./rule_editor/catalog.js');const M=require('./rule_editor/model.js');
const lua=process.env.LUA_EXE||'C:/Users/76025/AppData/Local/Programs/Lua/bin/lua.exe';
function document(condition){const d=M.clone(M.catalog.defaults);d.rules=[{id:'sample',title:'待核对',enabled:true,scope:'damage',priority:'P3',when:condition}];return d;}
test('generated catalog matches runtime authority',()=>{const r=spawnSync(process.execPath,['tools/cfn_replay_capture/build_rule_editor.mjs','--check'],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);});
test('JavaScript and Lua share condition validation and three-valued matching',()=>{
 const requests=[];
 for(const [field,values]of [['damage',[undefined,0,4,1000,9007199254740000]],['punish',[undefined,true,false]],['base_rule',[undefined,'attack_counter','guard_damage']]]){
  for(const value of values)for(const op of ['exists','missing','eq','ne',...(field==='damage'?['gt','ge','lt','le','between','bits_any','bits_all']:[])]){
   const c={field,op};if(!['exists','missing'].includes(op))c.value=op==='between'?[4,1000]:field==='damage'?4:field==='punish'?true:'attack_counter';
   for(const condition of [c,{not:c},{all:[c,{field:'frame',op:'ge',value:0}]},{any:[c,{field:'frame',op:'missing'}]}])requests.push({document:document(condition),context:value===undefined?{}:{[field]:value}});
  }
 }
 const invalid=[{field:'unknown',op:'eq',value:1},{field:'punish',op:'gt',value:1},{all:[]},{field:'damage',op:'between',value:[8,2]}];
 for(const context of [{damage:1000},{damage:1000,frame:999},{damage:1000,frame:1000},{damage:1000,frame:false}])requests.push({document:document({field:'damage',op:'gt',value_field:'frame'}),context});
 invalid.push({field:'damage',op:'ge',value:2,value_field:'frame'},{field:'damage',op:'between',value_field:'frame'});
 invalid.forEach(c=>requests.push({document:document(c),context:{}}));
 const p0=document({field:'damage',op:'ge',value:1});p0.rules[0].priority='P0';requests.push({document:p0,context:{}});
 for(const mode of [false,true,'false',0,null]){const d=document({field:'damage',op:'ge',value:1});d.include_system=mode;requests.push({document:d,context:{damage:1}});}
 const run=spawnSync(lua,['tools/test_cfn_rule_config.lua','--json'],{input:JSON.stringify(requests),encoding:'utf8',maxBuffer:4e6});assert.equal(run.status,0,run.stderr);
 const actual=JSON.parse(run.stdout);
 requests.forEach((r,i)=>{const valid=M.validate(r.document)===null;assert.equal(actual[i].valid,valid,JSON.stringify(r));if(valid)assert.deepEqual(actual[i].result,M.matches(r.document.rules[0].when,r.context)??'unknown',JSON.stringify(r));});
 assert.ok(requests.length>300);
});
test('first match, disabled rules and independent guard scope',()=>{const d=document({field:'damage',op:'ge',value:1});d.rules.push({...M.clone(d.rules[0]),id:'second'});assert.equal(M.match(d,'damage',{damage:2}).id,'sample');d.rules[0].enabled=false;assert.equal(M.match(d,'damage',{damage:2}).id,'second');assert.equal(M.match(d,'guard',{damage:2}),null);});
test('new IDs stay unique and the offline editor has no external scripts',()=>{const d=M.clone(M.catalog.defaults);for(let i=0;i<100;i++)d.rules.push(M.makeRule(d));assert.equal(new Set(d.rules.map(r=>r.id)).size,100);assert.equal(M.validate(d),null);const html=readFileSync(new URL('./rule_editor/index.html',import.meta.url),'utf8');assert.ok(!/https?:\/\//.test(html));});
