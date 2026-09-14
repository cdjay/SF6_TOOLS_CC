package.path="autorun/?.lua;"..package.path
local Pager=require("SF6CCTrainingLibrary/NativeRecordingPager")
local FUNCTION="Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
local VIEW="ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"
local ACTIVE="GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"
local MESSAGE="GetMessage(System.Guid)"
local FOCUS="GetFocusIndex(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"
local INDEX="GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)"
local TEXT="GetOptionText(app.training.TrainingFuncType)"
local SPIN="OnUpdateSpin()"
local function fixture(page_count)
    page_count=page_count or 2
    local hooks, tls, tid, updates, turns, reports={}, {}, 1, 0, 0, {}
    local selected=0
    local enabled=true
    local function obj(id,fields)
        return {get_address=function() return id end,get_field=function(_,key) return (fields or {})[key] end}
    end
    local data,parent,other=obj(1),obj(2),obj(3)
    local view_fields={Data=data,ParentData=parent,Index=0}
    local view=obj(4,view_fields)
    local focused=view
    local param=obj(7,{_SecondaryList={call=function() return 2 end},_ViewDataList={call=function(_,name,index)
        if name=="get_Count" then return 3 end
        return index==2 and focused or obj(90+index,{Index=0,Data=other,ParentData=parent}) end}})
    param.get_type_definition=function() return {get_full_name=function() return "app.training.UIFlowTrainingMenu.Param" end} end
    local ui=obj(5)
    local entry={phase="active",manager=obj(6,{_UIFunc=ui,_UITrainingMenu=obj(8,{_ParamData=param})})}
    entry.with_menu_navigation=function(owner,row,node,fn)
        assert(owner==ui and row==data and node==parent)
        return fn()
    end
    entry.menu={owns_pager=function(a,b) return a==data and b==parent end,
        navigate=function(a,b,index) assert(a==data and b==parent); turns=turns+1; selected=index; view_fields.Index=index; return true end,
        pager_info=function(row) if row==data then return {index=selected,count=page_count,label=tostring(selected+1).." / "..page_count} end end,
        text=function(key) if key=="01"..string.rep("00",15) then return "page "..turns end end}
    local api={PreHookResult={SKIP_ORIGINAL="skip"},
        find_type_definition=function() return {get_method=function(_,name) return name end} end,
        hook=function(name,pre,post) hooks[name]={pre,post} end,
        to_int64=function(x) return x end,to_ptr=function(x) return x end,
        to_managed_object=function(x) return x end,to_valuetype=function(x) return x end,
        create_managed_string=function(text) return {text=text,add_ref=function() end} end}
    local threads={get_id=function() return tid end,get_hook_storage=function() return tls end}
    local controller=Pager.new(api,threads,function() return entry end,function() return enabled end,
        function(err) reports[#reports+1]=err end)
    controller.install()
    local function call(name,args,body)
        if name==SPIN and not hooks[name] then if body then body() end; return nil,99 end
        local previous=tls; tls={}
        local h=assert(hooks[name]); local skip=h[1](args)
        if body then body() end
        local result=h[2](99); tls=previous
        return skip,result
    end
    local action=function(target,wanted)
        return call(FUNCTION,{0,ui,345,param,target or view,wanted or 1})
    end
    function ui:call(name,p,node,index)
        assert(name==VIEW and p==param and node==parent and index==0)
        updates=updates+1
        call(VIEW,{},function() action() end)
        return true
    end
    return {call=call,action=action,ui=ui,data=data,parent=parent,view=view,other=other,obj=obj,
        param=param,entry=entry,api=api,reports=reports,
        stats=function() return turns,updates end,
        commit=function(value) view_fields.Index=value end,
        selected=function() return selected end,
        focus=function(value) focused=value end,
        enabled=function(value) enabled=value end,thread=function(value) tid=value end}
end
local n=0
local function test(name,fn) fn(); n=n+1; print("PASS "..name) end
test("ten-page right arrow follows committed selection, not the following candidate query",function()
    local f=fixture(10)
    for selected=1,9 do
        f.call(SPIN,{0,f.param},function()
            local _,wanted=f.call(INDEX,{0,f.ui,345,selected,345})
            f.commit(wanted)
            f.call(INDEX,{0,f.ui,345,selected-1,345})
            f.call(INDEX,{0,f.ui,345,selected+1,345})
        end)
        assert(f.selected()==selected,"right arrow advanced two pages instead of one")
        local turns,updates=f.stats(); assert(turns==selected and updates==selected)
    end
    for selected=8,0,-1 do
        f.call(SPIN,{0,f.param},function()
            local _,wanted=f.call(INDEX,{0,f.ui,345,selected,345})
            f.commit(wanted)
            f.call(INDEX,{0,f.ui,345,selected-1,345})
            f.call(INDEX,{0,f.ui,345,selected+1,345})
        end)
        assert(f.selected()==selected,"left arrow did not follow committed selection")
    end
end)
test("candidate-only spin checks never turn a page",function()
    local f=fixture(10)
    f.call(SPIN,{0,f.param},function()
        f.call(INDEX,{0,f.ui,345,1,345})
        f.call(INDEX,{0,f.ui,345,9,345})
    end)
    assert(f.stats()==0,"availability queries are not committed arrow input")
end)
test("ten-page boundaries use the committed wrapped index",function()
    local f=fixture(10)
    for _,wanted in ipairs({0xFFFFFFFF,10}) do
        f.call(SPIN,{0,f.param},function()
            local _,value=f.call(INDEX,{0,f.ui,345,wanted,345})
            f.commit(value)
        end)
    end
    assert(f.selected()==0 and f.stats()==2)
end)
test("invalid or replaced native selection fails closed",function()
    for _,value in ipairs({-1,10,0.5,"1"}) do
        local f=fixture(10)
        f.call(SPIN,{0,f.param},function() f.commit(value) end)
        assert(f.stats()==0)
    end
    local f=fixture(10)
    f.call(SPIN,{0,f.param},function()
        f.focus(f.obj(82,{Data=f.data,ParentData=f.parent,Index=1}))
    end)
    assert(f.stats()==0,"a rebuilt ViewData is not the original input target")
end)
test("native arrow selection without button Function updates the slot page after spin returns",function()
    local f=fixture()
    f.call(SPIN,{0,f.param},function()
        local _,wanted=f.call(INDEX,{0,f.ui,345,1,345})
        assert(wanted==1)
        f.commit(wanted)
        assert(f.stats()==0,"do not rebuild inside the native spin setter")
    end)
    local turns,updates=f.stats()
    assert(turns==1 and updates==1,"page label changed but slot list stayed on page1")
end)
test("spin-owned layout queries cannot overwrite arrow intent or double apply Function",function()
    local f=fixture()
    f.call(SPIN,{0,f.param},function()
        f.call(INDEX,{0,f.ui,345,1,345})
        f.commit(1)
        f.call(VIEW,{0,f.ui,f.param,f.data,0},function()
            f.call(INDEX,{0,f.ui,345,0,345})
            f.action()
        end)
        assert(f.stats()==0)
    end)
    local turns,updates=f.stats(); assert(turns==1 and updates==1)
    f.call(SPIN,{0,f.param},function() f.call(INDEX,{0,f.ui,345,1,345}); f.commit(1) end)
    assert(f.stats()==1,"unchanged spin must not rebuild")
end)
test("foreign spin parameter and moved focus cannot rebuild an owned page",function()
    local f=fixture()
    f.call(SPIN,{0,f.other},function() f.call(INDEX,{0,f.ui,345,1,345}) end)
    assert(f.stats()==0)
    f.call(SPIN,{0,f.param},function()
        f.call(INDEX,{0,f.ui,345,1,345})
        f.focus(f.obj(21,{Data=f.other,ParentData=f.parent}))
    end)
    assert(f.stats()==0)
end)
test("spin scope never survives its callback or leaks across threads",function()
    local f=fixture()
    f.call(SPIN,{0,f.param},function()
        f.thread(2); f.call(INDEX,{0,f.ui,345,1,345}); f.thread(1)
    end)
    assert(f.stats()==0)
    f.call(INDEX,{0,f.ui,345,1,345}); assert(f.stats()==0)
    f.call(SPIN,{0,f.param},function() end); assert(f.stats()==0)
end)
test("spin rebuild failure disables navigation without repeated native calls",function()
    local f=fixture(); f.ui.call=function() error("native view rejected") end
    f.call(SPIN,{0,f.param},function() f.call(INDEX,{0,f.ui,345,1,345}); f.commit(1) end)
    assert(#f.reports==1 and f.stats()==1)
    f.call(SPIN,{0,f.param},function() f.call(INDEX,{0,f.ui,345,0,345}); f.commit(0) end)
    assert(#f.reports==1 and f.stats()==1)
end)
test("native spin change navigates once and rebuild cannot turn another page",function()
    local f=fixture(); local skip,result=f.action()
    assert(skip=="skip" and result==0)
    local turns,updates=f.stats(); assert(turns==1 and updates==1 and #f.reports==0)
end)
test("foreign dynamic rows and wrong parent pass through unchanged",function()
    local f=fixture()
    for _,fields in ipairs({{Data=f.other,ParentData=f.parent},{Data=f.data,ParentData=f.other}}) do
        local skip,result=f.action(f.obj(99,fields)); assert(skip==nil and result==99)
    end
    assert(f.stats()==0)
end)
test("foreign menu owner and native actions are never intercepted",function()
    local f=fixture()
    for _,args in ipairs({{0,f.other,345,f.param,f.view,0},{0,f.ui,118,f.param,f.view,0}}) do
        local skip,result=f.call(FUNCTION,args); assert(skip==nil and result==99)
    end
    assert(f.stats()==0)
end)
test("closed menu, inactive and released sessions cannot navigate",function()
    local f=fixture(); f.enabled(false); assert(f.action()==nil)
    f.enabled(true); f.entry.released=true; assert(f.action()==nil)
    f.entry.released=false; f.entry.phase="retired"; assert(f.action()==nil)
    assert(f.stats()==0)
end)
test("native layout invocation is not a user click",function()
    local f=fixture()
    f.call(VIEW,{},function() local skip,result=f.action(); assert(skip=="skip" and result==0) end)
    assert(f.stats()==0)
end)
test("navigation failure is contained, disables owned button and never retries",function()
    local f=fixture(); f.entry.menu.navigate=function() error("denied") end
    local skip,result=f.action(); assert(skip=="skip" and result==0 and #f.reports==1)
    f.action(); assert(#f.reports==1 and f.stats()==0)
    local a,b=f.call(ACTIVE,{0,f.ui,345,f.view}); assert(a=="skip" and b==0)
end)
test("view refresh failure does not escape or reenter",function()
    local f=fixture(); f.ui.call=function() error("refresh failure") end
    assert(f.action()=="skip"); assert(#f.reports==1 and f.stats()==1)
    f.action(); assert(f.stats()==1)
end)
test("only exact owned message GUID is replaced",function()
    local f=fixture()
    local function guid(first) return {read_byte=function(_,i) return i==0 and first or 0 end} end
    local skip,str=f.call(MESSAGE,{0,guid(1)}); assert(skip=="skip" and str.text=="page 0")
    local other,value=f.call(MESSAGE,{0,guid(2)}); assert(other==nil and value==99)
end)
test("message allocation failure is contained",function()
    local f=fixture(); f.api.create_managed_string=function() error("allocation") end
    local guid={read_byte=function(_,i) return i==0 and 1 or 0 end}
    local skip,value=f.call(MESSAGE,{0,guid}); assert(skip==nil and value==99)
    local a,b=f.call(TEXT,{0,f.ui,345}); assert(a==nil and b==99)
end)
test("left right indexes and label use only the currently focused owned spin",function()
    local f=fixture()
    local skip,wanted=f.call(INDEX,{0,f.ui,345,1,345}); assert(skip=="skip" and wanted==1)
    assert(f.stats()==0,"index query must not change pages")
    f.action(nil,wanted)
    local _,index=f.call(FOCUS,{0,f.ui,345,f.view}); assert(index==1)
    local _,label=f.call(TEXT,{0,f.ui,345}); assert(label.text=="2 / 2")
    local _,left=f.call(INDEX,{0,f.ui,345,0,345}); assert(left==0)
    f.action(nil,left); assert(f.stats()==2)
    f.focus(f.obj(20,{Index=4,Data=f.other,ParentData=f.parent}))
    local a,b=f.call(INDEX,{0,f.ui,345,1,345}); assert(a==nil and b==99)
    local c,d=f.call(TEXT,{0,f.ui,345}); assert(c==nil and d==99)
end)
test("layout index reads cannot reset a selected page or leak to another row",function()
    local f=fixture(); f.action()
    f.call(VIEW,{0,f.ui,f.param,f.data,0},function()
        local _,index=f.call(INDEX,{0,f.ui,345,0,345}); assert(index==1)
        local _,label=f.call(TEXT,{0,f.ui,345}); assert(label.text=="2 / 2")
        f.call(VIEW,{0,f.ui,f.param,f.other,0},function()
            local skip=f.call(TEXT,{0,f.ui,345}); assert(skip==nil)
        end)
        local _,again=f.call(TEXT,{0,f.ui,345}); assert(again.text=="2 / 2")
    end)
    assert(f.stats()==1)
end)
test("same index and out of range Function do not cycle or rebuild",function()
    local f=fixture(); f.action(nil,0); f.action(nil,2); assert(f.stats()==0)
    local _,wrapped=f.call(INDEX,{0,f.ui,345,0xFFFFFFFF,345}); assert(wrapped==1)
end)
print(n.." native pager hook cases passed (fake SDK; live UI acceptance separate)")
