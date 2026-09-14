package.path="autorun/?.lua;"..package.path
local Names=require("SF6CCTrainingLibrary/NativeRecordingNames")
local hooks,tls,serial={},{},0
local function obj(fields)
    serial=serial+1
    local o={id=serial,fields=fields or {}}
    function o:get_address() return self.id end
    function o:get_field(k) return self.fields[k] end
    function o:get_type_definition() return {get_method=function() return true end} end
    function o:call(k,i)
        if k=="get_Name" then return self.fields.name end
        if k=="get_Child" then return self.fields.child end
        if k=="get_Next" then return nil end
        if k=="get_Control" then return self.fields.control end
        if k=="GetChildren" then return self.fields.children.fields.items end
        if k=="GetChildCount" then return #self.fields.children.fields.items end
        if k=="GetChild(System.Int32)" then return self.fields.children.fields.items[i+1] end
        if k=="get_Count" then return #self.fields.items end
        if k=="get_Item" then return self.fields.items[i+1] end
        if k=="ToString" then return self.fields.text end
        error(k)
    end
    function o:get_size() return #self.fields.items end
    function o:get_element(i) return self.fields.items[i+1] end
    return o
end
local data,parent=obj(),obj()
local text=obj({name="e_txt_name"})
local group=obj({control=obj({child=obj({name="p_GroupItem_6",child=text})})})
local param=obj({_ViewDataList=obj({items={obj({Data=data,ParentData=parent})}}),
    _SecondaryList=obj({children=obj({items={group}})})})
local entry={phase="active",manager=obj({_UITrainingMenu=obj({_ParamData=param})}),
    menu={slot_info=function(d,p) if d==data and p==parent then return {slot=80,page=107} end end}}
local name="对空"
local library={slot_name=function(i) assert(i==80); return name end}
local errors={}
local api={find_type_definition=function() return {get_method=function(_,s) return s end} end,
    hook=function(s,a,b) hooks[s]={a,b} end,to_managed_object=function(x) return x end,
    to_int64=function(x) return type(x)=="table" and x.id or x end,to_ptr=function(x) return x end,
    create_managed_string=function(s) return obj({text=s}) end}
Names.new(api,{get_hook_storage=function() return tls end},function() return entry end,
    function() return true end,library,function(e) errors[#errors+1]=e end).install()
local discover=hooks["UpdateRecordSlotItem(app.UIPartsGroup, System.Int32)"]
local writer=hooks["setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])"]
local function write(target,source)
    local args={0,target,0,obj({text=source or "栏位<PLUNUM>"})}
    tls={}; assert(writer[1](args)==nil)
    local result=args[4]:call("ToString")
    assert(writer[2](99)==99)
    return result
end
discover[1]({0,param,group,0})
assert(write(text)=="<PLUNUM> 对空")
name="改名"; assert(write(text)=="<PLUNUM> 改名")
name="{0}"; assert(write(text)=="<PLUNUM> {{0}}")
name=""; assert(write(text)=="栏位<PLUNUM>")
name="对空"; assert(write(obj())=="栏位<PLUNUM>")
assert(write(text,"{0}帧")=="{0}帧")
local children=param.fields._SecondaryList.fields.children.fields.items
children[1]=obj()
assert(write(text)=="栏位<PLUNUM>","replaced native control must not receive old name")
children[1]=group
for i=1,100 do
    name=i%2==0 and "配置A" or "配置B"
    discover[1]({0,param,group,0})
    assert(write(text)=="<PLUNUM> "..name,"later imports/renames stopped updating")
end
local secondary=param.fields._SecondaryList
param.fields._SecondaryList=nil
assert(write(text)=="栏位<PLUNUM>","transient missing list must be ignored")
param.fields._SecondaryList=secondary
assert(write(text)=="<PLUNUM> "..name,"missing list permanently stopped name rendering")
param.fields._ViewDataList.fields.items[1].fields.Data=obj()
assert(write(text)=="栏位<PLUNUM>","stale row identity wrote a different slot")
assert(#errors==0)
print("PASS native slot names: child getters, slot80, 100 edits/imports, transient list, live ownership and foreign text")
