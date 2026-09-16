package.path="autorun/?.lua;"..package.path
local Module=require("SF6CCTrainingLibrary/NativeReversalRecordings")
local INIT="app.training.UIFlowTrainingMenu_Reversal_Recording.Param:InitScrollList()"
local LIST="app.UIPartsScrollList:InitList(System.Int32, System.Int32, System.Int32)"
local UPDATE="app.training.UIFlowTrainingMenu_Reversal_Recording.Param:UpdateScrollList()"
local OVERVIEW="app.training.UIFlowTrainingMenu.Param:UpdateReversalItem(app.UIPartsGroup, System.Int32)"
local WRITE="app.helper.hGUI:setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])"
local function fixture()
    local id,hooks,tid,tls=0,{},1,{}
    local function obj(fields)
        id=id+1
        return {id=id,fields=fields or {},get_address=function(s)return s.id end,
            get_field=function(s,k)return s.fields[k] end,get_size=function(s)return s.size or #s.fields.items end,
            get_element=function(s,i)return s.fields.items[i+1] end,
            get_type_definition=function(s)return {get_full_name=function()return s.fields.type end}end,
            call=function(s,k,i)
                if k=="get_Name" then return s.fields.name end
                if k=="ToString" then return s.fields.text end
                if k=="get_Length" then return #s.fields.items end
                if k=="GetValue(System.Int32)" then return s.fields.items[i+1] end
                if k=="get_Count" then return #s.fields.items end
                if k=="get_Item" then return s.fields.items[i+1] end
                error(k)
            end}
    end
    local bank=obj(); bank.size=80
    local scroll=obj()
    local parent=obj()
    local param=obj({ParentParam=parent,_pScrollList=scroll})
    local menu=obj({_ParamData=param})
    parent.fields.RecordingMenu=menu
    local data=obj()
    local manager=obj({_tData=data,_UITrainingMenu_Reversal=obj({_ParamData=parent})})
    local overview_row=obj({_FuncType=137,_Type=8,_SlotID=0})
    local overview_parent=obj({_FuncType=134})
    local overview=obj({_ViewDataList=obj({items={obj({Data=overview_row,ParentData=overview_parent})}})})
    manager.fields._UITrainingMenu=obj({_ParamData=overview})
    local reversal=obj({Type=4,SkillIndex=0,IsValid=true,IsActive=true})
    local reversal_fighter=obj({FighterID=28})
    local reversals={reversal}
    for i,field in ipairs({"DownReversalDatas","GuardReversalDatas","DamageReversalDatas"}) do
        reversals[i]=reversals[i] or obj({Type=4,SkillIndex=-1,IsValid=true,IsActive=true})
        reversal_fighter.fields[field]=obj({items={reversals[i]}})
    end
    local fighters={}; for i=1,29 do fighters[i]=obj({FighterID=i-1}) end
    fighters[29]=reversal_fighter
    local setting=obj({ReversalType=0,FighterDataList=obj({items=fighters})})
    data.fields.ReversalSetting=setting
    local entry={phase="active",manager=manager,data=data,fighter=obj({RecordSlots=bank}),array=bank,fighter_id=28}
    local enabled=true
    local api={find_type_definition=function(name)return {get_method=function(_,sig)return name..":"..sig end} end,
        hook=function(m,pre,post) hooks[m]={pre,post} end,to_managed_object=function(v)return v end,
        to_int64=function(v)return v end,to_ptr=function(v)return v end,
        create_managed_string=function(s)return obj({text=s})end}
    local threads={get_id=function()return tid end,get_hook_storage=function()return tls end}
    local names={[9]="截空",[80]="反击"}
    Module.new(api,threads,function()return entry end,function()return enabled end,error,
        {slot_name=function(n)return names[n] or "" end}).install()
    local function update(p,fn)
        local old=tls; tls={}; assert(hooks[UPDATE],"reversal picker has no shared-name hook")
        hooks[UPDATE][1]({0,p or param}); local scope=tls
        fn(); tls=scope; hooks[UPDATE][2](99); tls=old
    end
    local function overview_update(p,index,fn)
        local old=tls; tls={}
        if hooks[OVERVIEW] then hooks[OVERVIEW][1]({0,p or overview,obj(),index or 0}) end
        local scope=tls
        fn(); tls=scope
        if hooks[OVERVIEW] then assert(hooks[OVERVIEW][2](99)==99) end
        tls=old
    end
    local function write(slot,control,source)
        local old=tls; tls={}
        local args={0,obj({name=control or "e_txt_name"}),0,obj({text=source or "栏位<PLUNUM>"}),
            obj({items={obj({text="305922504",type="System.Int32",mValue=slot})}})}
        hooks[WRITE][1](args); local result=args[4]:call("ToString")
        assert(hooks[WRITE][2](99)==99); tls=old; return result
    end
    local function enter(p)
        tls={}; hooks[INIT][1]({0,p or param})
        return tls
    end
    local function leave(storage) tls=storage; hooks[INIT][2](0) end
    local function list(target,count,focus)
        local args={0,target or scroll,count or 8,focus or 0,-1}
        hooks[LIST][1](args); hooks[LIST][2](0)
        return args
    end
    return {enter=enter,leave=leave,list=list,obj=obj,entry=entry,param=param,scroll=scroll,parent=parent,
        thread=function(n)tid=n end,allowed=function(v)enabled=v end,update=update,write=write,names=names,
        overview_update=overview_update,overview=overview,overview_row=overview_row,
        overview_parent=overview_parent,reversal=reversal,reversals=reversals,setting=setting,reversal_fighter=reversal_fighter}
