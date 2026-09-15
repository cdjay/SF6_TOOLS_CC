-- Fake SDK contracts only; native navigation still requires a cold-start smoke.
package.path = "autorun/?.lua;" .. package.path
local hooks, updates, resets, errors = {}, {}, {}, {}
local paused, allowed, safe, writes, allocations = true, true, false, 0, 0
local storage, tid = {}, 1
local runtime_phase="unloaded"
local presentation_id=1
local sdk_calls, hook_installs = 0, 0
local function object(fields)
    fields = fields or {}
    function fields:get_field(k) return self[k] end
    function fields:get_address() return self end
    function fields:set_field(k, v)
        assert(safe and not paused, "write outside closed-menu update")
        writes = writes + 1; self[k] = v
    end
    function fields:add_ref() self.retained = true end
    function fields:release() error("must not release borrowed/native UI objects") end
    function fields:call(name, value)
        local key = name:match("^set_(%w+)%(")
        assert(key, "unexpected native call: " .. name)
        self:set_field("_" .. key, value)
    end
    return fields
end
local function array(items)
    local a = object({items=items})
    function a:get_size() return #self.items end
    function a:get_element(i) return self.items[i+1] end
    function a:call(name, value, i)
        assert(name == "SetValue" and safe and not paused)
        self.items[i+1] = value
    end
    return a
end
local function empty_list()
    local a = object()
    function a:call(name, first, count)
        if name == "get_Count" then return 0 end
        assert(name == "GetRange" and first == 0 and count == 0)
        return empty_list()
    end
    return a
end
local function guid()
    local bytes = {}
    return {write_byte=function(_,i,v) bytes[i]=v end, read_byte=function(_,i) return bytes[i] or 0 end}
end
local original = {}
for i=1,8 do original[i]=object({_Type=23,_FuncType=i,NextButton=7,PrevButton=8,DynamicChildData=empty_list()}) end
local foreign=object({_Type=23,_FuncType=345,_MessageID=guid()})
original[9]=foreign
local ui=object({_MenuData=array(original)})
local tm=object({_UIData=ui,_UIFunc=object(),_tData=object(),_IsInit=true})
local details={character="不知火舞 Mai / ID 28 / P2",slots="80"}
local label="不知火舞[测试配置]"
local pending_save,save_requests,save_accepted=false,0,0
local library={status="就绪",selection_label=function() return label end,selection_details=function() return details end}
function library.has_pending() return pending_save end
function library.request(kind)
    assert(kind=="save","native pilot must not expose other operations")
    save_requests=save_requests+1
    if pending_save then return false end
    pending_save=true; save_accepted=save_accepted+1
    library.status="已排队，关闭游戏暂停菜单后执行"
    return true
end
package.loaded["SF6CCTrainingLibrary/Context"]={is_training_allowed=function() return allowed end,pause_open=function() return paused end}
package.loaded["SF6CCTrainingLibrary/Library"]={shared=function() return library end}
package.loaded["SF6CCTrainingLibrary/State"]={runtime={
    state=function() return runtime_phase end,
    presentation_session=function() return runtime_phase=="active" and presentation_id or nil end,
}}
sdk={PreHookResult={SKIP_ORIGINAL="skip"},
    get_managed_singleton=function() return tm end,
    find_type_definition=function(name) return {
        get_method=function(_,s) return name..":"..s end,
        get_field=function() return {get_data=function() return {NewGuid=guid} end} end,
    } end,
    create_instance=function() error("local native factory forbidden") end,
    create_instance_global=function() allocations=allocations+1; return object() end,
    create_managed_array=function(_,n) local items={}; for i=1,n do items[i]=false end; return array(items) end,
    create_managed_string=function(s) return object({text=s}) end,
    to_managed_object=function(v) return v end,to_valuetype=function(v) return v end,
    to_ptr=function(v) return v end,to_int64=function(v) return v end,
    hook=function(name,pre,post) hook_installs=hook_installs+1; hooks[name]={pre=pre,post=post} end,
}
for name,fn in pairs(sdk) do
    if type(fn)=="function" then
        sdk[name]=function(...) sdk_calls=sdk_calls+1; return fn(...) end
    end
