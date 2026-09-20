(function(root){
'use strict';
const C=root.CFN_RULE_CATALOG,M=root.CFNRuleModel;
const numeric=v=>typeof v==='number'&&Number.isFinite(v)&&Math.abs(v)<=Number.MAX_SAFE_INTEGER;
const integer=v=>numeric(v)&&Number.isInteger(v)&&v>=0;
const equal=(a,b)=>JSON.stringify(stable(a))===JSON.stringify(stable(b));
function stable(v){if(Array.isArray(v))return v.map(stable);if(v&&typeof v==='object')return Object.fromEntries(Object.keys(v).sort().map(k=>[k,stable(v[k])]));return v;}
function direction(mask,facing){
 if(!integer(mask)||![0,1].includes(facing)||(mask&12)===12||(mask&3)===3)return null;
 return {back:!!(mask&(facing===1?4:8)),forward:!!(mask&(facing===1?8:4)),down:!!(mask&2)};
}
function normalizeConfig(value){
 const v=M.clone(value);
 if(v&&v.rules&&!Array.isArray(v.rules)&&Object.keys(v.rules).length===0)v.rules=[];
 const error=M.validate(v);if(error)throw new Error(error);return v;
}
function parse(document){
 const bundle=document?.schema==='sf6cc.replay-workbench.v1';
 const capture=bundle?document.capture:document;
 if(!capture||capture.schema!==C.capture_schema||capture.metadata?.version!==C.build||typeof capture.metadata.replay_id!=='string'||!capture.metadata.replay_id)
  throw new Error('录像格式或游戏版本不匹配');
 if(!equal(capture.columns,C.columns))throw new Error('录像字段不完整或顺序不一致');
 if(!Array.isArray(capture.samples)||!capture.samples.length||capture.samples.length>120000)throw new Error('录像需要1至120000帧记录');
 const index=Object.fromEntries(C.columns.map((k,i)=>[k,i])),rounds=new Map();let prior=null;
 const get=(r,k)=>r?.[index[k]];
 const continuous=(a,b)=>!!a&&!!b&&get(a,'round')===get(b,'round')&&get(a,'battle_round')===get(b,'battle_round')&&get(a,'fight_st')===get(b,'fight_st')&&get(a,'replay_frame')+1===get(b,'replay_frame')&&get(a,'stage_frame')+1===get(b,'stage_frame');
 for(const row of capture.samples){
  if(!Array.isArray(row)||row.length!==C.columns.length||row.some(v=>v!==false&&!numeric(v)))throw new Error('录像中有无效读数');
  for(const k of ['round','battle_round','replay_frame','stage_frame'])if(!integer(get(row,k)))throw new Error('录像帧编号不正确');
  const round=get(row,'round'),frame=get(row,'replay_frame');
  if(get(row,'battle_round')!==round)continue;
  if(prior&&(round<get(prior,'round')||round===get(prior,'round')&&(frame<get(prior,'replay_frame')||get(row,'stage_frame')<get(prior,'stage_frame'))))throw new Error('记录存在倒放，不能合并到同一时间线');
  if(!rounds.has(round))rounds.set(round,{round,rows:new Map(),frames:[],history:[[],[]]});
  const r=rounds.get(round),old=r.rows.get(frame);
  if(old){
   const ignored=new Set(['render_tick','thread_id','update_result','fight_st']);
   if(C.columns.some((k,i)=>!ignored.has(k)&&old[i]!==row[i]))throw new Error('同一帧存在冲突记录');
  }else r.frames.push(frame);
  r.rows.set(frame,row);prior=row;
 }
 if(!rounds.size)throw new Error('没有同局的有效帧记录');
 for(const r of rounds.values()){
  let before;
  for(const frame of r.frames){const row=r.rows.get(frame);for(let side=1;side<=2;side++){
   const mask=get(row,`p${side}.pl_input_new`),list=r.history[side-1],last=list.at(-1);
   if(!integer(mask))continue;
   if(last&&last.end===frame-1&&last.mask===mask&&continuous(before,row))last.end=frame;
   else list.push({start:frame,end:frame,mask});
  }before=row;}
  r.first=r.frames[0];r.last=r.frames.at(-1);
 }
 const config=bundle?normalizeConfig(document.config):null;
 const events=bundle?(Array.isArray(document.events)?document.events:document.events&&Object.keys(document.events).length===0?[]:null):[];
 if(!events||events.length>240000)throw new Error('事件列表不正确');
 const ids=new Set();
 for(const e of events){
  if(!e||typeof e.id!=='string'||ids.has(e.id)||!['damage','guard'].includes(e.kind)||![1,2].includes(e.side)||!rounds.get(e.round)?.rows.has(e.frame)||!e.context||typeof e.context!=='object')throw new Error('事件与时间线不一致');
  if(e.context.kind!==e.kind||e.context.frame!==e.frame||e.context.side!==e.side||e.context.round!==e.round+1)throw new Error('事件证据与位置不一致');
  for(const [key,value]of Object.entries(e.context)){const f=M.fields.get(key);if(!f||(f.type==='number'&&!numeric(value))||(f.type==='boolean'&&typeof value!=='boolean')||(f.type==='enum'&&!f.options.some(o=>o[0]===value)))throw new Error('事件条件数据无效');}
  ids.add(e.id);
 }
 function facts(round,frame,side){
  const r=rounds.get(round),row=r?.rows.get(frame);if(!row)return {};
  const candidate=r.rows.get(frame-1),before=continuous(candidate,row)?candidate:null;
  const result={frame,round:round+1,side};
  for(const [who,p]of [['self',side],['other',3-side]]){
   const player=capture.metadata.players?.[p-1]??{};
   if(numeric(player.playing_fighter_id??player.fighter_id))result[who+'.fighter_id']=player.playing_fighter_id??player.fighter_id;
   if([0,1].includes(player.control_mode))result[who+'.control_mode']=player.control_mode;
   for(const [time,sampleRow]of [['current',row],['previous',before]]){
    if(!sampleRow)continue;const prefix=who+'.'+time+'.';
    for(const key of C.columns){if(key.startsWith(`p${p}.`)&&numeric(get(sampleRow,key)))result[prefix+key.slice(3)]=get(sampleRow,key);}
    for(const [key,v,max]of [['health_pct','vital_new','vital_max'],['drive_pct','focus_new','focus_max'],['super_pct','mSuperGauge','mSuperGaugeMax']]){
     const value=result[prefix+v],limit=result[prefix+max];if(numeric(value)&&numeric(limit)&&limit>0&&value>=0&&value<=limit)result[prefix+key]=value/limit*100;
    }
    const d=direction(result[prefix+'pl_input_new'],result[prefix+'facing_right']);if(d)for(const [k,v]of Object.entries(d))result[prefix+k]=v;
   }
  }
  for(const [time,r]of [['current',row],['previous',before]])if(r)for(const k of C.columns)if(!k.includes('.')&&numeric(get(r,k)))result['clock.'+time+'.'+k]=get(r,k);
  if(numeric(result['self.current.x_raw'])&&numeric(result['other.current.x_raw']))result.distance=Math.abs(result['self.current.x_raw']-result['other.current.x_raw'])/65536;
  return result;
 }
 function history(round,frame,side,limit=20){
  if(!rounds.get(round)?.rows.has(frame))return [];
  const list=rounds.get(round).history[side-1];let lo=0,hi=list.length;
  while(lo<hi){const mid=(lo+hi)>>1;if(list[mid].start<=frame)lo=mid+1;else hi=mid;}
  return list.slice(Math.max(0,lo-limit),lo).reverse().map(r=>({...r,end:Math.min(r.end,frame)}));
 }
 return {capture,config,events,rounds,index,get,continuous,facts,history,bundle,generation:document.generation??0};
}
function trace(node,ctx){
 const result=M.matches(node,ctx);
 if(node.all||node.any||node.not)return {result,mode:node.all?'all':node.any?'any':'not',children:(node.all||node.any||[node.not]).map(n=>trace(n,ctx))};
 return {result,field:node.field,op:node.op,value:node.value,value_field:node.value_field,actual:ctx[node.field],expected:node.value_field?ctx[node.value_field]:node.value};
}
root.CFNTimeline={parse,direction,equal,trace,normalizeConfig};
if(typeof module!=='undefined')module.exports=root.CFNTimeline;
})(globalThis);
