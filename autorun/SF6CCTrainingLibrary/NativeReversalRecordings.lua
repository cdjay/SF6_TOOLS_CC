-- Adjust the game's own list initialization, only inside the owned recording picker.
local Layout = require("SF6CCTrainingLibrary/TrainingSlotLayout")
local Notes = require("SF6CCTrainingLibrary/TrainingConfigNotes")
local M = {}
local PARAM = "app.training.UIFlowTrainingMenu_Reversal_Recording.Param"
local function same(a, b) return a and b and a:get_address() == b:get_address() end

function M.new(api, threads, current, allowed, report, library)
    local scopes, name_scopes, names_stopped = {}, {}, false
    local function owned(param)
        if not allowed() then return end
        local entry = current()
        if not entry or entry.phase ~= "active" or entry.released
            or not same(entry.manager:get_field("_tData"), entry.data)
            or not same(entry.fighter:get_field("RecordSlots"), entry.array)
            or entry.array:get_size() ~= Layout.EXPANDED_RECORDS then return end
        local ui = entry.manager:get_field("_UITrainingMenu_Reversal")
        local parent = ui and ui:get_field("_ParamData")
        local menu = parent and parent:get_field("RecordingMenu")
        if param and menu and same(menu:get_field("_ParamData"), param)
            and same(param:get_field("ParentParam"), parent) then return entry end
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
        api.hook(writer, function(args)
            local storage = threads.get_hook_storage()
            storage.sf6cc_reversal_name_string = nil
            local frame = name_scopes[threads.get_id()]
            if names_stopped or not frame or not frame.param then return end
            local ok, err = pcall(function()
                if not owned(frame.param) then return end
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
                local name = library.slot_name(slot)
                if name == "" or not Notes.valid_note(name) then return end
                name = name:gsub("{", "{{"):gsub("}", "}}")
                local replacement = assert(api.create_managed_string("<PLUNUM> " .. name))
                storage.sf6cc_reversal_name_string = replacement
                args[4] = api.to_ptr(replacement)
            end)
            if not ok then names_stopped = true; pcall(report, tostring(err)) end
        end, function(retval)
            threads.get_hook_storage().sf6cc_reversal_name_string = nil
            return retval
        end)
    end
    return self
end
return M
