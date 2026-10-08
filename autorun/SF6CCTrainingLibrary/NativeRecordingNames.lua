-- Slot label source substitution on the game's own text writer. No GUI setters.
-- Follows the accepted SF6CCSlotLabelSmoke experiment without its C# dependency.
local Notes=require("SF6CCTrainingLibrary/TrainingConfigNotes")
local Ownership=require("SF6CCTrainingLibrary/NativeOwnership")
local M={}
local function same(a,b) return a and b and a:get_address()==b:get_address() end
local function read(o,k) return o and o:get_field(k) end
local function label(group,page)
    local control=group and group:call("get_Control")
    local node=control and control:call("get_Child")
    local template,seen=nil,{}
    local name=page==107 and "p_GroupItem_6" or "p_GroupItem_5"
    for _=1,32 do
        if not node then break end
        local id=node:get_address(); if seen[id] then return end; seen[id]=true
        if node:call("get_Name")==name then if template then return end; template=node end
        node=node:call("get_Next")
    end
    if not template then return end
    local work,cursor,result={template},1,nil
    seen={}
    while cursor<=#work and cursor<=32 do
        node=work[cursor]; cursor=cursor+1
        local id=node:get_address(); if seen[id] then return end; seen[id]=true
        if node:call("get_Name")== (page==107 and "e_txt_name" or "e_text_name") then
            if result then return end; result=node
        end
        local td=node:get_type_definition()
        local child=td:get_method("get_Child") and node:call("get_Child")
        local siblings={}
        while child do
            local key=child:get_address()
            if siblings[key] or #work>=32 then return end
            siblings[key]=true; work[#work+1]=child; child=child:call("get_Next")
        end
    end
    return result
end
function M.new(api,threads,current,allowed,library,report)
    local targets,owner,stopped={},nil,false
    local function context()
        if stopped or not allowed() then return end
        local entry=current()
        if not entry or entry.phase~="active" or entry.released then return end
        local manager=entry.manager
        local param=read(read(manager,"_UITrainingMenu"),"_ParamData")
        if not param then return end
        if owner~=param:get_address() then owner=param:get_address(); targets={} end
        return entry,param
    end
    local function row(entry,param,index)
        local list=read(param,"_ViewDataList")
        local count=list and list:call("get_Count")
        if type(count)~="number" or count>20 or index<0 or index>=count then return end
        local view=list:call("get_Item",index)
        local data,parent=read(view,"Data"),read(view,"ParentData")
        return entry.menu.slot_info(data,parent)
    end
    local function guard(fn)
        local ok,err=pcall(fn)
        if not ok then stopped=true; targets={}; pcall(report,"栏位名称显示暂停："..tostring(err)) end
    end
    local self={}
    function self.install()
        local td=assert(api.find_type_definition("app.training.UIFlowTrainingMenu.Param"))
        local record=assert(td:get_method("UpdateRecordSlotItem(app.UIPartsGroup, System.Int32)"))
        local play=assert(td:get_method("UpdatePlaySlotItem(app.UIPartsGroup, System.Int32)"))
        local writer=assert(assert(api.find_type_definition("app.helper.hGUI")):get_method(
            "setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])"))
        local function discover(args)
            guard(function()
                local entry,param=context()
                if not entry or not same(param,api.to_managed_object(args[2])) then return end
                local index=api.to_int64(args[4]) & 0xFFFFFFFF
                local info=row(entry,param,index); if not info then return end
                if library.slot_name(info.slot)=="" then return end
                local text=label(api.to_managed_object(args[3]),info.page); if not text then return end
                for id,t in pairs(targets) do if t.index==index then targets[id]=nil end end
                targets[text:get_address()]={index=index,slot=info.slot,page=info.page}
            end)
        end
        api.hook(record,discover,function(v) return v end)
        api.hook(play,discover,function(v) return v end)
        api.hook(writer,function(args)
            local storage=threads.get_hook_storage(); storage.sf6cc_slot_name_string=nil
            if stopped then return end
            local target=targets[api.to_int64(args[2])]; if not target then return end
            guard(function()
                local entry,param=context(); if not entry then return end
                local info=row(entry,param,target.index)
                if not info or info.page~=target.page or info.slot~=target.slot then return end
                local name=library.slot_name(info.slot)
                if name=="" or not Notes.valid_note(name) then return end
                local children=read(param,"_SecondaryList")
                local count=children and children:call("GetChildCount")
                if type(count)~="number" or count%1~=0 or count<0 or count>20 or target.index>=count then return end
                local text=label(children:call("GetChild(System.Int32)",target.index),info.page)
                if not text or text:get_address()~=api.to_int64(args[2]) then return end
                local source=api.to_managed_object(args[4])
                source=source and source:call("ToString")
                if type(source)~="string" or not source:find("<PLUNUM>",1,true) then return end
                -- Native formatting owns the number; braces in user input are
                -- escaped before the game's System.String.Format consumer.
                name=name:gsub("{","{{"):gsub("}","}}")
                local replacement=assert(Ownership.string(api,"<PLUNUM> - "..name))
                storage.sf6cc_slot_name_string=replacement
                args[4]=api.to_ptr(replacement)
            end)
        end,function(retval)
            threads.get_hook_storage().sf6cc_slot_name_string=nil
            return retval
        end)
    end
    return self
end
return M
