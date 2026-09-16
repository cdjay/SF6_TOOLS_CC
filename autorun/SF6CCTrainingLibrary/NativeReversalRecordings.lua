-- Extend the owned recording picker and substitute names in native reversal text.
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local Notes = require("SF6CCTrainingLibrary/TrainingConfigNotes")
local M = {}
local PARAM = "app.training.UIFlowTrainingMenu_Reversal_Recording.Param"
local OVERVIEW = "app.training.UIFlowTrainingMenu.Param"
local REVERSAL_GROUPS = { [134]="DownReversalDatas", [135]="GuardReversalDatas", [136]="DamageReversalDatas" }
local function same(a, b) return a and b and a:get_address() == b:get_address() end
local function read(obj, field) return obj and obj:get_field(field) end
local function integer(n, min, max) return type(n)=="number" and n%1==0 and n>=min and n<=max end

function M.new(api, threads, current, allowed, report, library)
    local scopes, name_scopes, names_stopped, overview_stopped = {}, {}, false, false
    local function active_entry()
        if not allowed() then return end
        local entry = current()
        if not entry or entry.phase ~= "active" or entry.released
            or not same(entry.manager:get_field("_tData"), entry.data)
            or not same(entry.fighter:get_field("RecordSlots"), entry.array)
            or entry.array:get_size() ~= Layout.EXPANDED_RECORDS then return end
        return entry
    end
    local function owned(param)
        local entry=active_entry(); if not entry then return end
        local ui = entry.manager:get_field("_UITrainingMenu_Reversal")
        local parent = ui and ui:get_field("_ParamData")
        local menu = parent and parent:get_field("RecordingMenu")
        if param and menu and same(menu:get_field("_ParamData"), param)
            and same(param:get_field("ParentParam"), parent) then return entry end
    end
    local function overview_slot(param,index)
        local entry=active_entry(); if not entry then return end
        if not same(param,read(read(entry.manager,"_UITrainingMenu"),"_ParamData")) then return end
        local views=read(param,"_ViewDataList")
        local count=views and views:call("get_Count")
        if not integer(count,1,20) or not integer(index,0,count-1) then return end
        local view=views:call("get_Item",index)
        local data=read(view,"Data")
        -- Captured native overview row identity, not recording page rows.
        if read(data,"_FuncType")~=137 or read(data,"_Type")~=8 then return end
        local row=read(data,"_SlotID")
        if not integer(row,0,Layout.NATIVE_REVERSALS-1) then return end
        local setting=read(entry.data,"ReversalSetting")
        local field=REVERSAL_GROUPS[read(read(view,"ParentData"),"_FuncType")]
        local fighters=read(setting,"FighterDataList")
        local n=fighters and fighters:call("get_Count")
        if not field or not integer(n,1,256) or not integer(entry.fighter_id,0,n-1) then return end
        local fighter=fighters:call("get_Item",entry.fighter_id)
        if read(fighter,"FighterID")~=entry.fighter_id then return end
        local values=read(fighter,field)
        local size=values and values:get_size()
        if not integer(size,1,Layout.NATIVE_REVERSALS) or row>=size then return end
        local reversal=values:get_element(row)
        -- RECORDING=4 was verified through live type/field inspection. An empty
        -- reversal also formats a slot number, so the text alone is not proof.
        if read(reversal,"Type")~=4 or read(reversal,"IsValid")~=true then return end
        local recording=read(reversal,"SkillIndex")
        if integer(recording,0,Layout.EXPANDED_RECORDS-1) then return recording+1,row+1 end
    end
    local self = {}
    function self.install()
        local function method(kind, signature)
            return assert(assert(api.find_type_definition(kind)):get_method(signature), signature)
        end
        local init = method(PARAM, "InitScrollList()")
        local list = method("app.UIPartsScrollList", "InitList(System.Int32, System.Int32, System.Int32)")
        api.hook(init, function(args)
            local id = threads.get_id()
            local frame = { previous = scopes[id] }
            scopes[id] = frame
            threads.get_hook_storage().sf6cc_reversal_init = frame
            local ok, err = pcall(function()
                local param = api.to_managed_object(args[2])
                if owned(param) then frame.param = param end
            end)
            if not ok then pcall(report, tostring(err)) end
        end, function(retval)
            local frame = threads.get_hook_storage().sf6cc_reversal_init
            if frame then scopes[threads.get_id()] = frame.previous end
            return retval
        end)
        api.hook(list, function(args)
            local frame = scopes[threads.get_id()]
            if not frame or not frame.param then return end
            local ok, err = pcall(function()
                if api.to_int64(args[3]) ~= Layout.NATIVE_RECORDS or not owned(frame.param) then return end
                local scroll = frame.param:get_field("_pScrollList")
                if same(api.to_managed_object(args[2]), scroll) then
                    args[3] = api.to_ptr(Layout.EXPANDED_RECORDS)
                end
            end)
            if not ok then pcall(report, tostring(err)) end
        end, function(retval) return retval end)
        if not library or type(library.slot_name) ~= "function" then return end
        local update = method(PARAM, "UpdateScrollList()")
        local writer = method("app.helper.hGUI",
            "setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])")
        api.hook(update, function(args)
            local id = threads.get_id()
            local frame = { previous = name_scopes[id] }
            name_scopes[id] = frame
            threads.get_hook_storage().sf6cc_reversal_names = frame
            if names_stopped then return end
            local ok, err = pcall(function()
                local param = api.to_managed_object(args[2])
                if owned(param) then frame.param = param end
            end)
            if not ok then names_stopped = true; pcall(report, tostring(err)) end
        end, function(retval)
            local frame = threads.get_hook_storage().sf6cc_reversal_names
            if frame then name_scopes[threads.get_id()] = frame.previous end
            return retval
        end)
        local overview=method(OVERVIEW,"UpdateReversalItem(app.UIPartsGroup, System.Int32)")
        api.hook(overview,function(args)
            local id=threads.get_id()
            local frame={previous=name_scopes[id],overview=true}
            name_scopes[id]=frame
            threads.get_hook_storage().sf6cc_reversal_overview=frame
            if overview_stopped then return end
            local ok,err=pcall(function()
                local param=api.to_managed_object(args[2])
                local index=api.to_int64(args[4]) & 0xFFFFFFFF
                local slot,ordinal=overview_slot(param,index)
                if slot then frame.param,frame.index,frame.slot,frame.ordinal=param,index,slot,ordinal end
            end)
            if not ok then overview_stopped=true; pcall(report,tostring(err)) end
        end,function(retval)
            local frame=threads.get_hook_storage().sf6cc_reversal_overview
            if frame then name_scopes[threads.get_id()]=frame.previous end
            return retval
        end)
        api.hook(writer, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_reversal_name_string = nil
            local frame = name_scopes[threads.get_id()]
            if not frame or not frame.param then return end
            if (frame.overview and overview_stopped) or (not frame.overview and names_stopped) then return end
            local ok, err = pcall(function()
                if frame.overview then
                    local slot,ordinal=overview_slot(frame.param,frame.index)
                    if slot~=frame.slot or ordinal~=frame.ordinal then return end
                elseif not owned(frame.param) then return end
                local text = api.to_managed_object(args[2])
                if not text or text:call("get_Name") ~= "e_txt_name" then return end
                local source = api.to_managed_object(args[4])
                source = source and source:call("ToString")
                if type(source) ~= "string" or not source:find("<PLUNUM>", 1, true) then return end
                -- Native UpdateScrollList formats the visible item's actual
                -- zero-based Index + 1, not its position on the current page.
                local values = api.to_managed_object(args[5])
                if not values or values:call("get_Length") ~= 1 then return end
                local value = values:call("GetValue(System.Int32)", 0)
                local slot = type(value) == "number" and value or nil
                -- Boxed Int32.ToString returns an unrelated value through this
                -- SDK binding. The captured native format argument stores mValue.
                if not slot and value and value:get_type_definition():get_full_name() == "System.Int32" then
                    slot = value:get_field("mValue")
                end
                if type(slot) ~= "number" or slot%1 ~= 0 or slot < 1 or slot > Layout.EXPANDED_RECORDS then return end
                -- Overview formats the reversal row ordinal, whereas the picker
                -- formats the recording number. Resolve the name from SkillIndex.
                if frame.overview and slot~=frame.ordinal then return end
                local name = library.slot_name(frame.overview and frame.slot or slot)
                if name == "" or not Notes.valid_note(name) then return end
                name = name:gsub("{", "{{"):gsub("}", "}}")
                local replacement = assert(api.create_managed_string("<PLUNUM> - " .. name))
                storage.sf6cc_reversal_name_string = replacement
                args[4] = api.to_ptr(replacement)
            end)
            if not ok then
                if frame.overview then overview_stopped=true else names_stopped=true end
                pcall(report, tostring(err))
            end
        end, function(retval)
            threads.get_hook_storage().sf6cc_reversal_name_string = nil
            return retval
        end)
    end
    return self
end
return M
