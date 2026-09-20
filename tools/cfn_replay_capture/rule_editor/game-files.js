(function(root){
'use strict';
let folder,data;
async function connect(){
 if(!root.showDirectoryPicker)throw new Error('此浏览器不支持文件夹授权，请使用导入和导出');
 const next=await root.showDirectoryPicker({id:'sf6-reframework',mode:'readwrite'});
 if(next.name.toLowerCase()!=='reframework')throw new Error('请选择游戏的 reframework 文件夹');
 const child=await next.getDirectoryHandle('data');folder=next;data=child;return true;
}
async function save(doc){
 const error=root.CFNRuleModel.validate(doc);if(error)throw new Error(error);
 const snapshot=root.CFNRuleModel.clone(doc);
 if(!data)await connect();
 let previous;try{previous=await data.getFileHandle('cfn-replay-rules.json');}catch(e){if(e.name!=='NotFoundError')throw e;}
 if(previous&&!root.confirm('覆盖游戏中现有的录像规则配置？'))return false;
 const file=previous||await data.getFileHandle('cfn-replay-rules.json',{create:true});
 const writer=await file.createWritable();
 try{await writer.write(JSON.stringify(snapshot,null,2));await writer.close();}catch(e){await writer.abort().catch(()=>{});throw e;}
 root.dispatchEvent(new CustomEvent('cfn-config-saved',{detail:snapshot}));return true;
}
async function read(){
 if(!data)throw new Error('请先连接游戏文件夹');
 const handle=await data.getFileHandle('cfn-workbench.json');return handle.getFile();
}
root.CFNGameFiles={connect,save,read,connected:()=>!!folder};
})(globalThis);
