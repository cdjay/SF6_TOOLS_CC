-- SF6CC native recording-menu pilot: shared library backend, deferred operations.
-- Research build. Do not include in releases until real-game acceptance completes.
-- Revision 6: snapshot file lists; native navigation owns all visible rebuilds.
-- Native text technique adapted from Wael Hadjmouldi's MIT-licensed NativeOptions.
local State = require("SF6CCTrainingLibrary/State")
local Safety = require("SF6CCTrainingLibrary/Context")
local Library = require("SF6CCTrainingLibrary/Library").shared()
local NamePage = require("SF6CCTrainingLibrary/NativeRecordingNamePage")
local owner, tick, stopped, failed = nil, 0, false, false
local layout_depths = {}
local function in_layout() return (layout_depths[thread.get_id()] or 0) > 0 end
local option_templates = {}
local option_indices = {}
local texts, trace_count = {}, 0
local RECORD, SELECTOR, RECORD_PAGE, PLAY_PAGE, DYNAMIC = 4, 106, 107, 108, 345
local VIEW_UPDATE = "ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)"
local FILES_PER_PAGE = 8
local function trace(message)
    if trace_count >= 16 then return end
    trace_count = trace_count + 1
    log.info("[NativeLibraryPilot] " .. message)
end
local function read(obj, field)
    return obj and obj:get_field(field) or nil
