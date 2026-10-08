-- Fake SDK contracts only; native navigation still requires a cold-start smoke.
package.path = "autorun/?.lua;" .. package.path
local hooks, updates, resets, errors = {}, {}, {}, {}
local paused, allowed, safe, writes, allocations = true, true, false, 0, 0
local navigating=false
local storage, tid = {}, 1
local runtime_phase="unloaded"
local presentation_id=1
local sdk_calls, hook_installs = 0, 0
local notifications={}
package.loaded["SF6CCTrainingLibrary/NativeTicker"]={new=function() return {
    prepare=function() return true end,stop=function() end,tick=function() end,
    enqueue=function(text) notifications[#notifications+1]=text; return true end,
} end}
local function object(fields)
    fields = fields or {}
    function fields:get_field(k) return self[k] end
    function fields:get_address() return self end
    function fields:set_field(k, v)
        assert((safe and not paused) or (navigating and (k=="IsCantFocus" or k=="IsUpdate" or k=="_Type" or k=="_ChildData" or k=="Index")), "write outside allowed UI scope")
        writes = writes + 1; self[k] = v
    end
    function fields:add_ref() error("library objects must not depend on Lua reference bookkeeping") end
    function fields:add_ref_permanent() self.permanent = (self.permanent or 0) + 1 end
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
local details={character="不知火舞 Mai / ID 28 / P2",slots="80",saved="今天"}
local label="不知火舞[测试配置]"
local pending_save,save_requests,save_accepted=false,0,0
local action_requests={}
local library={status="就绪",selection_label=function() return label end,selection_details=function() return details end}
library.loaded=true; library.revision=1; library.selected=1
library.entries={{path="a",metadata={fighter_id=28}},{path="b",metadata={fighter_id=28}}}
library.selection=function() return library.entries[library.selected] end
library.select=function(i) library.selected=i; return true end
library.slot_capacity=function() assert(safe and not paused and not navigating); return 8 end
library.slot_name=function(i) return i==8 and "截空" or "" end
library.can_edit_slot_names=function() return true end
function library.has_pending() return pending_save end
function library.request_cancel() pending_save=false end
function library.request(kind)
    assert(kind=="save" or kind=="export" or kind=="refresh" or kind=="clear"
        or kind=="import","unexpected operation")
    action_requests[#action_requests+1]=kind
    if kind=="save" then save_requests=save_requests+1 end
    if pending_save then return false end
    pending_save=true
    if kind=="save" then save_accepted=save_accepted+1 end
    library.status="已排队，关闭游戏暂停菜单后执行"; library.status_ok=true
    return true
end
local editor_installs,editor_requests,editor_ready=0,0,true
local editor_slot
package.loaded["SF6CCTrainingLibrary/NativeNoteEditor"]={install=function()
    assert(safe and not paused and allowed and runtime_phase=="active","editor installed outside closed active training")
    editor_installs=editor_installs+1
    return {available=function() return editor_ready end,request=function(slot)
        editor_slot=slot
        assert(navigating and not pending_save)
        editor_requests=editor_requests+1; pending_save=true
        library.status_ok=true; library.status="关闭暂停菜单后修改训练配置名称（最多15个字符）"
        return true
    end}
end}
package.loaded["SF6CCTrainingLibrary/Context"]={is_training_allowed=function() return allowed end,
    training_state=function() return allowed and "training" or nil end,pause_open=function() return paused end}
local fighter=28
package.loaded["SF6CCTrainingLibrary/Library"]={shared=function() return library end,
    runtime_context=function() return {allowed=allowed,fighter_id=fighter} end}
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
    create_instance_global=function() error("global factory drops its only reference on a stale wrapper") end,
    create_instance=function() allocations=allocations+1; return object() end,
    create_managed_array=function(_,n) local items={}; for i=1,n do items[i]=false end; return array(items) end,
    create_managed_string=function(s) return object({text=s}) end,
    to_managed_object=function(v) return v end,to_valuetype=function(v) return v end,
    to_ptr=function(v) return v end,to_int64=function(v) return v end,
    hook=function(name,pre,post)
        hook_installs=hook_installs+1
        local old=hooks[name]
        hooks[name]={pre=function(args)
            local a=old and old.pre(args); local b=pre(args); return a or b
        end,post=function(rv) return post(old and old.post(rv) or rv) end}
    end,
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
local function call(name,args,rv,body)
    local h=assert(hooks[name],name); local previous=storage; storage={}
    local before=navigating; navigating=name:find(":Function(",1,true)~=nil
        or name=="app.training.UIFlowTrainingMenu.Param:ChangeTabIndex(System.Int32)"
    local skip=h.pre(args); if body then body() end
    local result=h.post(rv); navigating=before; storage=previous
    return skip,result
end
local pass=0
local function check(name,fn) fn(); pass=pass+1; print("PASS "..name) end
load()
check("Loading a dormant root module performs zero SDK calls or hook installs",function()
    assert(sdk_calls==0,"root module touched SDK before recording Runtime became active")
    assert(hook_installs==0 and next(hooks)==nil)
    assert(editor_installs==0,"editor registered hooks during module load")
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
    assert(editor_installs==0)
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
    assert(not tm.permanent and not ui.permanent and not foreign.permanent,"borrowed native objects gained references")
    assert(ui._MenuData.permanent==1,"published root array must hold one permanent engine reference")
    assert(hook_installs==16,"root, tab transition and list spin hooks must install exactly once")
end)
local tab=ui._MenuData:get_element(5)
check("Use native root type, arrows, empty dynamic list and requested thirteen-row body",function()
    assert(tab._Type==23 and tab._FuncType==345 and tab.NextButton==7 and tab.PrevButton==8)
    assert(tab.DynamicChildData:call("get_Count")==0 and tab._ChildData:get_size()==13)
    assert(tab._ChildData:get_element(2).IsCantFocus==false)
end)
check("Page, rows and their arrays hold exactly one permanent engine reference",function()
    assert(tab.permanent==1 and tab._ChildData.permanent==1 and tab.DynamicChildData.permanent==1)
    for i=0,12 do assert(tab._ChildData:get_element(i).permanent==1,"row "..i.." lacks its permanent reference") end
    assert(allocations==14,"expected one page and thirteen rows")
end)
check("No duplicate/rebuild or menu writes while navigating and reopening",function()
    local before=writes; local roots=ui._MenuData
    for i=1,5 do paused=true; tick(60); paused=false; tick(60) end
    assert(writes==before and ui._MenuData==roots and allocations==14)
    assert(hook_installs==16,"root hooks were registered again")
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
    local row=tab._ChildData:get_element(2)
    local skipped,rv=call(sig,{nil,row._MessageID},"original")
    assert(skipped=="skip" and rv.text=="保存当前配置" and rv.permanent==1)
    local _,again=call(sig,{nil,row._MessageID},"original")
    assert(again==rv,"repeated native text reads must reuse one permanent string")
    local _,title=call(sig,{nil,tab._MessageID},"original"); assert(title.text=="木人库")
    paused=true; label="不知火舞[新配置]"; tick(30)
    local _,old=call(sig,{nil,row._MessageID},"original"); assert(not old.text:find(label,1,true))
    paused=false; tick(30)
    _,rv=call(sig,{nil,row._MessageID},"original"); assert(rv.text=="保存当前配置")
    skipped,rv=call(sig,{nil,foreign._MessageID},"original"); assert(skipped==nil and rv=="original")
    _,rv=call(sig,{nil,row._GuideMessage},"original")
    assert(rv.text:find(label,1,true) and not rv.text:find(library.status,1,true))
    assert(save_requests==0,"drawing a guide queued a job")
end)
check("Save delegates once to the shared queue and returns native close result",function()
    local row=tab._ChildData:get_element(2)
    local before=writes
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(skipped=="skip" and rv==1 and save_accepted==1)
    skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(skipped=="skip" and rv==0 and save_requests==1)
    assert(writes==before,"button performed native writes instead of delegating")
    local _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(not guide.text:find("已排队",1,true))
    assert(notifications[#notifications]:find("尚未完成",1,true))
    pending_save=false; library.status="已保存：测试.json"; library.status_ok=true
    tick(6)
    _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(not guide.text:find("配置已保存",1,true))
    assert(notifications[#notifications]:find("配置已保存",1,true))
end)
check("Rejected save stays open and reports through ticker, never menu text",function()
    local request=library.request
    library.request=function(kind) assert(kind=="save"); library.status="请先选择配置"; return false end
    local row=tab._ChildData:get_element(2)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(skipped=="skip" and rv==0)
    local _,guide=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,row._GuideMessage},"original")
    assert(not guide.text:find("请先选择配置",1,true))
    assert(notifications[#notifications]:find("请先选择训练配置",1,true))
    library.request=request
end)
check("Request exceptions cancel queued work without closing or native writes",function()
    local request,cancel=library.request,library.request_cancel
    local cancelled=0
    library.request=function() error("injected save request failure") end
    library.request_cancel=function() cancelled=cancelled+1 end
    local before=writes
    local row=tab._ChildData:get_element(2)
    local skipped,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(skipped=="skip" and rv==0 and writes==before and cancelled==1)
    assert(library.status_ok==false and library.status:find("操作请求失败",1,true))
    assert(#errors==1 and errors[1]:find("injected save request failure",1,true))
    errors={}; library.request,library.request_cancel=request,cancel
end)
check("Requested main actions keep save-as and clear at their new positions",function()
    for _,item in ipairs({
        {3,"export","已导出：测试.json","配置已另存"},
    }) do
        local row=tab._ChildData:get_element(item[1])
        local before,notices=writes,#notifications
        local _,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
        assert(rv==1 and writes==before)
        assert(action_requests[#action_requests]==item[2])
        paused=true; tick(120); assert(#notifications==notices)
        pending_save=false; paused=false; library.status=item[3]; library.status_ok=true; tick(6)
        assert(#notifications==notices+1 and notifications[#notifications]==item[4])
    end
end)
check("Fixed rows open a catalog and double confirmation imports without rebuilding",function()
    paused=true
    local views={}
    for i=0,12 do views[i+1]=object({Data=tab._ChildData:get_element(i),ParentData=tab}) end
    local groups={}
    local function list(items)
        return {call=function(_,name,index)
            if name=="get_Count" then return #items end
            assert(name=="get_Item"); return items[index+1]
        end}
    end
    for i=1,13 do
        groups[i]=object({["<Index>k__BackingField"]=i-1,["<Layout>k__BackingField"]=5,
            _FocusIndex=views[i].Data._Type,_Children=list({{},{},{},{},{}})})
        groups[i].call=function(self,name,value)
            assert(navigating and name=="ChangeFocusIndex(System.Int32)")
            self._FocusIndex=value
        end
    end
    local param=object({_ViewDataList={call=function(_,name,i)
        if name=="get_Count" then return #views end
        assert(name=="get_Item"); return views[i+1]
    end}})
    function param:get_type_definition() return {get_full_name=function() return "app.training.UIFlowTrainingMenu.Param" end} end
    param._SecondaryList=object({_Children=list(groups)})
    local focus=9
    param._SecondaryList.call=function(_,name) assert(name=="GetFocusIndex"); return focus end
    param._SecondarySpinIndex=9
    tm._UITrainingMenu=object({_ParamData=param})
    local spin_ready,spin_initializations=false,0
    local spin_row=10
    local primary_index=5
    function param:call(name,index)
        if name=="get_PrimaryListIndex" then return primary_index end
        assert(name=="InitSpinBox(System.Int32)","whole-page initialization/refresh is forbidden")
        assert(navigating and (index==0 or index==9))
        spin_row=index+1
        focus=index; self._SecondarySpinIndex=index
        assert(views[spin_row].Data._Type==1 and groups[spin_row]._FocusIndex==1)
        assert(views[spin_row].Data._ChildData:get_size()>1 and views[spin_row].Index==0)
        local requests=#action_requests
        local _,result=call(function_sig,{nil,tm._UIFunc,345,param,views[3],0},99)
        assert(result==0 and #action_requests==requests,"spin initialization dispatched a user operation")
        spin_ready=true; spin_initializations=spin_initializations+1
        return true
    end
    local function press(index)
        return call(function_sig,{nil,tm._UIFunc,345,param,views[index],0},99)
    end
    local function spin(wanted,child)
        assert(spin_ready,"native page arrow changes its own value but has no list update callback")
        local sig="app.training.UIFlowTrainingMenu.Param:OnUpdateSpin()"
        call(sig,{nil,param},99,function()
            local _,value=call("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)",
                {nil,tm._UIFunc,345,wanted,345},99)
            views[spin_row].Index=value -- The engine commits before Function/repaint.
            call("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)",
                {nil,tm._UIFunc,345,wanted+1,345},99)
            local target=child and object({Data=views[spin_row].Data._ChildData:get_element(value),ParentData=views[spin_row].Data}) or views[spin_row]
            call(function_sig,{nil,tm._UIFunc,345,param,target,child and (spin_row-1) or value},99)
            assert(views[2].IsUpdate and views[spin_row].Index==wanted,"first click failed to bind before native repaint")
        end)
        assert(#errors==0,table.concat(errors,"\n"))
    end
    local count,requests=allocations,#action_requests
    assert(views[2].Data._Type==4 and views[8].Data._Type==4)
    local before=writes
    local missing=table.remove(views)
    local _,invalid=press(1)
    assert(invalid==0 and writes==before and #action_requests==requests)
    assert(#errors==1 and errors[1]:find("view count changed",1,true))
    errors={}; views[#views+1]=missing
    groups[2]["<Index>k__BackingField"]=99
    _,invalid=press(1)
    assert(invalid==0 and writes==before and #action_requests==requests)
    assert(#errors==1 and errors[1]:find("display row identity changed",1,true))
    errors={}; groups[2]["<Index>k__BackingField"]=1
    local _,rv=press(1); assert(rv==0 and allocations==count and #action_requests==requests)
    for _,v in ipairs(views) do assert(v.IsUpdate==true and v.Data._Type==0) end
    for i,g in ipairs(groups) do assert(g._FocusIndex==views[i].Data._Type,"native display retained separator at row "..i) end
    _,rv=press(2); assert(rv==0 and library.selected==1 and #action_requests==requests)
    local _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[2].Data._MessageID},"original")
    assert(label.text:find("再次确认导入",1,true))
    paused=false; tick(1); paused=true
    _,rv=press(2); assert(rv==0 and #action_requests==requests,"brief menu closure reused confirmation")
    _,rv=press(2); assert(rv==1 and action_requests[#action_requests]=="import")
    pending_save=false; library.status="配置已导入，请核对录像栏位及播放效果"; paused=false; tick(30)
    paused=true; press(1)
    _,rv=press(12); assert(rv==1 and action_requests[#action_requests]=="refresh")
    pending_save=false; library.status="已刷新，共 2 个配置"; paused=false; tick(30)
    paused=true; press(1); _,rv=press(13); assert(rv==0)
    _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[1].Data._MessageID},"original")
    assert(label.text=="切换配置【当前："..library.selection_label().."】" and allocations==count)
    assert(views[2].Data._Type==4 and views[8].Data._Type==4)
    for i,g in ipairs(groups) do assert(g._FocusIndex==views[i].Data._Type,"return retained list display at row "..i) end
    paused=false; tick(30)
    local slot_requests=#action_requests
    for _,slot in ipairs({1,8}) do
        paused=true
        spin_ready=false
        local inits=spin_initializations
        _,rv=press(6); assert(rv==0,"slot browser must stay open")
        assert(not spin_ready and spin_initializations==inits,"one native page must not initialize arrows")
        for i,v in ipairs(views) do assert(v.Data._Type==0) end
        for i,g in ipairs(groups) do assert(g._FocusIndex==views[i].Data._Type) end
        local index=(slot-1)%8+2
        _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[index].Data._MessageID},"original")
        assert(label.text:find("栏位"..slot,1,true))
        _,rv=press(index); assert(rv==1 and editor_slot==slot)
        assert(#action_requests==slot_requests and allocations==count and hook_installs==16)
        pending_save=false; paused=false; tick(30)
    end
    -- Use a catalog long enough to exercise the same native arrows, then verify
    -- returning to a one-page catalog removes the spinner and its old variant.
    local saved_entries=library.entries
    for i=3,17 do library.entries[i]={path="config"..i,metadata={fighter_id=28}} end
    library.revision=library.revision+1; tick(30)
    paused=true; press(1)
    assert(views[10].Data._Type==1 and views[10].Data._ChildData:get_size()==3)
    for _,p in ipairs({1,2,1,0}) do
        spin(p,true)
        local _,text=call("app.training.TrainingMenuFunc:GetOptionText(app.training.TrainingFuncType)",{nil,tm._UIFunc,345},99)
        assert(text.text==(p+1).." / 3")
        local requests=#action_requests
        press(2); assert(library.selected==p*8+1 and #action_requests==requests)
    end
    local inits=spin_initializations
    press(13)
    assert(groups[10]._FocusIndex==0 and views[10].Data._Type==0)
    assert(spin_initializations==inits,"leaving the list must not initialize a spin")
    press(6)
    assert(groups[1]._FocusIndex==0 and groups[10]._FocusIndex==0)
    press(10)
    assert(groups[1]._FocusIndex==0,"return retained the slot page")
    press(1)
    assert(spin_row==10 and groups[10]._FocusIndex==1 and groups[1]._FocusIndex==0)
    spin(1,false)
    press(13)
    inits=spin_initializations
    paused=false
    library.entries={saved_entries[1],saved_entries[2]}; library.selected=1
    library.revision=library.revision+1; tick(30)
    paused=true; press(1)
    assert(views[10].Data._Type==0 and views[10].Data.IsCantFocus and groups[10]._FocusIndex==0)
    assert(spin_initializations==inits,"single-page catalog must not initialize hidden arrows")
    local _,blank=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[10].Data._MessageID},"original")
    assert(blank.text=="")
    press(13); paused=false; tick(30)
    assert(allocations==count+3 and #errors==0,"catalog expansion should allocate only three page options")
    count=allocations
    paused=true
    local tab_change="app.training.UIFlowTrainingMenu.Param:ChangeTabIndex(System.Int32)"
    local function change_tab(target)
        local skip,result=call(tab_change,{nil,param,target},123,function() primary_index=target end)
        assert(skip==nil and result==123,"tab transition must preserve the native call")
        for i,g in ipairs(groups) do g._FocusIndex=views[i].Data._Type end
    end
    for _,button in ipairs({6,1}) do
        press(button)
        local before_allocations=allocations
        change_tab(4); change_tab(5)
        _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[1].Data._MessageID},"original")
        assert(label.text:find("切换配置",1,true),"reentering the top-level tab retained a secondary page")
        assert(views[1].Data._Type==0 and views[2].Data._Type==4 and allocations==before_allocations)
    end
    press(6)
    local before_writes=writes
    call(tab_change,{nil,object(),4},123)
    call(tab_change,{nil,param,999},123)
    assert(writes==before_writes,"foreign or invalid tab transition changed owned rows")
    change_tab(5)
    _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[2].Data._MessageID},"original")
    assert(label.text:find("栏位1",1,true),"same-tab update must not reset a live inner page")
    press(10)
    local requests=#action_requests
    local notices=#notifications
    press(7); assert(#action_requests==requests)
    _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[7].Data._MessageID},"original")
    assert(label.text=="【再次确认清空】清空所有栏位" and views[7].IsUpdate)
    assert(#notifications==notices and not pending_save,"first confirmation must not notify or queue clearing")
    change_tab(4); change_tab(5)
    _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[7].Data._MessageID},"original")
    assert(label.text=="清空所有栏位","tab change retained the confirmation label")
    press(7); assert(#action_requests==requests,"switching tabs must discard clear confirmation")
    press(7); assert(#action_requests==requests+1 and action_requests[#action_requests]=="clear")
    _,label=call("app.helper.hMsg:GetMessage(System.Guid)",{nil,views[7].Data._MessageID},"original")
    assert(label.text=="清空所有栏位" and #notifications==notices)
    pending_save=false; paused=false; tick(30)
end)
check("Configuration rename uses the existing editor and native close protocol",function()
    assert(editor_installs==1)
    paused=true
    local row=tab._ChildData:get_element(4)
    assert(row.IsCantFocus==false)
    local before,notices,requests=writes,#notifications,#action_requests
    local edits=editor_requests
    local _,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(rv==1 and editor_requests==edits+1 and editor_slot==nil and writes==before and #action_requests==requests)
    tick(120); assert(#notifications==notices,"rename requested manual menu closure")
    _,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(rv==0 and editor_requests==edits+1,"duplicate click opened a second dialog")
    pending_save=false; paused=false
    library.status="配置名称已保存"; library.result_revision=1
    library.result_configuration={revision=1,kind="notes",title="新名字"}
    tick(30)
    assert(notifications[#notifications]=="新名字 配置名称已修改")
    editor_ready=false
    _,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=row,ParentData=tab}),0},99)
    assert(rv==0 and editor_requests==edits+1,"unavailable editor received request")
    editor_ready=true
end)
check("Readonly separators and summary rows never queue an operation",function()
    local count=#action_requests
    for _,i in ipairs({1,7,8,9,10,11,12}) do
        local _,rv=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab._ChildData:get_element(i),ParentData=tab}),0},99)
        assert(rv==0 and #action_requests==count)
    end
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
    local _,result=call(function_sig,{nil,tm._UIFunc,345,nil,object({Data=tab._ChildData:get_element(2),ParentData=tab}),0},99)
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
    assert(writes==before and ui._MenuData==roots and allocations==count and hook_installs==16)
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
    local before,old_allocations=writes,allocations; paused=true; for _,f in ipairs(resets) do f() end; tick(60)
    assert(writes==before)
    updates={}; resets={}; hooks={}; load(); tick(60); assert(writes==before)
    paused=false; tick(60)
    assert(ui._MenuData:get_size()==10 and ui._MenuData:get_element(5)==tab
        and allocations==old_allocations,
        "reset allocations "..tostring(allocations).." from "..tostring(old_allocations))
end)
check("Recreated UI receives one page; stale UI is never restored or written",function()
    local stale=ui; local previous=stale._MenuData
    local count=allocations
    ui=object({_MenuData=array(original)}); tm._UIData=ui; tm._tData=object()
    tick(60); assert(ui._MenuData:get_size()==10 and stale._MenuData==previous)
    assert(#errors==0,table.concat(errors,"\n"))
    assert(ui._MenuData:get_element(5)==tab and tab.permanent==2,
        "recreated UI must reuse the adopted page, retained once by this Lua state")
    assert(allocations==count,"recreated UI allocated new page nodes")
    for _=1,3 do
        presentation_id=presentation_id+1
        ui=object({_MenuData=array(original)}); tm._UIData=ui; tm._tData=object()
        tick(60)
        assert(ui._MenuData:get_element(5)==tab and allocations==count and #errors==0,
            "repeated training entries must not be limited or allocate page nodes")
    end
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
check("Mid-session root rebuilds reuse the page and a runaway loop stops",function()
    updates={}; resets={}; hooks={}; errors={}
    load()
    ui=object({_MenuData=array(original)}); tm._UIData=ui; tm._tData=object()
    presentation_id=presentation_id+1
    tick(60)
    assert(#errors==0 and ui._MenuData:get_size()==10)
    local page=ui._MenuData:get_element(5)
    local count=allocations
    for _=1,2 do
        ui._MenuData=array(original) -- game rebuilt the root mid-session
        tick(60)
        assert(#errors==0 and ui._MenuData:get_size()==10 and ui._MenuData:get_element(5)==page,
            "an occasional rebuild must re-insert the same page")
        assert(allocations==count,"republication allocated page nodes")
    end
    local rebuilt=array(original); ui._MenuData=rebuilt
    tick(60)
    assert(#errors==1 and errors[1]:find("replaced repeatedly during session",1,true))
    assert(ui._MenuData==rebuilt and rebuilt:get_size()==9 and allocations==count,
        "a runaway replacement loop must not keep publishing")
    tick(300); assert(#errors==1,"stopped root tab retried")
end)
print(string.format("PASS %d native root-tab contract checks (not live-game evidence)",pass))