end
thread={get_hook_storage=function() return storage end,get_id=function() return tid end}
re={on_pre_application_entry=function(name,f) assert(name=="LateUpdateBehavior"); updates[#updates+1]=f end,
    on_script_reset=function(f) resets[#resets+1]=f end}
log={info=function() end,warn=function() end,error=function(s) errors[#errors+1]=s end}
local function load() assert(loadfile("autorun/SF6CCTrainingLibrary/NativeLibraryTab.lua"))() end
local function tick(n) safe=true; for _=1,n or 30 do for _,f in ipairs(updates) do f() end end; safe=false end
local function call(name,args,rv)
    local h=assert(hooks[name],name); storage={}
    local skip=h.pre(args); return skip,h.post(rv)
end
local pass=0
local function check(name,fn) fn(); pass=pass+1; print("PASS "..name) end
load()
check("Loading a dormant root module performs zero SDK calls or hook installs",function()
    assert(sdk_calls==0,"root module touched SDK before recording Runtime became active")
    assert(hook_installs==0 and next(hooks)==nil)
end)
check("Missing recording Runtime remains dormant",function()
    local state=package.loaded["SF6CCTrainingLibrary/State"]
    local runtime=state.runtime; state.runtime=nil
    tick(60); assert(sdk_calls==0 and hook_installs==0)
    state.runtime=runtime
end)
check("No allocations or writes while open/unknown/offline denied",function()
    tick(120); paused=nil; tick(60); paused=false; allowed=false; tick(60)
    assert(writes==0 and allocations==0); allowed=true
end)
check("Wait for recording runtime before allocating a root page",function()
    tick(60); assert(writes==0 and allocations==0 and sdk_calls==0)
    runtime_phase="active"
end)
check("Active Runtime still requires a confirmed closed offline training menu",function()
    paused=true; tick(60); paused=nil; tick(60)
    paused=false; allowed=false; tick(60); allowed=true
    assert(sdk_calls==0 and hook_installs==0)
end)
check("A Runtime without the presentation contract cannot install native UI",function()
    local runtime=package.loaded["SF6CCTrainingLibrary/State"].runtime
    local getter=runtime.presentation_session
    runtime.presentation_session=nil; tick(60)
    assert(sdk_calls==0 and hook_installs==0)
    runtime.presentation_session=getter
end)
check("Insert after Reversal; preserve all native and foreign pages",function()
    tick(60)
    assert(#errors==0,table.concat(errors,"\n"))
    assert(ui._MenuData:get_size()==10)
    for i=1,9 do assert(ui._MenuData:get_element(i<=5 and i-1 or i)==original[i]) end
    assert(not tm.retained and not ui.retained and not foreign.retained)
    assert(hook_installs==7,"root hooks must install exactly once")
end)
local tab=ui._MenuData:get_element(5)
check("Use native root type, arrows, typed empty dynamic list, one blank row",function()
    assert(tab._Type==23 and tab._FuncType==345 and tab.NextButton==7 and tab.PrevButton==8)
    assert(tab.DynamicChildData:call("get_Count")==0 and tab._ChildData:get_size()==1)
    assert(tab._ChildData:get_element(0).IsCantFocus==false)
end)
check("No duplicate/rebuild or menu writes while navigating and reopening",function()
    local before=writes; local roots=ui._MenuData
    for i=1,5 do paused=true; tick(60); paused=false; tick(60) end
    assert(writes==before and ui._MenuData==roots and allocations==2)
    assert(hook_installs==7,"root hooks were registered again")
end)
local function_sig="app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
check("Entering own root is harmless; foreign/native callbacks pass through",function()
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab}),0},99)
    assert(skipped=="skip" and rv==0)
    for _,data in ipairs({foreign,original[4]}) do
        skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=data}),0},99)
        assert(skipped==nil and rv==99)
    end
    assert(save_requests==0)