end
local n=0
local function test(name,fn)fn(); n=n+1; print("PASS "..name)end

test("captured overview writer uses the edited recording name just like its picker",function()
    local f=fixture(); f.names[1]="对空练习"
    f.update(nil,function() assert(f.write(1)=="<PLUNUM> 对空练习") end)
    f.overview_update(nil,0,function()
        assert(f.write(1)=="<PLUNUM> 对空练习","overview kept default slot label while picker has edited name")
    end)
end)

test("all three overview groups resolve recording identity rather than reversal row number",function()
    local f=fixture()
    for group=0,2 do
        f.setting.fields.ReversalType=group
        f.overview_parent.fields._FuncType=134+group
        for _,slot in ipairs({9,80}) do
            f.reversals[group+1].fields.SkillIndex=slot-1
            f.overview_update(nil,0,function()
                assert(f.write(1)=="<PLUNUM> "..f.names[slot],"overview row1 must name its referenced recording")
                assert(f.write(2)=="栏位<PLUNUM>","foreign row format argument was renamed")
                assert(f.write(slot,"e_txt_center")=="栏位<PLUNUM>")
                assert(f.write(slot,nil,"空栏")=="空栏")
                assert(f.write(slot,nil,"55帧")=="55帧")
            end)
        end
    end
    f.reversals[3].fields.IsActive=false
    f.overview_update(nil,0,function() assert(f.write(1)=="<PLUNUM> 反击","disabled valid recording still has a name") end)
    f.names[80]="新说明"
    f.overview_update(nil,0,function() assert(f.write(1)=="<PLUNUM> 新说明") end)
    f.names[80]=""
    f.overview_update(nil,0,function() assert(f.write(1)=="栏位<PLUNUM>") end)
end)

test("overview resolves the row SlotID rather than its visible list position",function()
    local f=fixture()
    f.overview_row.fields._SlotID=1
    f.reversal_fighter.fields.DownReversalDatas.fields.items[2]=f.obj({Type=4,SkillIndex=79,IsValid=true})
    f.overview_update(nil,0,function() assert(f.write(2)=="<PLUNUM> 反击") end)
end)

test("overview parent selects the displayed group even when the global tab value is stale",function()
    local f=fixture()
    f.setting.fields.ReversalType=0
    f.overview_parent.fields._FuncType=135; f.reversals[2].fields.SkillIndex=8
    f.overview_update(nil,0,function() assert(f.write(1)=="<PLUNUM> 截空") end)
    f.overview_parent.fields._FuncType=136; f.reversals[3].fields.SkillIndex=79
    f.overview_update(nil,0,function() assert(f.write(1)=="<PLUNUM> 反击") end)
end)

for _,change in ipairs({"empty","normal","invalid","recording","row","type","func","fighter","group","session","bank","released","training"}) do
    test("overview rejects "..change.." without changing native text",function()
        local f=fixture(); f.names[1]="名称"
        if change=="empty" then f.reversal.fields.Type=-1; f.reversal.fields.SkillIndex=-1
        elseif change=="normal" then f.reversal.fields.Type=0
        elseif change=="invalid" then f.reversal.fields.IsValid=false
        elseif change=="recording" then f.reversal.fields.SkillIndex=80
        elseif change=="row" then f.overview_row.fields._SlotID=10
        elseif change=="type" then f.overview_row.fields._Type=0
        elseif change=="func" then f.overview_row.fields._FuncType=107
        elseif change=="fighter" then f.reversal_fighter.fields.FighterID=26
        elseif change=="group" then f.overview_parent.fields._FuncType=107
        elseif change=="session" then f.entry.manager.fields._tData=f.obj()
        elseif change=="bank" then f.entry.fighter.fields.RecordSlots=f.obj()
        elseif change=="released" then f.entry.released=true
        elseif change=="training" then f.allowed(false) end
        f.overview_update(nil,0,function() assert(f.write(1)=="栏位<PLUNUM>") end)
    end)
end