end
local function address(obj) return obj and obj:get_address() or nil end
local function method(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    local result = td and td:get_method(signature)
    assert(result, "Missing native signature: " .. type_name .. "." .. signature)
    return result
end
local function arr(items)
    local result = sdk.create_managed_array("app.training.TrainingMenuData", #items)
    assert(result, "Could not allocate menu array")
    result:add_ref()
    for i, obj in ipairs(items) do result:call("SetValue", obj, i - 1) end
    return result
end
local function guid_key(guid)
    local bytes = {}
    for i = 0, 15 do bytes[#bytes + 1] = string.format("%02x", guid:read_byte(i)) end
    return table.concat(bytes)
end
local function message(value)
    local guid = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    local key = guid_key(guid)
    assert(key ~= string.rep("0", 32) and texts[key] == nil, "Invalid or duplicate custom GUID")
    texts[key] = value
    return guid
end
local function menu_data(item_type, title, enabled, children, guide, read_only)
    local obj = sdk.create_instance("app.training.TrainingMenuData")
    assert(obj, "Could not allocate menu data")
    obj:add_ref()
    obj:set_field("_Type", item_type)
    obj:set_field("_FuncType", DYNAMIC)
    obj:set_field("IsEnabled", enabled)
    -- Visibility/activity is separate from navigation: informational rows stay drawn.
    obj:set_field("IsCantFocus", read_only == true or not enabled)
    obj:set_field("IsNotFocusFunc", false)
    obj:set_field("_Interval", 1)
    obj:set_field("_Interval_Option", 1)
    obj:set_field("_GuidIcon", -1)
    obj:set_field("_GuidAddIcon", -1)
    obj:set_field("VisibleCase", 0)
    local title_guid, guide_guid = message(title), message(guide or "")
    obj:call("set_MessageID(System.Guid)", title_guid)
    obj:call("set_GuideMessage(System.Guid)", guide_guid)
    -- Validate detached objects before exposing them to native menu construction.
    assert(guid_key(read(obj, "_MessageID")) == guid_key(title_guid), "Title GUID setter did not round-trip")
    assert(guid_key(read(obj, "_GuideMessage")) == guid_key(guide_guid), "Guide GUID setter did not round-trip")
    obj:set_field("_ChildData", arr(children or {}))
    return obj
end
local function current_manager()
    return sdk.get_managed_singleton("app.training.TrainingManager")
end
local function current_selector(tm)
    if not tm or read(tm, "_IsInit") ~= true then return nil end
    local ui = read(tm, "_UIData")
    local tabs = read(ui, "_MenuData")
    if not tabs then return nil end
    for i = 0, math.min(tabs:get_size(), 16) - 1 do
        local tab = tabs:get_element(i)
        if tonumber(read(tab, "_FuncType")) == RECORD then
            local children = read(tab, "_ChildData")
            if not children or children:get_size() ~= 1 then return nil end
            local selector = children:get_element(0)
            if tonumber(read(selector, "_FuncType")) ~= SELECTOR
                or tonumber(read(selector, "_Type")) ~= 18 then return nil end
            return selector, ui
        end
    end
end
local function owned_menu_call(args)
    if not owner or stopped then return false end
    return sdk.to_managed_object(args[2]) == read(owner.tm, "_UIFunc")
end
local function owned_view(ptr)
    if not owner then return nil end
    local view = sdk.to_managed_object(ptr)
    local data = read(view, "Data")
    if owner.name_browser and owner.name_browser.owns(data,read(view,"ParentData")) then return "name_item" end
    if data == owner.page then return "page" end
    local index = option_indices[address(data)]
    if index and index <= #owner.picker_entries then return "file", index end
    return owner.kinds[address(data)]
end
local function refresh_library_page(ptr, target)
    local current = owner
    if not current or current.refreshing then return end
    current.refreshing = true
    local ok, detail = pcall(function()
        local param = assert(sdk.to_managed_object(ptr), "Missing native menu parameter")
        assert(param:get_type_definition():get_full_name() == "app.training.UIFlowTrainingMenu.Param",
            "Unexpected native menu parameter type")
        -- Original Record/Play Function calls use this UI-only body update path.
        local page = target or (current.name_browser and current.name_browser.current())
            or (current.picker_index and current.picker_pages[current.picker_index].data) or current.page
        local updated = read(current.tm, "_UIFunc"):call(VIEW_UPDATE, param, page, 0)
        assert(updated == true, "Native page update did not succeed")
        if current.visible_param ~= param then param:add_ref() end
        current.visible_param = param
        current.drawn_selection, current.drawn_revision = Library.selected, Library.revision
    end)
    current.refreshing = false
    if ok then trace("Library body updated through native ViewUpdate.")
    else
        current.visible_param = nil
        trace("Library body update failed: " .. tostring(detail))
    end
    return ok
end
local function library_page_visible(param)
    local views = read(param, "_ViewDataList")
    local count = views and tonumber(views:call("get_Count"))
    if not count or count < 1 or count > 64 then return false end
    for i = 0, count - 1 do
        local view = views:call("get_Item", i)
        local data, parent = read(view, "Data"), read(view, "ParentData")
        if owner.name_browser and owner.name_browser.owns(data,parent) then return true end
        local picker = owner.picker_index and owner.picker_pages[owner.picker_index]
        if picker and parent == picker.data and (owner.kinds[address(data)] or option_indices[address(data)]) then return true end
        if data == owner.choice and parent == owner.page then return true end
        local index = option_indices[address(data)]
        if index and index <= #owner.picker_entries and (parent == owner.choice or parent == owner.page) then return true end
    end
    return false
end
local function restore()
    if not owner then return end
    local tm = current_manager()
    -- Never write through a cached object from a different scene/manager.
    if tm == owner.tm and read(tm, "_UIData") == owner.ui
        and read(owner.selector, "_ChildData") == owner.installed then
        owner.selector:set_field("_ChildData", owner.original)
        if tonumber(read(owner.selector, "_Type")) == 19 then
            owner.selector:set_field("_Type", owner.original_type)
        end
        trace("Original recording page array and layout restored.")
    end
    owner = nil
    Library.cancel()
end
local function build_picker_pages()
    -- Titles, rows and click targets share one catalog until explicit navigation.
    local entries = {}
    for i, entry in ipairs(Library.entries) do
        entries[i] = { path = entry.path, filename = entry.filename, label = Library.selection_label(i) }
    end
    owner.picker_entries = entries
    owner.revision = Library.revision
    local pages = math.max(1, math.ceil(#entries / FILES_PER_PAGE))
    owner.picker_count = pages
    for p = 1, pages do
        local page_index = p
        local cached = owner.picker_pages[p]
        if not cached then
            cached = { arrays = {} }
            cached.header = menu_data(0, function()
                return "选择配置（" .. page_index .. "/" .. owner.picker_count .. "，共 " .. #owner.picker_entries .. " 个）"
            end, true, nil, nil, true)
            cached.back = menu_data(0, "返回", true)
            cached.previous = menu_data(0, "上一页", true)
            cached.next = menu_data(0, "下一页", true)
            cached.data = menu_data(22, "选择配置", true)
            owner.kinds[address(cached.header)], owner.kinds[address(cached.back)] = "detail", "picker_back"
            owner.kinds[address(cached.previous)], owner.kinds[address(cached.next)] = "picker_previous", "picker_next"
            owner.kinds[address(cached.data)] = "picker_page"
            owner.picker_pages[p] = cached
        end
        local rows = { cached.header }
        for i = (p - 1) * FILES_PER_PAGE + 1, math.min(p * FILES_PER_PAGE, #entries) do
            local index = i
            if not option_templates[i] then
                option_templates[i] = menu_data(0, function()
                    local entry = owner.picker_entries[index]
                    local selected = Library.selection()
                    local marker = entry and selected and selected.path == entry.path
                        and (owner.armed_path == entry.path and "【再次确认切换】" or "【已选】") or ""
                    return marker .. index .. ". "
                        .. (entry and entry.label or "")
                end, true, nil, "切换将导入此配置，丢弃当前未保存的修改。")
                option_indices[address(option_templates[i])] = i
            end
            rows[#rows + 1] = option_templates[i]
        end
        if p > 1 then rows[#rows + 1] = cached.previous end
        if p < pages then rows[#rows + 1] = cached.next end
        rows[#rows + 1] = cached.back
        -- Reuse native arrays across refreshes instead of accumulating refs.
        local key = #rows .. ":" .. tostring(p < pages)
        if not cached.arrays[key] then cached.arrays[key] = arr(rows) end
        cached.data:set_field("_ChildData", cached.arrays[key])
    end
end
local function install(tm)
    local selector, ui = current_selector(tm)
    if not selector then return end
    local original = read(selector, "_ChildData")
    -- Unknown layouts or another mod's extension are left untouched.
    if not original or original:get_size() ~= 2 then return end
    local first, second = original:get_element(0), original:get_element(1)
    if tonumber(read(first, "_FuncType")) ~= RECORD_PAGE
        or tonumber(read(second, "_FuncType")) ~= PLAY_PAGE then return end
    if not Library.loaded then Library.refresh() end
    local choice = menu_data(0, function() return "切换训练配置：" .. Library.selection_label() end, true)
    local export = menu_data(0, "导出当前配置", true, nil, "导出 P2 录像栏位、反击设置及注释。")
    local refresh = menu_data(0, "刷新配置列表", true)
    local save = menu_data(0, "保存当前配置", true, nil, "更新选中的配置文件，保存全部录像栏位及三类反击；覆盖前备份原文件。")
    local status = menu_data(0, function() return Library.status_ok and "结果：" .. Library.status or "注意：" .. Library.status end,
        true, nil, function() return Library.status end, true)
    local details = {}
    local note_editor = State.editor
    for _, field in ipairs({ { "file", "文件：" }, { "character", "角色：" }, { "saved", "保存时间：" },
        { "slots", "栏位：" }, { "notes", "备注：" } }) do
        local key, prefix = field[1], field[2]
        local edit_note = key == "notes" and note_editor ~= nil
        details[#details + 1] = menu_data(0, function()
            if edit_note then return "修改训练配置名称" end
            return prefix .. Library.selection_details()[key]
        end, true, nil, nil, not edit_note)
    end
    local edit_separator = menu_data(4, "", true, nil, nil, true)
    local info_separator = menu_data(4, "", true, nil, nil, true)
    local rows = { choice, save, export, refresh, edit_separator, details[5] }
    local page = menu_data(22, "导入导出", true)
    local installed = arr({ first, second, page })
    -- Keep the detached original array alive for restoration on script reset.
    original:add_ref()
    owner = { tm = tm, ui = ui, selector = selector, original = original,
        record_page = first, play_page = second, library_selected = false,
        installed = installed, page = page, choice = choice, revision = Library.revision,
        picker_pages = {}, picker_entries = {}, picker_count = 1,
        kinds = { [address(choice)] = "choice", [address(export)] = "export",
            [address(refresh)] = "refresh", [address(status)] = "status", [address(save)] = "save" },
        original_type = tonumber(read(selector, "_Type")) }
    for _, item in ipairs(details) do owner.kinds[address(item)] = "detail" end
    owner.kinds[address(edit_separator)], owner.kinds[address(info_separator)] = "detail", "detail"
    if note_editor then owner.kinds[address(details[5])] = "notes" end
    if note_editor and Library.can_edit_slot_names() then
        local names=menu_data(0,"修改栏位名称",true,nil,"选择固定栏位改名；导出配置后保留。")
        owner.kinds[address(names)]="names"
        owner.name_browser=NamePage.new(menu_data,arr,Library,note_editor)
        rows[#rows + 1] = names
    end
    for _, item in ipairs({ info_separator, details[1], details[2], details[3], details[4], status }) do
        rows[#rows + 1] = item
    end
    page:set_field("_ChildData", arr(rows))
    build_picker_pages()
    selector:set_field("_ChildData", installed)
    -- The captured prefab has separate two/three-item views at ItemType 18/19.
    -- Keep FuncType=106 so this remains the recording selector, not reversal settings.
    selector:set_field("_Type", 19)
    trace("Revision 6 installed: snapshot file list; original record/play tabs unchanged.")
end

local ok, err = pcall(function()
    -- Resolve all mandatory methods before installing any hook or menu object.
    local index_method = method("app.training.TrainingMenuFunc",
        "GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)")
    local function_method = method("app.training.TrainingMenuFunc",
        "Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)")
    local active_method = method("app.training.TrainingMenuFunc",
        "GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)")
    local focus_method = method("app.training.TrainingMenuFunc",
        "GetFocusIndex(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)")
    local change_method = method("app.training.tf_RecordSetting.FuncData",
        "ChangeRecordSetting(app.training.RECORD_TYPE)")
    local message_method = method("app.helper.hMsg", "GetMessage(System.Guid)")
    local view_method = method("app.training.TrainingMenuFunc", VIEW_UPDATE)
    local cancel_method = method("app.training.UITrainingMenu", "OnCancelStart()")

    sdk.hook(view_method, function(args)
        local id=thread.get_id()
        layout_depths[id]=(layout_depths[id] or 0)+1
    end, function(retval)
        local id=thread.get_id()
        local depth=(layout_depths[id] or 1)-1
        layout_depths[id]=depth>0 and depth or nil
        return retval
    end)

    sdk.hook(message_method, function(args)
        local storage = thread.get_hook_storage()
        storage.sf6cc_library_text = nil
        if stopped then return end
        local success, value = pcall(function()
            -- ValueType ToString aliases distinct GUIDs on this game/bridge build.
            local text = texts[guid_key(sdk.to_valuetype(args[2], "System.Guid"))]
            if type(text) == "function" then text = text() end
            if text ~= nil then
                text = tostring(text):gsub("[%c<>]", " ")
                local n = utf8.len(text)
                if not n then return "?" end
                if n > 90 then text = text:sub(1, utf8.offset(text, 91) - 1) .. "..." end
            end
            return text
        end)
        if success and value ~= nil then
            storage.sf6cc_library_text = value
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        local value = thread.get_hook_storage().sf6cc_library_text
        if value ~= nil then
            local str = sdk.create_managed_string(value)
            -- The game and Lua each release one reference to a returned string.
            str:add_ref()
            return sdk.to_ptr(str)
        end
        return retval
    end)

    sdk.hook(index_method, function(args)
        local storage = thread.get_hook_storage()
        storage.sf6cc_library_index = nil
        if not owned_menu_call(args) then return end
        local ft = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local wanted = sdk.to_int64(args[4]) & 0xFFFFFFFF
        if ft ~= SELECTOR then return end
        if wanted == 2 then
            storage.sf6cc_library_index = 2
            trace("Third UI tab requested; native RecordType left unchanged.")
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        -- 0/1 keep the original function and its normal effects unchanged.
    end, function(retval)
        local index = thread.get_hook_storage().sf6cc_library_index
        if index ~= nil then return sdk.to_ptr(index) end
        return retval
    end)

    sdk.hook(function_method, function(args)
        local storage = thread.get_hook_storage()
        storage.sf6cc_library_result = nil
        if not owned_menu_call(args) then return end
        local ft = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local data = read(sdk.to_managed_object(args[5]), "Data")
        if (ft == RECORD_PAGE and data == owner.record_page) or (ft == PLAY_PAGE and data == owner.play_page) then
            owner.library_selected, owner.visible_param = false, nil
            owner.picker_index, owner.armed_path = nil, nil
            if owner.name_browser then owner.name_browser.close() end
        end
        local kind, option_index
        if ft == DYNAMIC then kind, option_index = owned_view(args[5]) end
        if kind
            or (ft == SELECTOR and (sdk.to_int64(args[6]) & 0xFFFFFFFF) == 2) then
            storage.sf6cc_library_result = 0
            local success, detail = pcall(function()
                if kind == "page" then
                    if owner.refreshing or in_layout() then return end
                    owner.picker_index = nil
                    if owner.name_browser then owner.name_browser.close() end
                    owner.library_selected = true
                    owner.armed_path = nil
                    refresh_library_page(args[4])
                elseif kind == "names" or kind == "name_item" then
                    if in_layout() or owner.refreshing or Library.has_pending() then return end
                    owner.armed_path=nil
                    if kind=="names" then
                        owner.picker_index=nil
                        owner.name_browser.open()
                    else
                        local v=sdk.to_managed_object(args[5])
                        local _,close=owner.name_browser.handle(read(v,"Data"),read(v,"ParentData"))
                        if close then storage.sf6cc_library_result=1; return end
                    end
                    refresh_library_page(args[4])
                elseif kind == "choice" then
                    if in_layout() or owner.refreshing or Library.has_pending() then return end
                    owner.armed_path = nil
                    if owner.revision ~= Library.revision then build_picker_pages() end
                    owner.picker_revision = Library.revision
                    owner.picker_index = math.min(owner.picker_count, math.floor((Library.selected - 1) / FILES_PER_PAGE) + 1)
                    if not refresh_library_page(args[4]) then owner.picker_index = nil end
                elseif kind == "file" or kind == "picker_back" or kind == "picker_previous" or kind == "picker_next" then
                    if in_layout() or owner.refreshing or not owner.picker_index or Library.has_pending() then return end
                    if owner.picker_revision ~= Library.revision then
                        owner.picker_index, owner.armed_path = nil, nil
                    elseif kind == "file" then
                        if math.floor((option_index - 1) / FILES_PER_PAGE) + 1 ~= owner.picker_index then return end
                        local view = sdk.to_managed_object(args[5])
                        if read(view, "ParentData") ~= owner.picker_pages[owner.picker_index].data then return end
                        local entry = owner.picker_entries[option_index]
                        local selected = Library.selection()
                        local confirmed = entry and selected and owner.armed_path == entry.path and selected.path == entry.path
                        if not Library.select(option_index) then return end
                        if confirmed then
                            owner.picker_index, owner.armed_path = nil, nil
                            if Library.request("import") then storage.sf6cc_library_result = 1; return end
                        else
                            owner.armed_path = entry.path
                        end
                    elseif kind == "picker_back" then owner.picker_index, owner.armed_path = nil, nil
                    else
                        owner.armed_path = nil
                        local next_page = owner.picker_index + (kind == "picker_next" and 1 or -1)
                        if next_page < 1 or next_page > owner.picker_count then return end
                        owner.picker_index = next_page
                    end
                    refresh_library_page(args[4])
                elseif kind == "notes" then
                    owner.armed_path = nil
                    local editor = State.editor
                    if editor and editor.request() then storage.sf6cc_library_result = 1
                    else refresh_library_page(args[4]) end
                elseif kind == "export" or kind == "refresh" or kind == "save" then
                    owner.armed_path = nil
                    if Library.request(kind) then storage.sf6cc_library_result = 1 end
                end
                if (kind == "export" or kind == "refresh" or kind == "save")
                    and storage.sf6cc_library_result == 0 then refresh_library_page(args[4]) end
            end)
            if not success then
                Library.cancel()
                Library.status_ok, Library.status = false, "菜单操作失败，详细原因见日志"
                trace("Menu action failed: " .. tostring(detail))
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        local result = thread.get_hook_storage().sf6cc_library_result
        if result ~= nil then return sdk.to_ptr(result) end
        return retval
    end)

    -- Page construction reads this getter, not a child-row ViewUpdate. It must
    -- rebuild the selector from shared state without changing that state.
    sdk.hook(focus_method, function(args)
        local storage = thread.get_hook_storage()
        storage.sf6cc_library_focus = nil
        if not owned_menu_call(args) then return end
        local ft = sdk.to_int64(args[3]) & 0xFFFFFFFF
        local view = sdk.to_managed_object(args[4])
        if ft == SELECTOR and read(view, "Data") == owner.selector and owner.library_selected then
            storage.sf6cc_library_focus = 2
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
        if ft == DYNAMIC and owned_view(args[4]) == "choice" then
            storage.sf6cc_library_focus = 0
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        local index = thread.get_hook_storage().sf6cc_library_focus
        if index ~= nil then return sdk.to_ptr(index) end
        return retval
    end)

    -- Intercept only our visible subpage's normal native Back event. No flow is
    -- force-ended and no game menu is opened by this pilot.
    sdk.hook(cancel_method, function(args)
        if not owner or stopped or not owner.visible_param
            or (not owner.picker_index and not (owner.name_browser and owner.name_browser.current())) then return end
        local ok, handled = pcall(function()
            local tm = current_manager()
            if tm ~= owner.tm or read(tm, "_UIData") ~= owner.ui
                or read(owner.selector, "_ChildData") ~= owner.installed
                or sdk.to_managed_object(args[2]) ~= read(tm, "_UITrainingMenu")
                or not library_page_visible(owner.visible_param) then return false end
            owner.picker_index, owner.armed_path = nil, nil
            if owner.name_browser then owner.name_browser.close() end
            return refresh_library_page(owner.visible_param)
        end)
        if ok and handled then return sdk.PreHookResult.SKIP_ORIGINAL end
    end, function(retval) return retval end)

    sdk.hook(active_method, function(args)
        local storage = thread.get_hook_storage()
        storage.sf6cc_library_active = nil
        if not owned_menu_call(args) or (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= DYNAMIC then return end
        local kind = owned_view(args[4])
        if kind then
            local v=sdk.to_managed_object(args[4])
            storage.sf6cc_library_active = kind=="name_item"
                and (owner.name_browser.active(read(v,"Data"),read(v,"ParentData")) and 1 or 0) or 1
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        local active = thread.get_hook_storage().sf6cc_library_active
        if active ~= nil then return sdk.to_ptr(active) end
        return retval
    end)

    -- Backstop: this pilot's UI-only index must never reach the native recorder.
    sdk.hook(change_method, function(args)
        if not owner or stopped or (sdk.to_int64(args[3]) & 0xFFFFFFFF) ~= 2 then return end
        local rec_func = sdk.to_managed_object(args[2])
        if read(rec_func, "_tData") == read(owner.tm, "_tData") then
            trace("Blocked UI-only mode from ChangeRecordSetting.")
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval) return retval end)
end)
if not ok then
    failed = true
    log.error("[NativeLibraryPilot] Disabled before installation: " .. tostring(err))
end

re.on_pre_application_entry("LateUpdateBehavior", function()
    if failed or stopped then return end
    tick = tick + 1
    if tick % 30 ~= 0 then return end
    local success, detail = pcall(function()
        if not Safety.is_training_allowed() then restore(); return end
        local tm = current_manager()
        if Safety.pause_open() == true and owner and tm == owner.tm
            and read(tm, "_UIData") == owner.ui and read(owner.selector, "_ChildData") == owner.installed then
            if owner.drawn_selection ~= Library.selected or owner.drawn_revision ~= Library.revision then
                owner.armed_path = nil
            end
            -- A cached Param is not permission to rebuild native widgets here.
            -- ViewUpdate reaches native list/spin rebuilding and has crashed
            -- outside native navigation. Adopt shared changes on the next entry.
            return
        end
        if Safety.pause_open() ~= false then return end
        if owner then
            owner.visible_param = nil
            owner.picker_index = nil
            if tm == owner.tm and read(tm, "_UIData") == owner.ui
                and read(owner.selector, "_ChildData") == owner.installed then
                owner.armed_path = nil
                if owner.revision ~= Library.revision then
                    build_picker_pages()
                    owner.revision = Library.revision
                end
                return
            end
            restore()
        end
        if tick >= 120 then install(tm) end
    end)
    if not success then
        failed = true
        pcall(restore)
        log.error("[NativeLibraryPilot] Disabled: " .. tostring(detail))
    end
end)
re.on_script_reset(function()
    local success, detail = pcall(restore)
    stopped = true
    if not success then log.error("[NativeLibraryPilot] Restore failed: " .. tostring(detail)) end
end)
trace("Revision 6 loaded. Close native menu briefly to install the library tab.")