end)
check("Only owned title, save label and cached guide are replaced",function()
    local sig="app.helper.hMsg:GetMessage(System.Guid)"
    local row=tab._ChildData:get_element(0)
    local skipped,rv=call(sig,{nil,row._MessageID},"original")
    assert(skipped=="skip" and rv.text=="保存当前配置" and rv.retained)
    local _,title=call(sig,{nil,tab._MessageID},"original"); assert(title.text=="木人库")
    paused=true; label="不知火舞[新配置]"; tick(30)
    local _,old=call(sig,{nil,row._MessageID},"original"); assert(not old.text:find(label,1,true))
    paused=false; tick(30)
    _,rv=call(sig,{nil,row._MessageID},"original"); assert(rv.text=="保存当前配置")
    skipped,rv=call(sig,{nil,foreign._MessageID},"original"); assert(skipped==nil and rv=="original")
    _,rv=call(sig,{nil,row._GuideMessage},"original")
    assert(rv.text:find(label,1,true) and rv.text:find(library.status,1,true))
    assert(save_requests==0,"drawing a guide queued a job")
end)
check("Save delegates once to the shared queue and returns native close result",function()
    local row=tab._ChildData:get_element(0)
    local before=writes
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row}),0},99)
    assert(skipped=="skip" and rv==1 and save_accepted==1)
    skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row}),0},99)
    assert(skipped=="skip" and rv==0 and save_requests==1)
    assert(writes==before,"button performed native writes instead of delegating")
    local _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(guide.text:find("已排队",1,true))
    pending_save=false; library.status="保存成功"
    _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(guide.text:find("保存成功",1,true))
end)
check("Rejected save keeps native menu open and exposes shared failure status",function()
    local request=library.request
    library.request=function(kind) assert(kind=="save"); library.status="请先选择配置"; return false end
    local row=tab._ChildData:get_element(0)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row}),0},99)
    assert(skipped=="skip" and rv==0)
    local _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(guide.text:find("请先选择配置",1,true))
    library.request=request
end)
check("Request exceptions cancel queued work without closing or native writes",function()
    local request,cancel=library.request,library.request_cancel
    local cancelled=0
    library.request=function() error("injected save request failure") end
    library.request_cancel=function() cancelled=cancelled+1 end
    local before=writes
    local row=tab._ChildData:get_element(0)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row}),0},99)
    assert(skipped=="skip" and rv==0 and writes==before and cancelled==1)
    assert(library.status_ok==false and library.status:find("保存请求失败",1,true))
    assert(#errors==1 and errors[1]:find("injected save request failure",1,true))
    errors={}; library.request,library.request_cancel=request,cancel
end)
check("Layout getters are scoped to owned rows, nested layouts and threads",function()
    local view=assert(hooks["app.training.TrainingMenuFunc:ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"])
    local function getter(expected)
        for _,name in ipairs({"IsValueType","GetVisibleCase","IsChangedValue"}) do
            local skipped,rv=call("app.training.TrainingMenuFunc:"..name,{nil,tm._UIFunc,345},99)
            assert((skipped=="skip")==expected and rv==(expected and 0 or 99))
        end
    end
    getter(false)
    view.pre({nil,tm._UIFunc,nil,tab}); getter(true)
    local requests=save_requests
    local _,result=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab._ChildData:get_element(0)}),0},99)
    assert(result==0 and save_requests==requests,"layout callback queued a save")
    tid=2; getter(false); tid=1
    view.pre({nil,tm._UIFunc,nil,foreign}); getter(false)
    view.post(99); getter(true); view.post(99); getter(false)
    local before=writes
    for i=1,20 do
        view.pre({nil,tm._UIFunc,nil,tab}); getter(true); view.post(99)
    end
    assert(writes==before)
end)
check("Installed hooks are inert while recording Runtime is inactive",function()
    runtime_phase="unloaded"
    local before,requests=sdk_calls,save_requests
    for name,h in pairs(hooks) do
        storage={}
        assert(h.pre({})==nil,"dormant hook skipped native original: "..name)
        assert(h.post(99)==99,"dormant hook changed native return: "..name)
    end
    tick(60)
    assert(sdk_calls==before,"inactive Runtime hook inspected native arguments or owners")
    assert(save_requests==requests,"inactive Runtime queued a save")
    runtime_phase="active"
end)
local function assert_dormant()
    local before,requests=sdk_calls,save_requests
    for name,h in pairs(hooks) do
        storage={}
        assert(h.pre({})==nil,"stale hook inspected arguments or skipped original: "..name)
        assert(h.post(99)==99,"stale hook changed native return: "..name)
    end
    assert(sdk_calls==before and save_requests==requests,"stale session touched SDK or save queue")
