import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../..');
const lua=process.env.LUA_EXE || (process.platform==='win32'?'C:/Users/76025/AppData/Local/Programs/Lua/bin/lua.exe':'lua');
const run=spawnSync(lua,['tools/cfn_replay_capture/export_rule_catalog.lua'],{cwd:root,encoding:'utf8',maxBuffer:4e6});
if(run.status!==0) throw new Error(run.stderr || run.stdout);
function stable(value){if(Array.isArray(value))return value.map(stable);if(value && typeof value==='object')return Object.fromEntries(Object.keys(value).sort().map(k=>[k,stable(value[k])]));return value;}
const catalog=stable(JSON.parse(run.stdout));
catalog.icon='data:image/png;base64,'+readFileSync(resolve(root,'images/ui_icons/statistics_white.png')).toString('base64');
catalog.input_icons=Object.fromEntries(['1','2','3','4','5','6','7','8','9','lp','mp','hp','lk','mk','hk','modern_l','modern_m','modern_h','modern_sp','modern_auto','modern_n'].map(name=>[
 name,'data:image/png;base64,'+readFileSync(resolve(root,`images/buttonsAndArrows/${name}.png`)).toString('base64')]));
catalog.system_source=readFileSync(resolve(root,'tools/cfn_replay_capture/damage_rules.lua'),'utf8');
const output='// Generated from rule_config.lua; run build_rule_editor.mjs.\n'+
 'globalThis.CFN_RULE_CATALOG = '+JSON.stringify(catalog,null,2)+';\n';
const path=resolve(root,'tools/cfn_replay_capture/rule_editor/catalog.js');
if(process.argv.includes('--check')) {if(readFileSync(path,'utf8')!==output) throw new Error('Rule catalog drift');}
else writeFileSync(path,output);
console.log(`Rule catalog: ${catalog.fields.length} fields; ${catalog.builtins.length} system categories`);
