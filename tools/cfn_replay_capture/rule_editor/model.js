(function(root){
'use strict';
const catalog=root.CFN_RULE_CATALOG;
const fields=new Map(catalog.fields.map(f=>[f.key,f]));
const clone=x=>JSON.parse(JSON.stringify(x));
const finite=x=>typeof x==='number' && Number.isFinite(x);
function assert(ok,message){if(!ok) throw new Error(message);}
const byteLength=s=>new TextEncoder().encode(s).length;
function keys(o,allowed){assert(o && typeof o==='object' && !Array.isArray(o),'配置对象不正确');for(const k of Object.keys(o)) assert(allowed.includes(k),`不支持的设置项：${k}`);}
function validate(doc){
 try{
  keys(doc,['schema','build','name','include_system','settings','rules']);assert(doc.schema===catalog.schema && doc.build===catalog.build,'规则格式或游戏版本不匹配');
  assert(doc.include_system==null||typeof doc.include_system==='boolean','包含系统规则必须是开关');
  const title=s=>typeof s==='string' && byteLength(s)>0 && byteLength(s)<=180 && !/[\x00-\x1f\x7f]/.test(s);
  assert(title(doc.name),'规则名称不正确');keys(doc.settings,catalog.settings.map(s=>s.key));
  for(const s of catalog.settings){const v=doc.settings[s.key];assert(Number.isInteger(v)&&v>=s.min&&v<=s.max,`范围不正确：${s.label}`);}
  assert(Array.isArray(doc.rules)&&doc.rules.length<=100,'最多100条规则');const ids=new Set();let count=0;
  function node(c,depth){
   assert(++count<=2000&&depth<=6,'条件过多或嵌套过深');assert(c&&typeof c==='object'&&!Array.isArray(c),'条件格式不正确');
   if('all' in c || 'any' in c || 'not' in c){
    keys(c,['all','any','not']);assert(Object.keys(c).length===1,'条件组合只能选一种');
    if('not' in c) node(c.not,depth+1);
    else{const a=c.all??c.any;assert(Array.isArray(a)&&a.length>0&&a.length<=32,'条件组需要1至32项');a.forEach(x=>node(x,depth+1));}return;
   }
   keys(c,['field','op','value','value_field']);const f=fields.get(c.field);assert(f,'未知条件字段');
   assert(['exists','missing','eq','ne'].includes(c.op)||(f.type==='number'&&['gt','ge','lt','le','between','bits_any','bits_all'].includes(c.op)),'条件比较方式不正确');
   if('value_field' in c){assert(f.type==='number'&&fields.get(c.value_field)?.type==='number'&&!('value' in c)&&['eq','ne','gt','ge','lt','le'].includes(c.op),'字段比较需要两个数值字段');return;}
   if(['exists','missing'].includes(c.op)){assert(!('value' in c),'存在性条件不带比较值');return;}
   if(c.op==='between') assert(Array.isArray(c.value)&&c.value.length===2&&c.value.every(finite)&&c.value[0]<=c.value[1],'范围上下限不正确');
   else if(f.type==='number') assert(finite(c.value)&&Math.abs(c.value)<=Number.MAX_SAFE_INTEGER,'数值无效');
   else if(f.type==='boolean') assert(typeof c.value==='boolean','请选择是或否');
   else assert(f.options.some(o=>o[0]===c.value),'选项不存在');
   if(['bits_any','bits_all'].includes(c.op)) assert(Number.isInteger(c.value)&&c.value>0&&c.value<=2147483647,'标记值必须是正整数');
  }
  for(const r of doc.rules){
   keys(r,['id','title','enabled','scope','priority','when','opportunity']);
   assert(typeof r.id==='string'&&/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(r.id)&&!ids.has(r.id),'规则编号重复或不正确');ids.add(r.id);
   assert(title(r.title),'问题描述长度不正确');assert(typeof r.enabled==='boolean'&&['damage','guard'].includes(r.scope),'规则类型不正确');
   assert(['P1','P2','P3'].includes(r.priority),'自定义规则不能设为人工确认P0');
   assert(!('opportunity' in r)||(r.scope==='guard'&&typeof r.opportunity==='boolean'),'机会设置只用于防御规则');node(r.when,1);
  }
  return null;
 }catch(e){return e.message;}
}
function matches(c,ctx){
 if(c.not){const v=matches(c.not,ctx);return v===null?null:!v;}
 if(c.all||c.any){const values=(c.all||c.any).map(x=>matches(x,ctx));if(c.all&&values.includes(false))return false;if(c.any&&values.includes(true))return true;if(values.includes(null))return null;return !!c.all;}
 const f=fields.get(c.field),v=ctx[c.field];
 const known=f&&((f.type==='number'&&finite(v))||(f.type==='boolean'&&typeof v==='boolean')||(f.type==='enum'&&v!==undefined&&v!==null));
 if(c.op==='exists')return !!known;if(c.op==='missing')return !known;if(!known)return null;
 const n=c.value_field?ctx[c.value_field]:c.value;if(c.value_field&&!finite(n))return null;
 switch(c.op){case 'eq':return v===n;case 'ne':return v!==n;case 'gt':return v>n;case 'ge':return v>=n;case 'lt':return v<n;case 'le':return v<=n;
 case 'between':return v>=n[0]&&v<=n[1];case 'bits_any':case 'bits_all':if(!Number.isSafeInteger(v))return null;{const bits=BigInt(v)&BigInt(n);return c.op==='bits_any'?bits!==0n:bits===BigInt(n);}default:return null;}
}
function match(doc,scope,ctx){return doc.rules.find(r=>r.enabled&&r.scope===scope&&matches(r.when,ctx)===true)??null;}
function makeRule(doc,base){let i=1;while(doc.rules.some(r=>r.id===`rule_${i}`))i++;return {id:`rule_${i}`,title:base?.[1]??'新规则',scope:'damage',enabled:true,priority:'P3',when:{all:[base?{field:'base_rule',op:'eq',value:base[0]}:{field:'damage',op:'ge',value:1000}]}};}
const api={catalog,fields,clone,validate,matches,match,makeRule};root.CFNRuleModel=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