end
check("Release window is dormant even before Runtime stops reporting active",function()
    presentation_id=nil
    local before=sdk_calls
    assert(runtime_phase=="active")
    assert_dormant(); tick(60)
    assert(sdk_calls==before,"release window re-adopted stale native UI")
    presentation_id=1
end)
check("Release during an owned layout disables its primitive getters",function()
    local view=hooks["app.training.TrainingMenuFunc:ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"]
    view.pre({nil,tm._UIFunc,nil,tab})
    presentation_id=nil
    local before=sdk_calls
    for _,name in ipairs({"IsValueType","GetVisibleCase","IsChangedValue"}) do
        local skipped,rv=call("app.training.TrainingMenuFunc:"..name,{},99)
        assert(skipped==nil and rv==99)
    end
    view.post(99)
    assert(sdk_calls==before)
    presentation_id=1
end)
check("A new session must adopt even when native pointers are reused",function()
    local before,roots,count=writes,ui._MenuData,allocations
    presentation_id=2
    assert_dormant()
    paused=true; tick(60); assert_dormant()
    paused=false; tick(60)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab}),0},99)
    assert(skipped=="skip" and rv==0,"new session was not adopted")
    assert(writes==before and ui._MenuData==roots and allocations==count and hook_installs==7)
end)
check("A replaced Runtime cannot reuse the old owner's equal session number",function()
    local state=package.loaded["SF6CCTrainingLibrary/State"]
    local previous=state.runtime
    state.runtime={state=previous.state,presentation_session=previous.presentation_session}
    assert_dormant(); tick(60)
    local skipped=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab}),0},99)
    assert(skipped=="skip")
end)
check("An already-skipped call completes its return during session invalidation",function()
    storage={}
    local h=hooks[function_sig]
    assert(h.pre({nil,tm._UIFunc,345,nil,object({Data=tab}),0})=="skip")
    presentation_id=nil
    assert(h.post(99)==0,"post-hook lost the return for an already skipped original")
    presentation_id=2
end)
check("Reset performs no native writes; closed-menu reload adopts own page",function()
    local before=writes; paused=true; for _,f in ipairs(resets) do f() end; tick(60)
    assert(writes==before)
    updates={}; resets={}; hooks={}; load(); tick(60); assert(writes==before)
    paused=false; tick(60)
    assert(ui._MenuData:get_size()==10 and ui._MenuData:get_element(5)==tab and allocations==2)
end)
check("Recreated UI receives one page; stale UI is never restored or written",function()
    local stale=ui; local previous=stale._MenuData
    ui=object({_MenuData=array(original)}); tm._UIData=ui; tm._tData=object()
    tick(60); assert(ui._MenuData:get_size()==10 and stale._MenuData==previous)
    assert(#errors==0,table.concat(errors,"\n"))
end)
check("Changed native ordering fails before allocating or publishing",function()
    local bad={}; for i,v in ipairs(original) do bad[i]=v end
    bad[1]=object({_Type=23,_FuncType=999})
    ui=object({_MenuData=array(bad)}); tm._UIData=ui
    local before=writes; local count=allocations; local untouched=ui._MenuData
    tick(60)
    assert(writes==before and allocations==count and ui._MenuData==untouched and #errors==1)
end)
check("Partial hook setup fails once without publishing or automatic retries",function()
    updates={}; resets={}; hooks={}; errors={}
    ui=object({_MenuData=array(original)}); tm._UIData=ui
    local register=sdk.hook
    local attempts=0
    sdk.hook=function(...)
        attempts=attempts+1
        if attempts==2 then error("injected hook setup failure") end
        return register(...)
    end
    local before_calls,before_writes,before_allocations=sdk_calls,writes,allocations
    load(); assert(sdk_calls==before_calls)
    tick(60)
    assert(attempts==2 and #errors==1 and errors[1]:find("injected hook setup failure",1,true))
    assert(writes==before_writes and allocations==before_allocations and ui._MenuData:get_size()==9)
    before_calls=sdk_calls
    tick(300)
    for _,h in pairs(hooks) do
        storage={}; assert(h.pre({})==nil and h.post(99)==99)
    end
    assert(sdk_calls==before_calls and attempts==2 and #errors==1)
    sdk.hook=register
end)
print(string.format("PASS %d native root-tab contract checks (not live-game evidence)",pass))
