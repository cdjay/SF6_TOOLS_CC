package.path="autorun/?.lua;"..package.path
local fixture=require("tools.fixtures.native_recording_runtime")
local passed=0
local FUNCTION="Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
local ACTIVE="GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"
local function test(name,fn) fn(); passed=passed+1; print("PASS "..name) end
local function mount()
    local f=fixture({native_capacity=80})
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    f.ctx.menu_closed=false
    return f
end
test("ten pages reuse eight private rows without changing any original row",function()
    local f=fixture({native_capacity=80})
    local originals={f.pages[1].fields._ChildData,f.pages[2].fields._ChildData}
    f.runtime.install_hooks(); f.tick()
    assert(f.runtime.state()=="active",f.stats.error)
    f.ctx.menu_closed=false
    local bank=f.fighter.fields.RecordSlots
    local allocations=f.native_work.allocations
    local snapshots={}
    for i=0,79 do
        local slot=bank:get_element(i)
        slot.fields.Weight=i%5+1; slot.fields.IsActive=i%3==0
        local fields={}; for key,value in pairs(slot.fields) do fields[key]=value end
        local input={}; for j,value in ipairs(slot.fields.InputData.fields.buff.items) do input[j]=value end
        snapshots[i+1]={slot=slot,fields=fields,input=input}
    end
    for p=1,2 do
        local page=f.pages[p]
        local window=page.fields._ChildData
        assert(window:get_size()==12)
        local rows={}
        for i=1,8 do
            rows[i]=window:get_element(i)
            assert(rows[i]~=originals[p]:get_element(i),"original menu row must stay untouched")
        end
        for index=0,9 do
            f.arrow(p,index)
            assert(page.fields._ChildData==window,"page array must remain stable")
            assert(f.fighter.fields.RecordSlots==bank and bank:get_size()==80)
            for i=1,8 do
                local row=window:get_element(i)
                local slot=index*8+i
                assert(row==rows[i],"paging allocated/replaced a visible row")
                assert(row.fields._SlotID==slot-1)
                local info=f.session().menu.slot_info(row,page)
                assert(info and info.slot==slot and info.page==(p==1 and 107 or 108))
                assert(bank:get_element(row.fields._SlotID).fields.Frame==slot,"frame source binding")
                assert(originals[p]:get_element(i).fields._SlotID==i-1)
            end
            assert(window:get_element(10)==originals[p]:get_element(10))
            assert(window:get_element(11)==originals[p]:get_element(11))
        end
    end
    assert(f.native_work.allocations==allocations,"paging allocated native state")
    for i,snapshot in ipairs(snapshots) do
        local slot=bank:get_element(i-1)
        assert(slot==snapshot.slot)
        for key,value in pairs(snapshot.fields) do assert(slot.fields[key]==value,"changed recording "..key) end
        for j,value in ipairs(snapshot.input) do assert(slot.fields.InputData.fields.buff.items[j]==value) end
    end
    assert((f.native_work.view_updates or 0)==0,"must not invoke native view rebuild")
    f.ctx.allowed=false; f.tick()
    assert(f.pages[1].fields._ChildData==originals[1] and f.pages[2].fields._ChildData==originals[2])
end)
test("visible row refresh marks only owned view data and keeps focus",function()
    local f=mount()
    f.arrow(1,1,true)
    local param=f.manager.fields._UITrainingMenu.fields._ParamData
    local views=param.fields._ViewDataList
    local sentinel=f.obj({IsUpdate=false,Data=f.obj(),ParentData=f.obj()})
    views.items[#views.items+1]=sentinel
    local selected=views:get_element(1)
    local focus=selected.fields.Index
    f.ui_tick()
    assert(selected.fields.Index==focus and selected.fields.IsUpdate==true)
    for i=2,9 do assert(views:get_element(i).fields.IsUpdate==true,"slot redraw not requested") end
    assert(sentinel.fields.IsUpdate==false)
    assert((f.native_work.view_updates or 0)==0)
end)
test("record and play windows remember different pages",function()
    local f=mount()
    f.arrow(1,9); f.arrow(2,3)
    assert(f.read_page_focus(1)==9 and f.read_page_focus(2)==3)
    assert(f.pages[1].fields._ChildData:get_element(1).fields._SlotID==72)
    assert(f.pages[2].fields._ChildData:get_element(1).fields._SlotID==24)
end)
test("partial binding failure blocks every owned slot without further writes",function()
    local f=mount()
    local window=f.pages[1].fields._ChildData
    local target=window:get_element(3)
    local set=target.set_field
    function target:set_field(key,value)
        set(self,key,value)
        if key=="_SlotID" then error("injected rebind failure after write") end
    end
    f.arrow(1,1)
    assert((f.stats.error or ""):find("injected rebind failure",1,true))
    for i=1,8 do
        local row=window:get_element(i)
        assert(f.session().menu.slot_info(row,f.pages[1])==nil)
        assert(f.session().menu.command_active(row,f.pages[1])==false)
    end
    assert(f.session().menu.command_active(f.obj(),f.pages[1])==nil)
    assert(f.session().menu.command_active(f.pages[2].fields._ChildData:get_element(1),f.pages[2])==true)
    for p=1,2 do
        local page=f.pages[p]
        for i=1,8 do
            local view=f.obj({Data=page.fields._ChildData:get_element(i),ParentData=page})
            local kind=p==1 and 118 or 131
            local skip,result=f.hook_call(FUNCTION,{0,f.manager.fields._UIFunc,kind,nil,view,0})
            assert(skip=="skip" and result==0,"failed controller allowed owned command")
            local active,value=f.hook_call(ACTIVE,{0,f.manager.fields._UIFunc,kind,view})
            assert(active=="skip" and value==0,"failed controller reports enabled")
        end
    end
    local foreign=f.obj({Data=f.obj(),ParentData=f.pages[1]})
    local skip,result=f.hook_call(FUNCTION,{0,f.manager.fields._UIFunc,118,nil,foreign,0})
    assert(skip==nil and result==99,"failure intercepted foreign command")
    local ids={}; for i=1,8 do ids[i]=window:get_element(i).fields._SlotID end
    f.ui_tick(20)
    for i=1,8 do assert(ids[i]==window:get_element(i).fields._SlotID) end
end)

test("healthy record and playback commands fall through with the rebound slot ID",function()
    local f=mount()
    for p=1,2 do
        f.arrow(p,9)
        local page=f.pages[p]
        for i=1,8 do
            local row=page.fields._ChildData:get_element(i)
            local view=f.obj({Data=row,ParentData=page})
            local kind=p==1 and 118 or 131
            local skip,result=f.hook_call(FUNCTION,{0,f.manager.fields._UIFunc,kind,nil,view,0})
            assert(skip==nil and result==99 and row.fields._SlotID==71+i)
            local active,value=f.hook_call(ACTIVE,{0,f.manager.fields._UIFunc,kind,view})
            assert(active==nil and value==99,"must not override native recording eligibility")
        end
    end
end)

test("foreign view list is rejected before any dirty writes",function()
    local f=mount()
    local page,pager=f.pages[1],f.pages[1].fields._ChildData:get_element(0)
    local foreign=f.obj({Data=f.obj(),ParentData=page,IsUpdate=false})
    local param=f.obj({_ViewDataList=f.array({foreign})})
    local ok,err=pcall(function()
        f.session().with_menu_navigation(f.manager.fields._UIFunc,pager,page,function()
            f.session().menu.invalidate_view(param,pager,page)
        end)
    end)
    assert(not ok and tostring(err):find("does not own this pager",1,true),tostring(err))
    assert(not f.native_work.dirty_writes and foreign.fields.IsUpdate==false)
end)
test("foreign binding fields disable owned row commands and name resolution",function()
    for _,key in ipairs({"_SlotID","_Type","_FuncType","IsEnabled","IsCantFocus"}) do
        local f=mount()
        local page=f.pages[1]
        local row=page.fields._ChildData:get_element(1)
        row.fields[key]=999
        assert(f.session().menu.command_active(row,page)==false,"allowed changed "..key)
        assert(f.session().menu.slot_info(row,page)==nil,"name resolved changed "..key)
    end
end)

test("native name writer follows a reused row across all ten pages without stale labels",function()
    local f=mount()
    local Names=require("SF6CCTrainingLibrary/NativeRecordingNames")
    local prefix="config-A-"
    f.api.create_managed_string=function(value)
        local o=f.obj(); o.call=function(_,method) assert(method=="ToString"); return value end
        o.add_ref_permanent=function() end
        return o
    end
    Names.new(f.api,f.threads,f.session,function() return true end,
        {slot_name=function(slot) return prefix..slot end},function(err) error(err) end).install()
    for p=1,2 do
        local page,_,param=f.focus_page(p)
        local function node(name,child)
            local o=f.obj()
            o.call=function(_,method)
                if method=="get_Name" then return name end
                if method=="get_Child" then return child end
                assert(method=="get_Next"); return nil
            end
            o.set_field=function() error("name writer must not set GUI fields") end
            return o
        end
        local text=node(p==1 and "e_txt_name" or "e_text_name")
        local control=node("control",node(p==1 and "p_GroupItem_6" or "p_GroupItem_5",text))
        local group=f.obj(); group.call=function(_,method) assert(method=="get_Control"); return control end
        param.fields._SecondaryList.call=function(_,method,index)
            if method=="GetChildCount" then return param.fields._ViewDataList:get_size() end
            if method=="GetChild(System.Int32)" then assert(index==2); return group end
            assert(method=="GetFocusIndex"); return 1
        end
        local row=page.fields._ChildData:get_element(1)
        local pager=page.fields._ChildData:get_element(0)
        local function write(source)
            local args={0,text.id,0,f.api.create_managed_string(source or "slot<PLUNUM>")}
            f.hook_call("setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])",args)
            return args[4]:call("ToString")
        end
        for index=0,9 do
            f.session().with_menu_navigation(f.manager.fields._UIFunc,pager,page,function()
                assert(f.session().menu.navigate(pager,page,index))
            end)
            assert(page.fields._ChildData:get_element(1)==row)
            if index>0 then assert(write()=="slot<PLUNUM>","old GUI target wrote the previous slot name") end
            -- Simulate the engine calling its normal row writer, not a redraw.
            local method=p==1 and "UpdateRecordSlotItem" or "UpdatePlaySlotItem"
            f.hook_call(method.."(app.UIPartsGroup, System.Int32)",{0,param,group,2})
            assert(write()=="<PLUNUM> - "..prefix..(index*8+1))
            prefix=prefix=="config-A-" and "config-B-" or "config-A-"
            assert(write()=="<PLUNUM> - "..prefix..(index*8+1),"config change left stale name")
            assert(write("{0} frames")=="{0} frames","name writer replaced frame count")
        end
    end
end)

test("allocation count covers sixteen slot rows not 144 expanded slot rows",function()
    local f=mount()
    local count=0
    for _,o in pairs(f.objects) do
        if o.kind=="app.training.TrainingMenuData" and
            (o.fields._FuncType==118 or o.fields._FuncType==131) then count=count+1 end
    end
    assert(count==16,"unexpected native slot-row allocation count: "..count)
end)
print(passed.." fixed-window tests passed (fake SDK; native behavior unverified)")
