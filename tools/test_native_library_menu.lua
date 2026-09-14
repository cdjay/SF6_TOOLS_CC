-- Standalone integration simulation. Does not prove native rendering.
package.path = "autorun/?.lua;" .. package.path
local path = os.getenv("SF6CC_NATIVE_LIBRARY_TEST_SOURCE") or "autorun/SF6CCTrainingLibrary/NativeMenu.lua"
local note_test = not arg or arg[1] ~= "no_editor"
local name_test = note_test and (not arg or arg[2] ~= "no_names")
local requested_slot
local note_requests, note_accept = 0, true
if note_test then
    require("SF6CCTrainingLibrary/State").editor = { request = function(slot)
        requested_slot=slot
        note_requests = note_requests + 1; return note_accept
    end }
end
local hooks, frames, resets, writes, messages = {}, {}, {}, 0, {}
local original0, original1 = { _Type = 22, _FuncType = 107 }, { _Type = 22, _FuncType = 108 }
local function array(items)
    return {
        items = items,
        get_size = function(self) return #self.items end,
        get_element = function(self, i) return self.items[i + 1] end,
        call = function(self, method, obj, i)
            assert(method == "SetValue"); self.items[i + 1] = obj
        end,
        add_ref = function() end,
    }
end
local function object(fields)
    fields.get_address = function(self) return self.native_address or self end
    fields.get_field = function(self, k) return self[k] end
    fields.set_field = function(self, k, v) self[k] = v end
    fields.add_ref = function() end
    return fields
end
original0, original1 = object(original0), object(original1)
local original = array({ original0, original1 })
local selector = object({ _Type = 18, _FuncType = 106, _ChildData = original })
local root = object({ _FuncType = 4, _ChildData = array({ selector }) })
local ui = object({ _MenuData = array({ root }) })
local rec = object({ RecordType = 1 })
local tm = object({ _IsInit = true, _UIData = ui, _UIFunc = object({}), _UITrainingMenu = object({}), _tData = object({ RecordSetting = rec }) })
local refresh_calls = 0
tm._UIFunc.call = function(_, signature, param, page, index)
    assert(signature == "ViewUpdate(app.training.BaseParam, app.training.TrainingMenuData, System.Int32)")
    assert(page._Type == 22 and page._FuncType == 345 and index == 0)
    refresh_calls = refresh_calls + 1
    param.body_parent = page
    return true
end
local gs = { in_pause_menu = true }
local training = true
local storage, guid_next = {}, 0
-- Actual read-only capture: distinct GUID bytes returned this same ToString key.
local captured_bytes = {
    "be5bca89b357a44f989ca52af09cb167", "868762dfe9f1dd4fb7586c97e1085dba",
    "2c7548b46fbe03469640f127ded48a62", "a5acd16f7fcab44685eef9f2199b13f6",
}
local function captured_guid(bytes)
    return {
        call = function() return "4da443e8-0001-0000-0f27-000000000000" end,
        read_byte = function(_, i) return tonumber(bytes:sub(i * 2 + 1, i * 2 + 2), 16) end,
    }
end
local function td(name)
    return {
        get_full_name = function() return name end,
        get_method = function(_, method) return name .. ":" .. method end,
        get_field = function(_, field)
            assert(name == "System.Guid" and field == "Empty")
            return { get_data = function()
                return { NewGuid = function()
                    guid_next = guid_next + 1
                    return captured_guid(captured_bytes[guid_next] or string.format("%032x", guid_next))
                end }
            end }
        end,
    }
end
local function managed_new()
    local o = object({})
    o.call = function(self, method, v)
        if method:match("^set_") then
            local name = method:match("^set_([^%(]+)")
            self[name], self["_" .. name] = v, v
            return
        end
        error("Unexpected managed call " .. method)
    end
    return o