test("overview scope cannot leak into picker, nested foreign calls, threads or later controls",function()
    local f=fixture(); f.reversal.fields.SkillIndex=8
    f.overview_update(nil,0,function()
        assert(f.write(1)=="<PLUNUM> 截空")
        f.overview_update(f.obj(),0,function() assert(f.write(9)=="栏位<PLUNUM>") end)
        f.overview_update(nil,99,function() assert(f.write(9)=="栏位<PLUNUM>") end)
        assert(f.write(1)=="<PLUNUM> 截空")
        f.thread(2); assert(f.write(9)=="栏位<PLUNUM>"); f.thread(1)
        f.update(nil,function() assert(f.write(80)=="<PLUNUM> 反击") end)
        assert(f.write(1)=="<PLUNUM> 截空")
        f.reversal.fields.SkillIndex=79
        assert(f.write(9)=="栏位<PLUNUM>","changed recording reused previous name")
    end)
    assert(f.write(9)=="栏位<PLUNUM>","overview label survived after returning")
    f.update(nil,function()
        f.overview_update(f.obj(),0,function() assert(f.write(80)=="栏位<PLUNUM>") end)
        assert(f.write(80)=="<PLUNUM> 反击")
    end)
end)

test("overview read failure stops its own names without disabling the accepted picker",function()
    local f=fixture(); f.reversal.fields.SkillIndex=8
    local views=f.overview.fields._ViewDataList
    local original=views.call
    views.call=function() error("injected overview read failure") end
    f.overview_update(nil,0,function() assert(f.write(9)=="栏位<PLUNUM>") end)
    views.call=original
    f.overview_update(nil,0,function() assert(f.write(9)=="栏位<PLUNUM>") end)
    f.update(nil,function() assert(f.write(9)=="<PLUNUM> 截空") end)
end)

test("reversal recording picker uses current edited names including slot80",function()
    local f=fixture()
    f.update(nil,function()
        assert(f.write(9)=="<PLUNUM> 截空")
        assert(f.write(80)=="<PLUNUM> 反击")
        f.names[9]="新名称"; assert(f.write(9)=="<PLUNUM> 新名称")
        assert(f.write(1)=="栏位<PLUNUM>")
        assert(f.write(81)=="栏位<PLUNUM>")
        assert(f.write(0)=="栏位<PLUNUM>")
        assert(f.write(9.5)=="栏位<PLUNUM>")
        assert(f.write("9")=="栏位<PLUNUM>")
        assert(f.write(9,"e_txt_frame")=="栏位<PLUNUM>")
        assert(f.write(9,nil,"其他文字")=="其他文字")
    end)
    assert(f.write(9)=="栏位<PLUNUM>","name scope leaked outside native update")
end)

test("nested foreign reversal update and foreign threads cannot consume names",function()
    local f=fixture()
    f.update(nil,function()
        f.update(f.obj(),function() assert(f.write(9)=="栏位<PLUNUM>") end)
        assert(f.write(9)=="<PLUNUM> 截空")
        f.thread(2); assert(f.write(9)=="栏位<PLUNUM>"); f.thread(1)
        f.allowed(false); assert(f.write(9)=="栏位<PLUNUM>")
    end)
end)
test("native recording reversal initializes all eighty slots and preserves selected index",function()
    local f=fixture(); local s=f.enter(); local a=f.list(nil,8,79)
    assert(a[3]==80 and a[4]==79 and a[5]==-1,"reversal picker still initializes eight slots")
    f.leave(s); assert(f.list()[3]==8)
end)
test("unrelated list, foreign parent, thread and outside training are untouched",function()
    local f=fixture(); local s=f.enter()
    assert(f.list(f.obj())[3]==8)
    f.thread(2); assert(f.list()[3]==8); f.thread(1)
    assert(f.list(nil,10)[3]==10)
    f.allowed(false); assert(f.list()[3]==8); f.allowed(true)
    f.leave(s)
    s=f.enter(f.obj({ParentParam=f.parent})); assert(f.list()[3]==8); f.leave(s)
end)
for _,kind in ipairs({"released","retired","bank","data","parent","capacity"}) do
    test("changed "..kind.." prevents capacity substitution",function()
        local f=fixture(); local s=f.enter()
        if kind=="released" then f.entry.released=true
        elseif kind=="retired" then f.entry.phase="retired"
        elseif kind=="bank" then f.entry.fighter.fields.RecordSlots=f.obj()
        elseif kind=="data" then f.entry.manager.fields._tData=f.obj()
        elseif kind=="parent" then f.param.fields.ParentParam=f.obj()
        else f.entry.array.size=200 end
        assert(f.list()[3]==8); f.leave(s)
    end)
end
test("nested foreign initialization cannot inherit outer scope",function()
    local f=fixture(); local outer=f.enter(); local inner=f.enter(f.obj())
    assert(f.list()[3]==8); f.leave(inner)
    assert(f.list()[3]==80); f.leave(outer)
end)
print(n.." native reversal recording tests passed")
