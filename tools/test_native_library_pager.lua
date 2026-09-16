package.path="autorun/?.lua;"..package.path
local Adapter=require("SF6CCTrainingLibrary/NativeLibraryPager")
local Spin=require("SF6CCTrainingLibrary/NativeRecordingPager")
local FOCUS="GetFocusIndex(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)"
local INDEX="GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)"
local TEXT="GetOptionText(app.training.TrainingFuncType)"
local ACTION="Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
local SPIN="OnUpdateSpin()"
local VIEW="ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"
local function fixture(reverse)
    local hooks,storage={},{}
    local function obj(fields)
        fields=fields or {}
        function fields:get_address() return self end
        function fields:get_field(key) return self[key] end
        return fields
    end
    local function list(items)
        return obj({get_size=function() return #items end,get_element=function(_,i) return items[i+1] end,
            call=function(_,name,i) if name=="get_Count" then return #items end; assert(name=="get_Item"); return items[i+1] end})
    end
    local root,row,ui=obj(),obj(),obj()
    local options={obj(),obj(),obj()}; row._ChildData=list(options)
    local item=obj({Data=row,ParentData=root,Index=0})
    local param=obj({_ViewDataList=list({item}),_SecondarySpinIndex=0,_SecondaryList={call=function() return 0 end}})
    function param:get_type_definition() return {get_full_name=function() return "app.training.UIFlowTrainingMenu.Param" end} end
    local manager=obj({_UIFunc=ui,_UITrainingMenu=obj({_ParamData=param})})
    local owner={page=root,pager=row,tm=manager}
    local page,turns,busy,active,live=0,0,false,true,owner
    local view={paging=function() return {index=page,count=3,label=(page+1).." / 3"} end,
        set_page=function(index) page=index; return true end}
    local api={PreHookResult={SKIP_ORIGINAL="skip"},find_type_definition=function()
        return {get_method=function(_,name) return name end} end,
        hook=function(name,pre,post)
            hooks[name]=hooks[name] or {}; table.insert(hooks[name],{pre,post})
        end,to_managed_object=function(x) return x end,to_int64=function(x) return x end,
        to_ptr=function(x) return x end,to_valuetype=function(x) return x end,
        create_managed_string=function(s) return {text=s,add_ref=function() end} end}
    local threads={get_hook_storage=function() return storage end,get_id=function() return 1 end}
    local library=Adapter.new(api,threads,function() return live end,view,function(p,change)
        assert(p==param and live==owner and not busy)
        assert(change()); turns=turns+1; item.IsUpdate=true; return true
    end,function() return live~=nil and active and not busy end,error,function() return busy end)
    -- The recording pager is active on the very same manager and hook methods,
    -- but must leave this library row and its return values alone.
    local recording_entry={phase="active",manager=manager,menu={
        owns_pager=function() return false end,pager_for_layout=function() end,text=function() end}}
    local recording=Spin.new(api,threads,function() return recording_entry end,function() return true end,error)
    if reverse then library.install(); recording.install() else recording.install(); library.install() end
    local function call(name,args,body)
        local previous=storage; storage={}; local skip
        for _,h in ipairs(assert(hooks[name])) do skip=h[1](args) or skip end
        if body then body() end
        local result=99
        for _,h in ipairs(hooks[name]) do result=h[2](result) end
        storage=previous; return skip,result
    end
    local function spin(wanted)
        call(SPIN,{0,param},function()
            local _,index=call(INDEX,{0,ui,345,wanted,345})
            item.Index=index
            call(INDEX,{0,ui,345,index+1,345})
            local child=obj({Data=options[index+1],ParentData=row})
            local skipped,result=call(ACTION,{0,ui,345,param,child,0})
            assert(skipped=="skip" and result==0)
            assert(item.IsUpdate and page==index,"library did not refresh in the committed native spin")
        end)
    end
    return {call=call,spin=spin,ui=ui,item=item,param=param,owner=owner,row=row,
        pager=library,stats=function() return page,turns end,busy=function(value) busy=value end,
        live=function(value) live=value end,active=function(value) active=value end}
end
for _,reverse in ipairs({false,true}) do
    local f=fixture(reverse)
    local skipped,value=f.call(FOCUS,{0,f.ui,345,f.item})
    assert(skipped=="skip" and value==0)
    for _,wanted in ipairs({1,2,1,0}) do
        f.spin(wanted)
        local _,text=f.call(TEXT,{0,f.ui,345}); assert(text.text==(wanted+1).." / 3")
    end
    assert(select(2,f.stats())==4)
    for _,data in ipairs({f.owner.page,f.row}) do
        f.call(VIEW,{0,f.ui,f.param,data,0},function()
            local _,index=f.call(INDEX,{0,f.ui,345,2,345})
            assert(index==0,"root/row initialization must not change the selected page")
        end)
    end
    -- Busy input cannot queue work or accidentally pass through a library row.
    f.busy(true); f.call(SPIN,{0,f.param},function() f.item.Index=1 end)
    f.pager.tick(); f.pager.tick(); assert(f.stats()==0)
    f.busy(false)
    -- A committed fallback is cancelled when the active presentation disappears.
    f.call(SPIN,{0,f.param},function() f.item.Index=1 end)
    f.live(nil); f.pager.tick(); f.live(f.owner); f.pager.tick()
    assert(f.stats()==0 and select(2,f.stats())==4)
    f.call(SPIN,{0,f.param},function() f.item.Index=1 end)
    f.pager.tick(); assert(f.stats()==0)
    f.pager.tick(); assert(f.stats()==1 and select(2,f.stats())==5)
end
print("PASS library native spin: recording-hook coexistence in both orders, immediate commit, busy and session cancellation")
