'use strict';
const M=CFNRuleModel,C=M.catalog,$=id=>document.getElementById(id);
let doc=M.clone(C.defaults),selected=null,tab='rules',dirty=false,sample={};
const draftKey='sf6cc-replay-rules-v1';
const ops={eq:'等于',ne:'不等于',gt:'大于',ge:'大于等于',lt:'小于',le:'小于等于',between:'范围内（含两端）',exists:'有记录',missing:'没有记录',bits_any:'包含任一标记',bits_all:'包含全部标记'};
function el(tag,text,attrs={}){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;for(const [k,v]of Object.entries(attrs)){if(k==='class')e.className=v;else e.setAttribute(k,v);}return e;}
function button(text,title,fn){const e=el('button',text,{title});e.onclick=fn;return e;}
function select(options,value,fn){const e=el('select');for(const [key,title]of options){const o=el('option',title,{value:String(key)});e.append(o);}e.value=String(value);e.onchange=()=>fn(e.value);return e;}
function input(value,fn,type='text'){const e=el('input',undefined,{type});e.value=value??'';e.onchange=()=>fn(type==='number'?(e.value===''?null:Number(e.value)):e.value);return e;}
function labelled(title,widget){const label=el('label',title);label.append(widget);return label;}
function status(message,error=false){$('status').textContent=message;$('status').className=error?'bad':'';}
function changed(redraw=true){dirty=true;try{localStorage.setItem(draftKey,JSON.stringify(doc));}catch{}status('本地草稿已修改 · 尚未保存到游戏');if(redraw)render();else validate();window.dispatchEvent(new Event('cfn-rules-changed'));}
function validate(){const error=M.validate(doc);$('validity').textContent=error||'配置检查通过';$('validity').className=error?'bad':'good';$('export').disabled=!!error;$('save-game').disabled=!!error||!window.showDirectoryPicker;return !error;}
function current(){return doc.rules.find(r=>r.id===selected);}
function freshCondition(){return {field:'damage',op:'ge',value:1000};}
function defaultValue(f){return f.type==='number'?0:f.type==='boolean'?true:f.options[0][0];}
function fieldSelect(value,onchange,numericOnly=false){
 const e=el('select',undefined,{'aria-label':'条件字段'});let last,group;
 for(const f of C.fields){if(numericOnly&&f.type!=='number')continue;if(f.group!==last){group=el('optgroup',undefined,{label:f.group});e.append(group);last=f.group;}group.append(el('option',f.group+' / '+f.label,{value:f.key}));}
 e.value=value;e.onchange=()=>onchange(e.value);return e;
}
function valueWidget(c,f,onchange){
 if(['exists','missing'].includes(c.op))return el('span','');
 if(c.op==='between'){const range=el('div',undefined,{class:'range'});for(let i=0;i<2;i++){const e=input(c.value?.[i],v=>{c.value[i]=v;onchange();},'number');e.setAttribute('aria-label',i?'上限':'下限');range.append(e);}return range;}
 if(f.type==='number')return input(c.value,v=>{c.value=v;onchange();},'number');
 const options=f.type==='boolean'?[[true,'是'],[false,'否']]:f.options;
 return select(options,c.value,v=>{c.value=options.find(o=>String(o[0])===v)[0];onchange();});
}
function compareWidget(c,f){
 if(f.type!=='number'||!['eq','ne','gt','ge','lt','le'].includes(c.op))return valueWidget(c,f,()=>changed(false));
 const wrap=el('div',undefined,{class:'compare-value'});
 wrap.append(select([['constant','数值'],['field','另一字段']],c.value_field?'field':'constant',v=>{
  if(v==='field'){delete c.value;c.value_field='other.current.vital_new';}else{delete c.value_field;c.value=0;}changed();
 }));
 wrap.append(c.value_field?fieldSelect(c.value_field,v=>{c.value_field=v;changed();},true):valueWidget(c,f,()=>changed(false)));
 return wrap;
}
function renderNode(node,parent,replace,remove,depth=1){
 if(node.all||node.any||node.not){
  const box=el('div',undefined,{class:'condition-group'}),head=el('div',undefined,{class:'group-head'});
  const mode=node.all?'all':node.any?'any':'not';
  head.append(select([['all','全部满足'],['any','任一满足'],['not','不满足']],mode,v=>{
   const children=node.all||node.any||(node.not.all||[node.not]);replace(v==='not'?{not:{all:children}}:{[v]:children});changed();
  }));
  if(mode!=='not'){
   head.append(button('＋ 条件','新增条件',()=>{(node.all||node.any).push(freshCondition());changed();}));
   if(depth<5)head.append(button('＋ 条件组','新增嵌套条件组',()=>{(node.all||node.any).push({all:[freshCondition()]});changed();}));
  }
  if(remove)head.append(button('×','删除条件组',()=>{remove();changed();}));box.append(head);
  if(node.not)renderNode(node.not,box,x=>{node.not=x;},null,depth+1);
  else (node.all||node.any).forEach((child,i)=>{const list=node.all||node.any;renderNode(child,box,x=>{list[i]=x;},()=>list.splice(i,1),depth+1);});
  parent.append(box);return;
 }
 const row=el('div',undefined,{class:'condition'}),f=M.fields.get(node.field);
 row.append(fieldSelect(node.field,key=>{node.field=key;node.op='eq';delete node.value_field;node.value=defaultValue(M.fields.get(key));changed();}));
 const options=Object.entries(ops).filter(([key])=>f.type==='number'||['eq','ne','exists','missing'].includes(key));
 row.append(select(options,node.op,v=>{node.op=v;delete node.value_field;if(['exists','missing'].includes(v))delete node.value;else node.value=v==='between'?[0,100]:defaultValue(f);changed();}));
 row.append(compareWidget(node,f));
 if(remove)row.append(button('×','删除条件',()=>{remove();changed();}));
 parent.append(row);
}
function sampleFields(node,out=new Set()){if(node.not)sampleFields(node.not,out);else if(node.all||node.any)(node.all||node.any).forEach(n=>sampleFields(n,out));else{out.add(node.field);if(node.value_field)out.add(node.value_field);}return out;}
function renderSample(r){
 const wrap=$('sample-values');wrap.replaceChildren();$('match-result').textContent='未试算';$('match-result').className='';
 for(const key of sampleFields(r.when)){
  const f=M.fields.get(key),box=el('div',undefined,{class:'sample-field'});
  const c={op:'eq',value:sample[key]??defaultValue(f)};
  const widget=valueWidget(c,f,()=>{sample[key]=c.value;});widget.disabled=!(key in sample);
  const cb=el('input',undefined,{type:'checkbox'});cb.checked=key in sample;cb.onchange=()=>{if(cb.checked)sample[key]=c.value;else delete sample[key];widget.disabled=!cb.checked;};
  box.append(labelled(f.group+' / '+f.label,widget),labelled('有记录',cb));wrap.append(box);
 }
}
function renderRule(){
 const r=current();$('empty').hidden=!!r;$('rule-detail').hidden=!r;$('sandbox').hidden=!r;if(!r)return;
 const detail=$('rule-detail');detail.replaceChildren();const head=el('div',undefined,{class:'rule-head'});
 head.append(labelled('问题描述',input(r.title,v=>{r.title=v;changed(false);renderList();})),labelled('记录类型',select([['damage','受伤段'],['guard','防御段']],r.scope,v=>{r.scope=v;delete r.opportunity;changed();})),
 labelled('问题级别',select([['P1','P1'],['P2','P2'],['P3','P3']],r.priority,v=>{r.priority=v;changed(false);renderList();})));detail.append(head);
 const actions=el('div',undefined,{class:'rule-actions'}),cb=el('input',undefined,{type:'checkbox'});cb.checked=r.enabled;cb.onchange=()=>{r.enabled=cb.checked;changed(false);renderList();};actions.append(labelled('启用规则',cb));
 const i=doc.rules.indexOf(r);
 for(const [text,title,delta]of [['↑','提高优先顺序',-1],['↓','降低优先顺序',1]]){const b=button(text,title,()=>{[doc.rules[i],doc.rules[i+delta]]=[doc.rules[i+delta],doc.rules[i]];changed();});b.disabled=i+delta<0||i+delta>=doc.rules.length;actions.append(b);}
 actions.append(button('复制','复制规则',()=>{const copy=M.clone(r);copy.id=M.makeRule(doc).id;copy.title+='（副本）';doc.rules.splice(i+1,0,copy);selected=copy.id;changed();}),button('删除','删除规则',()=>{if(confirm('删除这条自定义规则？')){doc.rules.splice(i,1);selected=doc.rules[Math.min(i,doc.rules.length-1)]?.id??null;changed();}}));detail.append(actions);
 if(r.scope==='guard')detail.append(labelled('机会列表',select([['keep','保持系统结果'],['yes','列为待核对机会'],['no','不列为机会']],r.opportunity===undefined?'keep':r.opportunity?'yes':'no',v=>{if(v==='keep')delete r.opportunity;else r.opportunity=v==='yes';changed(false);})));
 const title=el('div',undefined,{class:'section-heading'});title.append(el('h2','发生条件'),el('span',String(i+1).padStart(2,'0')+' / '+doc.rules.length));detail.append(title);
 renderNode(r.when,detail,x=>{r.when=x;});renderSample(r);
}
function renderList(){
 const list=$('rule-list');list.replaceChildren();const query=$('search').value.toLowerCase();
 doc.rules.forEach((r,i)=>{if(!r.title.toLowerCase().includes(query))return;const b=el('button',undefined,{class:'rule-item'+(selected===r.id?' active':'')+(!r.enabled?' off':'')});
 b.append(el('span',String(i+1).padStart(2,'0'),{class:'number'}),el('strong',r.title),el('small',r.enabled?r.priority:'停用'));b.onclick=()=>{selected=r.id;render();};list.append(b);});
 $('rule-count').textContent=doc.rules.length;
}
function render(){
 $('include-system').checked=doc.include_system!==false;
 $('include-system').onchange=()=>{doc.include_system=$('include-system').checked;changed();};
 $('empty').querySelector('h2').textContent=doc.include_system===false?'尚未添加问题规则':'系统规则已启用';
 $('profile-name').value=doc.name;renderList();renderRule();$('json-text').value=JSON.stringify(doc,null,2);
 $('settings').replaceChildren();for(const s of C.settings){const e=input(doc.settings[s.key],v=>{doc.settings[s.key]=v;changed(false);},'number');e.min=s.min;e.max=s.max;e.step=1;$('settings').append(labelled(s.label,e));}
 validate();
}
function add(base){const r=M.makeRule(doc,base);doc.rules.push(r);selected=r.id;tab='rules';setTab(tab);changed();}
function setTab(value){tab=value;for(const t of ['rules','settings','fields','json','facts','system'])$(t+'-view').hidden=t!==tab;document.querySelectorAll('[data-tab]').forEach(b=>b.classList.toggle('active',b.dataset.tab===tab));if(tab==='json')$('json-text').value=JSON.stringify(doc,null,2);}
function accept(next){const error=M.validate(next);if(error)throw new Error(error);doc=M.clone(next);selected=doc.rules[0]?.id??null;sample={};changed();}
function directory(){
 const query=$('field-search').value.toLowerCase(),table=el('table'),head=el('tr');for(const title of ['条件','分组','字段'])head.append(el('th',title));table.append(head);
 for(const f of C.fields.filter(f=>(f.label+f.group+f.key).toLowerCase().includes(query))){const tr=el('tr');tr.append(el('td',f.label),el('td',f.group));const cell=el('td');cell.append(el('code',f.key));tr.append(cell);table.append(tr);}$('field-directory').replaceChildren(table);
}
$('brand-icon').src=C.icon;$('build').textContent=C.build;
$('profile-name').onchange=e=>{doc.name=e.target.value;changed(false);};$('search').oninput=renderList;$('field-search').oninput=directory;
$('add').onclick=$('empty-add').onclick=()=>add();
$('templates').onclick=()=>{$('template-dialog').showModal();};$('close-templates').onclick=()=>{$('template-dialog').close();};
for(const base of C.builtins)$('template-list').append(button(base[1],'以此系统分类为条件创建自定义规则',()=>{add(base);$('template-dialog').close();}));
$('reset').onclick=()=>{if(confirm('恢复默认配置？当前自定义规则会移除。'))accept(C.defaults);};
document.querySelectorAll('[data-tab]').forEach(b=>b.onclick=()=>setTab(b.dataset.tab));
$('run-sample').onclick=()=>{if(!validate())return;const r=current(),value=M.matches(r.when,sample),winner=M.match(doc,r.scope,sample);$('match-result').textContent=value===null?'未知：条件缺少记录':value?(winner?.id===r.id?'满足：本规则命中':'满足，但被更靠前规则覆盖'):'不满足';$('match-result').className=value===true?'good':'';};
$('apply-json').onclick=()=>{try{accept(JSON.parse($('json-text').value));status('文本修改已应用 · 尚未导出');}catch(e){status(e.message,true);}};
$('import').onclick=()=>$('file-input').click();$('file-input').onchange=async e=>{const file=e.target.files[0];if(!file)return;try{if(file.size>1024*1024)throw new Error('配置不能超过1MB');const next=JSON.parse(await file.text());if(dirty&&!confirm('导入配置并替换当前草稿？'))return;accept(next);status('配置已导入 · 尚未在游戏中应用');}catch(err){status(err.message,true);}finally{e.target.value='';}};
$('export').onclick=()=>{if(!validate())return;const a=el('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(doc,null,2)],{type:'application/json;charset=utf-8'}));a.download='cfn-replay-rules.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);dirty=false;status('配置已导出 · 尚未在游戏中应用');};
$('save-game').title=window.showDirectoryPicker?'选择游戏的 reframework 文件夹':'此浏览器不能直接保存到文件夹，请使用导出配置';
$('save-game').onclick=async()=>{
 if(!validate())return;
 try{
  if(await CFNGameFiles.save(doc)){dirty=false;status('规则已保存 · 等待游戏更新规则');}
 }catch(e){if(e.name!=='AbortError')status(e.message,true);}
};
try{const saved=localStorage.getItem(draftKey);if(saved){const draft=JSON.parse(saved);if(!M.validate(draft)){doc=draft;selected=doc.rules[0]?.id??null;status('已恢复本地草稿');}}}catch{}
window.CFNEditor={document:()=>M.clone(doc),current:()=>current(),show:setTab,
 addCondition:(field,value,scope)=>{
  let r=current();if(!r){add();r=current();r.when={all:[]};if(scope)r.scope=scope;}
  const c=value===undefined?{field,op:'missing'}:{field,op:'eq',value};
  if(!r.when.all)r.when={all:[r.when]};r.when.all.push(c);setTab('rules');changed();
 },fromEvent:event=>{const r=M.makeRule(doc);r.title=event.base_title||'当前事件规则';r.scope=event.kind;
  r.when={all:[{field:'kind',op:'eq',value:event.kind}]};doc.rules.push(r);selected=r.id;setTab('rules');changed();},
 accept};
$('system-source').textContent=C.system_source;
render();directory();
