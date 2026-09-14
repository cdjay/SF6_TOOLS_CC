package.path="autorun/?.lua;"..package.path
local Module=require("SF6CCTrainingLibrary/NativeReversalRecordings")
local INIT="app.training.UIFlowTrainingMenu_Reversal_Recording.Param:InitScrollList()"
local LIST="app.UIPartsScrollList:InitList(System.Int32, System.Int32, System.Int32)"
local UPDATE="app.training.UIFlowTrainingMenu_Reversal_Recording.Param:UpdateScrollList()"
local WRITE="app.helper.hGUI:setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])"
local function fixture()
    local id,hooks,tid,tls=0,{},1,{}
    local function obj(fields)
        id=id+1
        return {id=id,fields=fields or {},get_address=function(s)return s.id end,
            get_field=function(s,k)return s.fields[k] end,get_size=function(s)return s.size end,
            get_type_definition=function(s)return {get_full_name=function()return s.fields.type end}end,
            call=function(s,k,i)
                if k=="get_Name" then return s.fields.name end
                if k=="ToString" then return s.fields.text end
                if k=="get_Length" then return #s.fields.items end
                if k=="GetValue(System.Int32)" then return s.fields.items[i+1] end
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
    local entry={phase="active",manager=manager,data=data,fighter=obj({RecordSlots=bank}),array=bank}
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
        thread=function(n)tid=n end,allowed=function(v)enabled=v end,update=update,write=write,names=names}
end
local n=0
local function test(name,fn)fn(); n=n+1; print("PASS "..name)end

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
