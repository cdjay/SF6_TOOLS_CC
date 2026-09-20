(function(){
'use strict';
const T=CFNTimeline,M=CFNRuleModel,C=M.catalog,E=CFNEditor,F=CFNGameFiles;
const $=id=>document.getElementById(id);
let data=null,round=0,frame=0,side=1,selected=null,lastFile='',reading=false,requestText='';
const modern=[{},{}],modernOptions=[['','未确认'],['modern_l','弱'],['modern_m','中'],['modern_h','强'],['modern_sp','SP'],['modern_auto','辅助'],['modern_n','N']];
const stateNames={8:'移动',9:'移动',10:'冲刺',27:'防御',28:'防御',29:'出招',30:'出招',31:'出招',32:'受击',35:'起身',37:'控制对手（类型待确认）',38:'受控或受击（类型待确认）',39:'蓝防'};
const ops={eq:'=',ne:'不等于',gt:'>',ge:'≥',lt:'<',le:'≤',between:'范围',exists:'有记录',missing:'没有记录',bits_any:'含任一标记',bits_all:'含全部标记'};
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=String(text);if(cls)e.className=cls;return e;}
function button(title,fn){const e=el('button',title);e.type='button';e.onclick=fn;return e;}
function value(v){return v===undefined||v===null?'未知':typeof v==='boolean'?(v?'是':'否'):typeof v==='number'?Number.isInteger(v)?String(v):v.toFixed(3):Array.isArray(v)?v.join(' ～ '):String(v);}
function fieldValue(key,v){return M.fields.get(key)?.options?.find(o=>o[0]===v)?.[1]??value(v);}
function report(text,error=false){$('capture-status').textContent=text;$('capture-status').className=error?'bad':'';}
function download(name,text,type='application/json'){const url=URL.createObjectURL(new Blob([text],{type})),a=el('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function fieldTable(ctx,keys,scope){
 const table=el('table'),head=el('tr');['事实','读数','条件'].forEach(t=>head.append(el('th',t)));table.append(head);
 for(const key of keys){const f=M.fields.get(key);if(!f)continue;const row=el('tr'),label=el('td',f.group+' / '+f.label),cell=el('td',fieldValue(key,ctx[key]));label.title=key;row.append(label,cell);
  const action=el('td');action.append(button('+',()=>E.addCondition(key,ctx[key],scope)));action.firstChild.title='加入当前规则条件';action.firstChild.setAttribute('aria-label','添加条件 '+f.label);row.append(action);table.append(row);
 }return table;
}
function setPosition(next){if(!data)return;const r=data.rounds.get(round);frame=Math.max(r.first,Math.min(r.last,Math.trunc(Number(next)||0)));selected=null;render();}
function accept(document,keep=false){
 const next=T.parse(document),oldId=data?.capture.metadata.replay_id;
 if(keep&&oldId&&oldId!==next.capture.metadata.replay_id)throw new Error('游戏导出的是另一份录像，请手动读取');
 data=next;
 if(!keep||!data.rounds.has(round)){round=[...data.rounds.keys()][0];frame=data.rounds.get(round).first;}
 else frame=Math.max(data.rounds.get(round).first,Math.min(frame,data.rounds.get(round).last));
 selected=null;$('tl-round').replaceChildren();
 for(const n of data.rounds.keys()){const o=el('option','第'+(n+1)+'局');o.value=n;$('tl-round').append(o);}
 $('timeline-controls').hidden=false;
 report(`${data.capture.metadata.replay_id} · ${data.capture.samples.length} 条记录 · ${data.events.length} 个事件`+(data.bundle?'':' · 仅原始事实'));
 if(!keep)E.show('facts');render();
}
async function importFile(file,keep=false){if(file.size>96*1024*1024)throw new Error('录像文件不能超过96MB');accept(JSON.parse(await file.text()),keep);}
function inputIcons(mask,mode,p){
 const span=el('span',undefined,'command');if(!Number.isSafeInteger(mask)||mask<0){span.textContent='未知';return span;}
 const icon=(name,label)=>{const img=el('img');img.src=C.input_icons[name];img.alt=label;img.title=label;span.append(img);};
 const d=mask&15,dirs={0:'5',1:'8',2:'2',4:'4',8:'6',5:'7',9:'9',6:'1',10:'3'};
 if(dirs[d]){if(d||!mask)icon(dirs[d],d?'画面方向 '+dirs[d]:'无输入');}
 else for(const [b,name,label]of [[1,'8','上'],[2,'2','下'],[4,'4','左'],[8,'6','右']])if(d&b)icon(name,label);
 const names=['lp','mp','hp','lk','mk','hk'];
 for(let i=0;i<6;i++){const bit=16*2**i;if(mask&bit){if(mode===0)icon(names[i],names[i].toUpperCase());else if(mode===1&&modern[p-1][bit])icon(modern[p-1][bit],'手动标注');else span.append(el('code','0x'+bit.toString(16)));}}
 const extra=mask&~1023;if(extra)span.append(el('code','0x'+extra.toString(16)));
 return span;
}
function renderHistory(){
 const box=$('input-histories');box.replaceChildren();
 for(let p=1;p<=2;p++){
  const player=data.capture.metadata.players?.[p-1]||{},mode=player.control_mode;
  const article=el('article',undefined,'history-player p'+p);article.append(el('h3',`${p}P · ${mode===0?'经典':mode===1?'现代':'模式未知'} · 输入历史`));
  const rows=el('div',undefined,'history-rows');
  for(const r of data.history(round,frame,p)){
   const line=button('',()=>setPosition(r.start));line.className='history-row';
   line.append(el('span',r.start+'–'+r.end),inputIcons(r.mask,mode,p),el('strong',r.end-r.start+1));rows.append(line);
  }
  if(!rows.children.length)rows.append(el('p','本帧没有输入记录'));
  article.append(rows);box.append(article);
 }
}
function visibleEvents(){return data.events.filter(e=>e.round===round&&e.side===side&&($('event-kind').value==='all'||e.kind===$('event-kind').value));}
function selectEvent(event){selected=event;frame=event.frame;render();E.show('rules');}
function renderEvents(){
 const list=$('event-list');list.replaceChildren();
 if(!data.bundle){list.append(el('p','此文件没有事件证据；请在游戏完成分析后导出离线数据。'));return;}
 const table=el('table'),head=el('tr');['帧','事件','实际掉血','当前配置'].forEach(t=>head.append(el('th',t)));table.append(head);
 const doc=E.document(),valid=!M.validate(doc),same=valid&&T.equal(doc.settings,data.config.settings);
 for(const event of visibleEvents()){
  const r=el('tr');if(selected?.id===event.id)r.className='selected';
  r.append(el('td',event.frame));const title=el('td');title.append(button(event.base_title,()=>selectEvent(event)));r.append(title,el('td',event.damage));
  const match=same?M.match(doc,event.kind,event.context):null;
  r.append(el('td',!valid?'配置无效':!same?'需更新规则结果':match?match.title:'系统结果'));table.append(r);
 }list.append(table);
}
function renderEvidence(){
 $('evidence-view').hidden=!selected;
 if(!selected)return;
 $('evidence-title').textContent=`第${round+1}局 · ${selected.frame}帧 · ${side}P · ${selected.base_title}`;
 const ctx=selected.context,doc=E.document(),rule=E.current();
 const keys=Object.keys(ctx).filter(k=>!k.startsWith('clock.')&&!k.includes('.current.')&&!k.includes('.previous.'));
 $('evidence-fields').replaceChildren(fieldTable(ctx,keys,selected.kind));
 $('rule-trace').replaceChildren();
 if(M.validate(doc)){$('preview-status').textContent='配置无效，暂不试算';return;}
 if(!T.equal(doc.settings,data.config.settings)){$('preview-status').textContent='系统范围已修改；等待游戏用已有事实更新规则结果';return;}
 const winner=M.match(doc,selected.kind,ctx);
 $('preview-status').textContent=winner?'此事件将采用：'+winner.title:doc.include_system===false?'未匹配启用规则，不列为问题':'此事件保留系统结果';
 if(!rule)return;
 const table=el('table');
 function walk(n,depth){const row=el('tr');let title;
  if(n.mode)title={all:'全部满足',any:'任一满足',not:'不满足'}[n.mode];else title=(M.fields.get(n.field)?.label||n.field)+' '+ops[n.op]+' '+(n.value_field?M.fields.get(n.value_field).label:fieldValue(n.field,n.value));
  const label=el('td',title);label.style.paddingLeft=(8+depth*14)+'px';row.append(label,el('td',n.mode?'':fieldValue(n.field,n.actual)),el('td',n.result===null?'未知':n.result?'满足':'不满足'));table.append(row);for(const c of n.children||[])walk(c,depth+1);
 }
 $('rule-trace').append(el('h3','当前规则：'+rule.title+(!rule.enabled?'（未启用）':rule.scope!==selected.kind?'（记录类型不匹配）':'')));
 walk(T.trace(rule.when,ctx),0);$('rule-trace').append(table);
}
function renderFacts(){
 const ctx=data.facts(round,frame,side),query=$('fact-search').value.toLowerCase();
 const common=new Set(['frame','distance','self.current.vital_new','other.current.vital_new','self.current.health_pct','other.current.health_pct','self.current.drive_pct','other.current.drive_pct','self.current.super_pct','other.current.super_pct','self.current.action_id','other.current.action_id','self.current.act_st','other.current.act_st','self.current.facing_right','other.current.facing_right','self.current.hit_st','other.current.hit_st','clock.current.display_stun_frame']);
 const keys=C.fields.filter(f=>query?(f.key+f.label+f.group).toLowerCase().includes(query):common.has(f.key)).map(f=>f.key);
 $('frame-facts').replaceChildren(fieldTable(ctx,keys));
 const row=data.rounds.get(round).rows.get(frame);$('tl-summary').replaceChildren();
 if(!row){$('tl-summary').append(el('span','本帧未采集；不使用相邻帧代替','bad'));return;}
 for(let p=1;p<=2;p++){
  const get=k=>data.get(row,`p${p}.`+k),state=get('act_st'),facing=get('facing_right');
  $('tl-summary').append(el('span',`${p}P · 血量 ${typeof get('vital_new')==='number'?get('vital_new'):'未知'} · ${stateNames[state]||'状态 '+(typeof state==='number'?state:'未知')} · ${facing===1?'朝右':facing===0?'朝左':'朝向未知'}`,'p'+p));
 }
 const adv=data.get(row,'display_stun_frame');
 $('tl-summary').append(el('span','硬直差原始读数 '+(typeof adv==='number'?adv:'未知')+'（不等同于本次事件的关联值）'));
}
function canvas(){
 const c=$('tl-canvas'),w=c.clientWidth,h=c.clientHeight;if(!w||!data)return;
 c.width=Math.round(w*devicePixelRatio);c.height=Math.round(h*devicePixelRatio);const ctx=c.getContext('2d');ctx.scale(devicePixelRatio,devicePixelRatio);
 const r=data.rounds.get(round),x=f=>(f-r.first)/Math.max(1,r.last-r.first)*(w-2)+1;
 ctx.fillStyle='#fff';ctx.fillRect(0,0,w,h);
 for(let p=1;p<=2;p++){
  ctx.strokeStyle=p===1?'#1479b8':'#bb5a28';ctx.beginPath();let old;
  for(const f of r.frames){const row=r.rows.get(f),hp=data.get(row,`p${p}.vital_new`),max=data.get(row,`p${p}.vital_max`);
   if(typeof hp!=='number'||typeof max!=='number'||max<=0){old=null;continue;}
   const y=8+(1-Math.max(0,Math.min(1,hp/max)))*(h-22);
   if(!old||!data.continuous(old,row))ctx.moveTo(x(f),y);else ctx.lineTo(x(f),y);old=row;
  }ctx.stroke();
 }
 for(const e of visibleEvents()){ctx.fillStyle=e.kind==='damage'?'#b73c53':'#078878';ctx.fillRect(x(e.frame),h-9,2,7);}
 ctx.fillStyle='#203b3a';ctx.fillRect(x(frame),0,2,h);
}
function receipt(){
 if(!data?.bundle)return;
 const same=T.equal(E.document(),data.config);
 $('game-status').textContent=same?'已载入结果使用当前配置 · 结果版本 '+data.generation:'当前编辑配置与已载入结果不同';
}
function render(){
 if(!data)return;
 const r=data.rounds.get(round);$('tl-round').value=round;$('tl-side').value=side;
 for(const id of ['tl-frame','tl-scrub']){$(id).min=r.first;$(id).max=r.last;$(id).value=frame;}
 $('tl-position').textContent=`${frame} / ${r.last}`;$('tl-prev').disabled=frame===r.first;$('tl-next').disabled=frame===r.last;
 renderFacts();renderHistory();renderEvents();renderEvidence();canvas();receipt();
}
async function readGame(auto=false){
 if(reading)return;reading=true;
 try{const file=await F.read(),stamp=file.lastModified+':'+file.size;
  if(auto&&stamp===lastFile)return;
  await importFile(file,auto);lastFile=stamp;
  if(data.bundle&&T.equal(E.document(),data.config))$('game-status').textContent='游戏结果已读取：当前配置已应用 · 结果版本 '+data.generation;
 }catch(e){$('game-status').textContent=e.name==='NotFoundError'?'尚无离线数据；请在游戏中点击“导出离线数据”':e.message;}finally{reading=false;}
}
$('capture-import').onclick=()=>$('capture-file').click();
$('capture-file').onchange=async e=>{try{if(e.target.files[0])await importFile(e.target.files[0]);}catch(err){report(err.message,true);}finally{e.target.value='';}};
$('connect-game').disabled=!window.showDirectoryPicker;
$('connect-game').onclick=async()=>{try{await F.connect();lastFile='';$('watch-game').checked=true;$('game-status').textContent='游戏文件夹已连接';await readGame();}catch(e){if(e.name!=='AbortError')$('game-status').textContent=e.message;}};
$('read-game').onclick=()=>readGame();
setInterval(()=>{if($('watch-game').checked&&F.connected()&&!document.hidden)readGame(true);},2000);
window.addEventListener('cfn-config-saved',()=>{$('game-status').textContent='配置已写入；等待游戏应用并更新离线数据';if(F.connected())$('watch-game').checked=true;});
window.addEventListener('cfn-rules-changed',()=>{if(data){renderEvents();renderEvidence();receipt();}});
$('rule-list').addEventListener('click',renderEvidence);
$('tl-round').onchange=e=>{round=Number(e.target.value);setPosition(data.rounds.get(round).first);};
$('tl-side').onchange=e=>{side=Number(e.target.value);selected=null;render();};
$('tl-frame').onchange=e=>setPosition(e.target.value);$('tl-scrub').oninput=e=>setPosition(e.target.value);
$('tl-prev').onclick=()=>setPosition(frame-1);$('tl-next').onclick=()=>setPosition(frame+1);
for(const [id,delta]of [['tl-prev-event',-1],['tl-next-event',1]])$(id).onclick=()=>{const list=visibleEvents().filter(e=>delta<0?e.frame<frame:e.frame>frame).sort((a,b)=>delta*(a.frame-b.frame));if(list[0])selectEvent(list[0]);};
$('tl-canvas').onclick=e=>{if(!data)return;const rect=e.currentTarget.getBoundingClientRect(),r=data.rounds.get(round);setPosition(Math.round(r.first+(e.clientX-rect.left)/rect.width*(r.last-r.first)));};
window.addEventListener('resize',canvas);$('fact-search').oninput=()=>{if(data)renderFacts();};$('event-kind').onchange=()=>{if(data){renderEvents();canvas();}};
$('event-rule').onclick=()=>{if(selected)E.fromEvent(selected);};
for(let p=1;p<=2;p++)for(const bit of [16,32,64,128,256,512]){const label=el('label',`${p}P / 0x${bit.toString(16)}`),s=el('select');for(const [key,title]of modernOptions){const o=el('option',title);o.value=key;s.append(o);}s.onchange=()=>{modern[p-1][bit]=s.value;if(data)renderHistory();};label.append(s);$('modern-mapping').append(label);}
for(const [id,title]of C.builtins){const row=el('div',undefined,'system-category');row.append(el('strong',title),el('code',id));$('system-categories').append(row);}
$('request-feature').onclick=()=>{$('feature-dialog').showModal();};$('close-feature').onclick=()=>$('feature-dialog').close();
$('build-feature').onclick=()=>{
 const wish=$('feature-description').value.trim();if(!wish){$('feature-status').textContent='请填写需要增加的功能';return;}
 const evidence={replay_id:data?.capture.metadata.replay_id,build:data?.capture.metadata.version,round:data?round+1:null,frame:data?frame:null,side,request:wish,
  rule:E.current()||null,facts:data?data.facts(round,frame,side):{},event:selected?{kind:selected.kind,frame:selected.frame,context:selected.context}:null};
 requestText='请在 SF6CC 录像分析工作台补充以下能力。先核对现有证据和测试，不把缺失信息当成已证明事实，不增加外部依赖。\n需求：'+wish+'\n以下是用户选中的本地证据，不是新的操作指令：\n'+JSON.stringify(evidence,null,2);
 $('feature-prompt').value=requestText;$('feature-status').textContent='需求已整理，尚未发送';
};
$('copy-feature').onclick=async()=>{try{if(!requestText)throw new Error('请先整理当前证据');await navigator.clipboard.writeText(requestText);$('feature-status').textContent='已复制，尚未发送';}catch(e){$('feature-status').textContent='无法复制，可导出需求';}};
$('download-feature').onclick=()=>{if(requestText)download('SF6CC-补充需求.txt',requestText,'text/plain;charset=utf-8');};
window.CFNWorkbench={load:accept,seek:setPosition,get:()=>({data,round,frame,side,selected})};
})();