end
sdk = {
    PreHookResult = { SKIP_ORIGINAL = "skip" },
    find_type_definition = td,
    get_managed_singleton = function(name) assert(name == "app.training.TrainingManager"); return tm end,
    create_instance = function(name) assert(name == "app.training.TrainingMenuData"); return managed_new() end,
    create_managed_array = function(_, n) local items = {}; for i = 1, n do items[i] = false end; return array(items) end,
    create_managed_string = function(s) return { text = s, add_ref = function() end } end,
    hook = function(method, pre, post) hooks[method] = { pre = pre, post = post } end,
    to_managed_object = function(v) return v end,
    to_int64 = function(v) return v end,
    to_ptr = function(v) return v end,
    to_valuetype = function(v) return v end,
}
thread = { get_hook_storage = function() return storage end, get_id = function() return 1 end }
re = {
    on_frame = function() end,
    on_pre_application_entry = function(_, f) frames[#frames + 1] = f end,
    on_script_reset = function(f) resets[#resets + 1] = f end,
}
log = { info = function(s) messages[#messages + 1] = s end, error = function(s) error(s) end }
json = { dump_file = function() writes = writes + 1; error("No disk writes allowed") end }
package.preload["SF6CCTrainingLibrary/Context"] = function() return {
    is_training_allowed=function() return training end, pause_open=function() return gs.in_pause_menu end,
} end
local requests, imported, exported, saved = {}, 0, 0, 0
local catalog = { { path = "a.json" }, { path = "b.json" } }
local library_context = { allowed = true, session = tm, data = tm._tData,
    fighter_id = 19, busy = false, menu_closed = false }
local lib = dofile(os.getenv("SF6CC_TRAINING_LIBRARY_TEST_SOURCE") or "autorun/SF6CCTrainingLibrary/Library.lua").new({
    set_slot_name=name_test and function() return true end or nil,
    get_record_capacity=function() return 80 end,
    get_slot_name=function(i) return "name"..i end,
    list_configs = function() return catalog end,
    read_config_metadata = function(path)
        return { title = path, fighter_name = "Ed", fighter_id = 19, source_player = "P2",
            description = path == "a.json" and "note A" or "note B" }
    end,
    import_from_file = function(path) imported = imported + 1; requests[#requests + 1] = path; return true, "Imported" end,
    export_new = function() exported = exported + 1; return true, "Exported", "b.json" end,
    save_current = function(path) saved = saved + 1; return true, "Saved", path end,
}, function() return library_context end)
package.preload["SF6CCTrainingLibrary/Library"] = function() return { shared = function() return lib end } end
assert(loadfile(path))()
local function tick(n) for _ = 1, n do for _, f in ipairs(frames) do f() end end end
local function call_hook(signature, args, original_return)
    local h = assert(hooks[signature], signature)
    storage = {}
    local result = h.pre(args)
    return result, h.post(original_return)
end
local passed = 0
local function check(name, f) f(); passed = passed + 1; print("PASS " .. name) end
check("Never change menu data while the pause menu is open", function()
    tick(180); assert(selector._ChildData == original)
end)
check("Append third page only while training is idle; preserve original nodes", function()
    gs.in_pause_menu = false; tick(180)
    assert(selector._ChildData:get_size() == 3)
    assert(selector._ChildData:get_element(0) == original0)
    assert(selector._ChildData:get_element(1) == original1)
    assert(selector._ChildData:get_element(2)._Type == 22)
    assert(rec.RecordType == 1 and writes == 0)
end)
check("Repeated idle ticks do not duplicate the third page", function()
    local installed = selector._ChildData; tick(240); assert(selector._ChildData == installed)
end)
check("Record selector uses native three-item layout without changing semantic function", function()
    assert(selector._Type == 19, "Third child alone leaves the native two-item layout active")
    assert(selector._FuncType == 106 and rec.RecordType == 1)
end)
check("Captured native GUID is not replaced by a custom empty guide", function()
    local native = captured_guid("6e495d5428620145974a822107a8199d")
    local skip, result = call_hook("app.helper.hMsg:GetMessage(System.Guid)", { 0, native }, "native title")
    assert(skip == nil and result == "native title", "Native text was intercepted as a custom empty guide")
end)
check("Custom page title survives aliased ToString results", function()
    local page = selector._ChildData:get_element(2)
    local skip, result = call_hook("app.helper.hMsg:GetMessage(System.Guid)", { 0, page.MessageID }, "original")
    assert(skip == "skip" and result.text == "导入导出")
end)
check("Unreadable GUID leaves native text untouched", function()
    local skip, result = call_hook("app.helper.hMsg:GetMessage(System.Guid)", { 0, {} }, "original")
    assert(skip == nil and result == "original")
end)
check("Config row is active and selection does not import", function()
    local label = selector._ChildData:get_element(2)._ChildData:get_element(0)
    assert(label.IsEnabled == true and label.IsCantFocus == false, "Static content was disabled instead of made read-only")
    local view = object({ Data = label })
    local skip, result = call_hook("app.training.TrainingMenuFunc:GetIsActive(app.training.TrainingFuncType, app.training.UIFlowTrainingMenu.Param.ViewData)",
        { 0, tm._UIFunc, 345, view }, 0)
    assert(skip == "skip" and result == 1, "Static content excluded by activity gate")
    skip, result = call_hook("app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)",
        { 0, tm._UIFunc, 345, {}, view, 1 }, 1)
    assert(skip == "skip" and result == 0 and rec.RecordType == 1 and writes == 0)
end)
check("Third UI index is returned without entering native record state", function()
    local skip, result = call_hook("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)", { 0, tm._UIFunc, 106, 2, 106 }, 99)
    assert(skip == "skip" and result == 2 and rec.RecordType == 1)
end)
check("Record and playback indexes follow the original method", function()
    for _, value in ipairs({ 0, 1 }) do
        local skip, result = call_hook("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)", { 0, tm._UIFunc, 106, value, 106 }, value)
        assert(skip == nil and result == value)
    end
end)
check("Unrelated native menu functions are untouched", function()
    local skip, result = call_hook("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)", { 0, tm._UIFunc, 200, 2, 200 }, 7)
    assert(skip == nil and result == 7)
end)
check("Other menu instances using the same method are untouched", function()
    local skip, result = call_hook("app.training.TrainingMenuFunc:GetOptionIndex(app.training.TrainingFuncType, System.Int32, app.training.TrainingFuncType)", { 0, object({}), 106, 2, 106 }, 1)
    assert(skip == nil and result == 1)
end)
check("Third-page confirmation refreshes native content without changing recording mode", function()
    local view = object({ Data = selector._ChildData:get_element(2) })
    local param = object({ body_parent = original1 })
    param.get_type_definition = function() return td("app.training.UIFlowTrainingMenu.Param") end
    local before = refresh_calls
    local skip, result = call_hook("app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)", { 0, tm._UIFunc, 345, param, view, 0 }, 1)
    assert(skip == "skip" and result == 0 and rec.RecordType == 1 and writes == 0)
    assert(refresh_calls == before + 1 and param.body_parent == view.Data, "Selected third tab kept the previous page body")
end)
check("Other mods' dynamic rows are untouched", function()
    local view = object({ Data = object({ _FuncType = 345 }) })
    local skip, result = call_hook("app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)", { 0, tm._UIFunc, 345, {}, view, 0 }, 1)
    assert(skip == nil and result == 1)
end)
check("Unexpected menu parameter cannot invoke native body refresh", function()
    local view = object({ Data = selector._ChildData:get_element(2) })
    local param = object({})
    param.get_type_definition = function() return td("app.training.BaseParam") end
    local before = refresh_calls
    local skip, result = call_hook("app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)",
        { 0, tm._UIFunc, 345, param, view, 0 }, 1)
    assert(skip == "skip" and result == 0 and refresh_calls == before and rec.RecordType == 1)
end)
check("Native body refresh failure does not escape to the game callback", function()
    local view = object({ Data = selector._ChildData:get_element(2) })
    local param = object({})
    param.get_type_definition = function() return td("app.training.UIFlowTrainingMenu.Param") end
    local original_call = tm._UIFunc.call
    tm._UIFunc.call = function() error("injected view failure") end
    local skip, result = call_hook("app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)",
        { 0, tm._UIFunc, 345, param, view, 0 }, 1)
    tm._UIFunc.call = original_call
    assert(skip == "skip" and result == 0 and rec.RecordType == 1 and writes == 0)
end)
check("Native recorder never receives the UI-only mode 2", function()
    local skip = call_hook("app.training.tf_RecordSetting.FuncData:ChangeRecordSetting(app.training.RECORD_TYPE)", { 0, object({ _tData = tm._tData }), 2 }, 0)
    assert(skip == "skip" and rec.RecordType == 1)
end)
check("Normal recorder modes still follow the original method", function()
    for _, value in ipairs({ 0, 1 }) do
        local skip = call_hook("app.training.tf_RecordSetting.FuncData:ChangeRecordSetting(app.training.RECORD_TYPE)", { 0, object({ _tData = tm._tData }), value }, 0)
        assert(skip == nil)
    end
end)

local FUNCTION = "app.training.TrainingMenuFunc:Function(app.training.TrainingFuncType, app.training.BaseParam, app.training.UIFlowTrainingMenu.Param.ViewData, System.Int32)"
local function title(row)
    local _, result=call_hook("app.helper.hMsg:GetMessage(System.Guid)",{0,row.MessageID},"native")
    return result.text
end
local page=selector._ChildData:get_element(2)
gs.in_pause_menu=true
local function click(row,parent)
    local param=object({body_parent=parent,get_type_definition=function() return td("app.training.UIFlowTrainingMenu.Param") end})
    local skip,result=call_hook(FUNCTION,{0,tm._UIFunc,345,param,object({Data=row,ParentData=parent}),0},99)
    assert(skip=="skip")
    return result,param
end
local function find(prefix)
    for _,row in ipairs(page._ChildData.items) do
        if title(row):sub(1,#prefix)==prefix then return row end
    end
    error("missing menu row "..prefix)
end
check("Presentation order and native separators preserve action rows",function()
    local rows=page._ChildData.items
    assert(title(rows[1])=="切换训练配置：爱德 Ed [a.json]")
    assert(title(rows[2])=="保存当前配置" and title(rows[3])=="导出当前配置")
    assert(title(rows[4])=="刷新配置列表")
    for _,row in ipairs(rows) do assert(title(row)~="导入所选配置") end
    local separators=0
    for _,row in ipairs(rows) do
        if row._Type==4 then
            separators=separators+1
            assert(row.IsCantFocus and row.IsEnabled and title(row)=="")
            assert(click(row,page)==0 and not lib.has_pending())
        end
    end
    assert(separators==2)
    assert(title(rows[#rows-4]):match("^文件："))
    assert(title(rows[#rows-3])=="角色：爱德 Ed / ID 19 / P2")
    assert(title(rows[#rows-1]):match("^栏位："))
    assert(rows[#rows].IsCantFocus)
end)
local selected_picker, selected_row
check("First configuration click selects and stays in picker without importing",function()
    local _,param=click(find("切换训练配置"),page)
    local picker=param.body_parent
    assert(picker~=page)
    local second=picker._ChildData:get_element(2)
    assert(title(second)=="2. 爱德 Ed [b.json]")
    local result,after=click(second,picker)
    assert(result==0 and after.body_parent==picker)
    assert(lib.selection().path=="b.json" and imported==0 and not lib.has_pending())
    assert(title(second):find("确认",1,true))
    selected_picker,selected_row=picker,second
end)
check("Second click imports once, only after menu closes",function()
    assert(click(selected_row,selected_picker)==1 and lib.has_pending())
    click(selected_row,selected_picker)
    lib.tick(); assert(imported==0)
    library_context.menu_closed=true; lib.tick(); lib.tick()
    assert(imported==1 and requests[1]=="b.json")
    library_context.menu_closed=false
end)
check("Reordered save and export retain their existing controller actions",function()
    assert(click(find("保存当前配置"),page)==1)
    library_context.menu_closed=true; lib.tick()
    assert(saved==1 and exported==0 and imported==1)
    library_context.menu_closed=false
    assert(click(find("导出当前配置"),page)==1)
    library_context.menu_closed=true; lib.tick()
    assert(saved==1 and exported==1 and imported==1)
    library_context.menu_closed=false
end)
if note_test then
    check("Configuration rename uses existing editor request without new arguments",function()
        local before=note_requests
        assert(click(find("修改训练配置名称"),page)==1)
        assert(note_requests==before+1 and requested_slot==nil)
        assert(saved==1 and imported==1)
    end)
end
if name_test then
    check("Renamed slot menu still edits the selected fixed slot",function()
        local _,param=click(find("修改栏位名称"),page)
        local names=param.body_parent
        assert(title(names)=="栏位名称")
        local row=names._ChildData:get_element(1)
        assert(title(row)=="栏位1：name1")
        assert(click(row,names)==1 and requested_slot==1)
    end)
end
check("Chinese character labels never modify IDs or source metadata",function()
    local character=dofile("autorun/SF6CCTrainingLibrary/CharacterNames.lua")
    assert(character("Mai")=="不知火舞 Mai")
    assert(character("不知火舞 Mai")=="不知火舞 Mai")
    assert(character("Future Fighter")=="Future Fighter")
    assert(character(nil)=="未知角色")
    assert(lib.selection().metadata.fighter_name=="Ed" and lib.selection().metadata.fighter_id==19)
end)
local function open_picker()
    local _,param=click(find("切换训练配置"),page)
    return param.body_parent,param
end
local function picker_row(picker,prefix)
    for _,row in ipairs(picker._ChildData.items) do
        if title(row):sub(1,#prefix)==prefix then return row end
    end
    error("missing picker row "..prefix)
end
check("Already selected file still requires two clicks; changing target cancels confirmation",function()
    local before=imported
    lib.select(1)
    local picker=open_picker()
    local a,b=picker._ChildData:get_element(1),picker._ChildData:get_element(2)
    assert(click(a,picker)==0 and not lib.has_pending())
    assert(click(b,picker)==0 and not lib.has_pending())
    assert(click(a,picker)==0 and not lib.has_pending())
    click(picker_row(picker,"返回"),picker)
    picker=open_picker()
    assert(click(a,picker)==0 and not lib.has_pending())
    click(picker_row(picker,"返回"),picker)
    assert(imported==before)
end)
check("Foreign parent, shared selection change and stale catalog cannot confirm import",function()
    lib.select(1)
    local picker=open_picker()
    local a=picker._ChildData:get_element(1)
    assert(click(a,page)==0 and not lib.has_pending())
    assert(click(a,picker)==0 and not lib.has_pending())
    assert(lib.select(2))
    assert(click(a,picker)==0 and not lib.has_pending())
    lib.refresh()
    local result,param=click(a,picker)
    assert(result==0 and param.body_parent==page and not lib.has_pending())
end)
check("Native rebuild callbacks cannot count as a second user click",function()
    local picker=open_picker()
    local row=picker._ChildData:get_element(1)
    local old=tm._UIFunc.call
    local nested=0
    tm._UIFunc.call=function(...)
        local outer=storage
        assert(click(row,picker)==0 and not lib.has_pending())
        storage=outer
        nested=nested+1
        return old(...)
    end
    local result=click(row,picker)
    tm._UIFunc.call=old
    assert(result==0 and nested==1 and not lib.has_pending())
    click(picker_row(picker,"返回"),picker)
end)
check("Rejected import returns to status page and retains compatibility guard",function()
    local picker=open_picker()
    local row=picker._ChildData:get_element(1)
    click(row,picker)
    local meta=lib.selection().metadata
    local fighter=meta.fighter_id
    meta.fighter_id=28
    local result,param=click(row,picker)
    assert(result==0 and param.body_parent==page and not lib.has_pending() and not lib.status_ok)
    meta.fighter_id=fighter
end)
check("Native back and closing pause discard armed confirmation",function()
    local picker=open_picker()
    local row=picker._ChildData:get_element(1)
    local _,param=click(row,picker)
    local view=object({Data=row,ParentData=picker})
    param._ViewDataList={call=function(_,method)
        if method=="get_Count" then return 1 end
        assert(method=="get_Item"); return view
    end}
    local skip=call_hook("app.training.UITrainingMenu:OnCancelStart()",{0,tm._UITrainingMenu},0)
    assert(skip=="skip" and param.body_parent==page)
    picker=open_picker()
    assert(click(row,picker)==0 and not lib.has_pending())
    gs.in_pause_menu=false; tick(30); gs.in_pause_menu=true
    picker=open_picker()
    assert(click(row,picker)==0 and not lib.has_pending())
    click(picker_row(picker,"返回"),picker)
end)
check("File-list paging cancels confirmation and does not consume a stale row",function()
    for i=3,9 do catalog[i]={path="config"..i..".json"} end
    lib.refresh("a.json")
    local picker=open_picker()
    local first=picker._ChildData:get_element(1)
    click(first,picker)
    local _,param=click(picker_row(picker,"下一页"),picker)
    local second=param.body_parent
    assert(second~=picker)
    assert(click(first,second)==0 and not lib.has_pending())
    _,param=click(picker_row(second,"上一页"),second)
    assert(param.body_parent==picker)
    assert(click(first,picker)==0 and not lib.has_pending())
    click(picker_row(picker,"返回"),picker)
end)
check("Scene changes cancel a confirmed import before any recording write",function()
    local before=imported
    local picker=open_picker()
    local row=picker._ChildData:get_element(1)
    click(row,picker)
    assert(click(row,picker)==1 and lib.has_pending())
    library_context.menu_closed=true
    library_context.session={}
    lib.tick()
    assert(imported==before and not lib.has_pending())
end)
print(passed.." native menu presentation checks passed (fake SDK)")
