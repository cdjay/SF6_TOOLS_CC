-- Fake SDK contracts only; native navigation still requires a cold-start smoke.
package.path = "autorun/?.lua;" .. package.path
local hooks, updates, resets, errors = {}, {}, {}, {}
local paused, allowed, safe, writes, allocations = true, true, false, 0, 0
local storage, tid = {}, 1
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
local library={selection_label=function() return label end,selection_details=function() return details end}
package.loaded["SF6CCTrainingLibrary/Context"]={is_training_allowed=function() return allowed end,pause_open=function() return paused end}
package.loaded["SF6CCTrainingLibrary/Library"]={shared=function() return library end}
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
    hook=function(name,pre,post) hooks[name]={pre=pre,post=post} end,
}
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
check("No allocations or writes while open/unknown/offline denied",function()
    tick(120); paused=nil; tick(60); paused=false; allowed=false; tick(60)
    assert(writes==0 and allocations==0); allowed=true
end)
check("Append one root tab; preserve all native and foreign pages",function()
    tick(60)
    assert(#errors==0,table.concat(errors,"\n"))
    assert(ui._MenuData:get_size()==10)
    for i=1,9 do assert(ui._MenuData:get_element(i-1)==original[i]) end
    assert(not tm.retained and not ui.retained and not foreign.retained)
end)
local tab=ui._MenuData:get_element(9)
check("Use native root type, arrows, typed empty dynamic list, three rows",function()
    assert(tab._Type==23 and tab._FuncType==345 and tab.NextButton==7 and tab.PrevButton==8)
    assert(tab.DynamicChildData:call("get_Count")==0 and tab._ChildData:get_size()==3)
    assert(tab._ChildData:get_element(0).IsCantFocus==false)
    assert(tab._ChildData:get_element(1).IsCantFocus==true)
end)
check("No duplicate/rebuild or menu writes while navigating and reopening",function()
    local before=writes; local roots=ui._MenuData
    for i=1,5 do paused=true; tick(60); paused=false; tick(60) end
    assert(writes==before and ui._MenuData==roots and allocations==4)
end)
local function_sig="app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
check("Own rows are harmless; foreign/native callbacks pass through",function()
    local row=tab._ChildData:get_element(0)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row}),0},99)
    assert(skipped=="skip" and rv==0)
    for _,data in ipairs({foreign,original[4]}) do
        skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=data}),0},99)
        assert(skipped==nil and rv==99)
    end
end)
check("Only owned GUID messages are replaced; snapshot updates while closed",function()
    local sig="app.helper.hMsg:GetMessage(System.Guid)"
    local row=tab._ChildData:get_element(0)
    local skipped,rv=call(sig,{nil,row._MessageID},"original")
    assert(skipped=="skip" and rv.text:find(label,1,true) and rv.retained)
    paused=true; label="不知火舞[新配置]"; tick(30)
    local _,old=call(sig,{nil,row._MessageID},"original"); assert(not old.text:find(label,1,true))
    paused=false; tick(30)
    _,rv=call(sig,{nil,row._MessageID},"original"); assert(rv.text:find(label,1,true))
    skipped,rv=call(sig,{nil,foreign._MessageID},"original"); assert(skipped==nil and rv=="original")
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
    tid=2; getter(false); tid=1
    view.pre({nil,tm._UIFunc,nil,foreign}); getter(false)
    view.post(99); getter(true); view.post(99); getter(false)
    local before=writes
    for i=1,20 do
        view.pre({nil,tm._UIFunc,nil,tab}); getter(true); view.post(99)
    end
    assert(writes==before)
end)
check("Reset performs no native writes; closed-menu reload adopts own page",function()
    local before=writes; paused=true; for _,f in ipairs(resets) do f() end; tick(60)
    assert(writes==before)
    updates={}; resets={}; hooks={}; load(); tick(60); assert(writes==before)
    paused=false; tick(60)
    assert(ui._MenuData:get_size()==10 and ui._MenuData:get_element(9)==tab and allocations==4)
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
print(string.format("PASS %d native root-tab contract checks (not live-game evidence)",pass))
