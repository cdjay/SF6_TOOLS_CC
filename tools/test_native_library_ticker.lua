package.path="autorun/?.lua;"..package.path
local Ticker=require("SF6CCTrainingLibrary/NativeTicker")
local hooks,storage,sent={}, {},{}
local safe,calls,sequence=false,0,0
local function write() assert(safe,"native write outside update"); calls=calls+1 end
local manager={call=function(_,name,req)
    write(); assert(name=="RequestShowTicker(app.TickerRequestData)")
    sent[#sent+1]=req
end}
local api={PreHookResult={SKIP_ORIGINAL="skip"}}
function api.find_type_definition(name)
    calls=calls+1
    return {get_method=function(_,method)
        return {name=name..":"..method,call=function() return manager end}
    end}
end
function api.hook(method,pre,post) hooks[method.name]={pre,post} end
function api.create_instance_global() error("global factory releases its only reference on a stale wrapper") end
function api.create_instance(name,simplify)
    write(); assert(name=="app.TickerRequestData")
    assert(simplify==true,"TickerRequestData requires WTT's simplified creation path")
    sequence=sequence+1
    local obj={id=sequence,fields={}}
    function obj:add_ref_permanent() self.permanent=true end
    function obj:add_ref() error("request must not depend on Lua reference bookkeeping") end
    function obj:get_address() return self.id end
    function obj:get_field(k) return self.fields[k] end
    function obj:set_field(k,v) write(); self.fields[k]=v end
    function obj:call(method,id,args)
        write(); assert(method=="Init" and id==112 and args==nil)
    end
    return obj
end
function api.to_managed_object(obj) return obj end
local strings=0
function api.create_managed_string(text)
    strings=strings+1
    return {text=text,add_ref=function() error("string must not depend on Lua reference bookkeeping") end,
        add_ref_permanent=function(self) self.permanent=true end}
end
function api.to_ptr(v) return v end
local t=Ticker.new({api=api,threads={get_hook_storage=function() return storage end},clock=function() return 0 end})
assert(calls==0)
t.enqueue("木人库：保存完成"); assert(calls==0)
t.tick(false); assert(calls==0 and #sent==0)
t.enqueue("木人库：保存完成")
safe=true; t.tick(true); safe=false
assert(#sent==1)
local req=sent[1]
assert(req.fields.TickerId==1 and req.fields.Category==6 and req.fields.IsForceDisplay==true)
assert(req.permanent,"submitted request polled later must hold a permanent engine reference")
local h=assert(hooks["app.TickerRequestData:GetMessage"])
assert(h[1]({nil,req})=="skip")
local message=h[2]("original"); assert(message.text=="木人库：保存完成" and message.permanent)
assert(h[1]({nil,req})=="skip" and h[2]("original")==message,"repeated native reads must reuse one string")
assert(strings==1,"GetMessage allocated a new string per native read")
t.enqueue("old wait"); t.enqueue("operation failed"); t.enqueue("old wait")
local before=calls
t.discard("old wait")
assert(t.pending_count()==1 and calls==before,"discard touched native state or removed other results")
t.discard("木人库：保存完成")
assert(h[1]({nil,req})=="skip" and h[2]("original").text==message.text,"discard invalidated submitted native text")
t.clear()
assert(h[1]({nil,{get_address=function() return 999 end}})==nil and h[2]("original")=="original")
req.fields.IsDisplayEnd=true
safe=true; t.tick(true); safe=false
assert(h[1]({nil,req})==nil and h[2]("original")=="original")
for i=1,100 do t.enqueue("消息"..i) end
assert(t.pending_count()<=20)
t.clear(); assert(t.pending_count()==0)
t.stop(); assert(h[1]({})==nil and h[2]("original")=="original")
assert(not t.enqueue("stopped"))
print("PASS native ticker: deferred dispatch, own requests, native pause visibility flag, bounded queue, shutdown")
