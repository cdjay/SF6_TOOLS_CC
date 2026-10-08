-- Native eight-slot list names through the real Names/Reversals modules. Fake SDK only.
package.path = "autorun/?.lua;" .. package.path
local passed = 0
local function check(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

local WRITE = "app.helper.hGUI:setTextMessage(via.gui.Text, app.AppDefine.GenderIdentity, System.String, System.Object[])"
local RECORD = "app.training.UIFlowTrainingMenu.Param:UpdateRecordSlotItem(app.UIPartsGroup, System.Int32)"
local PLAY = "app.training.UIFlowTrainingMenu.Param:UpdatePlaySlotItem(app.UIPartsGroup, System.Int32)"
local PICKER = "app.training.UIFlowTrainingMenu_Reversal_Recording.Param:UpdateScrollList()"
local OVERVIEW = "app.training.UIFlowTrainingMenu.Param:UpdateReversalItem(app.UIPartsGroup, System.Int32)"

local function fixture(options)
    options = options or {}
    local id, hooks, tls, errors, strings = 0, {}, {}, {}, 0
    local sdk_calls, hook_installs = 0, 0
    local function obj(fields)
        id = id + 1
        local o = { id = id, fields = fields or {} }
        function o:get_address() return self.id end
        function o:get_field(k) return self.fields[k] end
        function o:add_ref_permanent() self.permanent = true end
        function o:add_ref() error("list names must not use Lua reference bookkeeping") end
        function o:get_type_definition()
            return { get_method = function() return true end, get_full_name = function() return self.fields.type end }
        end
        function o:get_size() return #self.fields.items end
        function o:get_element(i) return self.fields.items[i + 1] end
        function o:call(k, i)
            if k == "get_Name" then return self.fields.name end
            if k == "get_Child" then return self.fields.child end
            if k == "get_Next" then return self.fields.next end
            if k == "get_Control" then return self.fields.control end
            if k == "GetChildCount" then return #self.fields.items end
            if k == "GetChild(System.Int32)" then return self.fields.items[i + 1] end
            if k == "get_Count" or k == "get_Length" then return #self.fields.items end
            if k == "get_Item" or k == "GetValue(System.Int32)" then return self.fields.items[i + 1] end
            if k == "ToString" then return self.fields.text end
            error("unexpected native call " .. k)
        end
        return o
    end
    local api = {}
    api.find_type_definition = function(name)
        sdk_calls = sdk_calls + 1
        return { get_method = function(_, sig) return name .. ":" .. sig end }
    end
    api.hook = function(m, pre, post)
        if options.fail_hook and hook_installs == options.fail_hook then error("injected hook failure") end
        hook_installs = hook_installs + 1
        local old = hooks[m]
        hooks[m] = { pre = function(args) local a = old and old.pre(args); local b = pre(args); return a or b end,
            post = function(rv) return post(old and old.post(rv) or rv) end }
    end
    api.to_managed_object = function(v) return v end
    api.to_int64 = function(v) return type(v) == "table" and v.id or v end
    api.to_ptr = function(v) return v end
    api.create_managed_string = function(text) strings = strings + 1; return obj({ text = text }) end

    -- Native record (107) and playback (108) pages with one slot row each.
    local function item(template, text_name)
        local text = obj({ name = text_name })
        local inner = obj({ name = template, child = text })
        return obj({ control = obj({ child = inner }) }), text
    end
    local record_group, record_text = item("p_GroupItem_6", "e_txt_name")
    local play_group, play_text = item("p_GroupItem_5", "e_text_name")
    local record_page, play_page = obj({ _FuncType = 107 }), obj({ _FuncType = 108 })
    local record_row = obj({ _FuncType = 118, _SlotID = 0 })
    local play_row = obj({ _FuncType = 131, _SlotID = 7 })
    local views = { obj({ Data = record_row, ParentData = record_page }), obj({ Data = play_row, ParentData = play_page }) }
    local param = obj({ _ViewDataList = obj({ items = views }), _SecondaryList = obj({ items = { record_group, play_group } }) })
    -- Reversal picker and overview.
    local reversal_parent = obj()
    local picker = obj({ ParentParam = reversal_parent })
    reversal_parent.fields.RecordingMenu = obj({ _ParamData = picker })
    local reversal = obj({ Type = 4, SkillIndex = 7, IsValid = true })
    local reversal_fighter = obj({ FighterID = 28 })
    for _, field in ipairs({ "DownReversalDatas", "GuardReversalDatas", "DamageReversalDatas" }) do
        reversal_fighter.fields[field] = obj({ items = { reversal } })
    end
    local fighters = {}
    for i = 1, 29 do fighters[i] = obj({ FighterID = i - 1 }) end
    fighters[29] = reversal_fighter
    local data = obj({ ReversalSetting = obj({ FighterDataList = obj({ items = fighters }) }) })
    local overview_row = obj({ _FuncType = 137, _Type = 8, _SlotID = 0 })
    -- The reversal overview rows live on the same training-menu Param as the lists.
    views[3] = obj({ Data = overview_row, ParentData = obj({ _FuncType = 134 }) })
    local manager = obj({ _tData = data, _UITrainingMenu = obj({ _ParamData = param }),
        _UITrainingMenu_Reversal = obj({ _ParamData = reversal_parent }) })

    local s = { paused = true, session = 1, names = { [1] = "扇子", [8] = "空跳", [9] = "第九" } }
    s.ctx = { session = manager, data = data, fighter_id = 28 }
    local State = { runtime = {
        presentation_session = function() return s.session end,
        context = function() return s.session and s.ctx or nil end,
    } }
    local library = { slot_name = function(i) return s.names[i] or "" end }
    local callbacks = {}
    local env = setmetatable({ sdk = api, thread = { get_id = function() return 1 end, get_hook_storage = function() return tls end },
        log = { error = function(m) errors[#errors + 1] = m end },
        re = { on_pre_application_entry = function(name, fn) assert(name == "LateUpdateBehavior"); callbacks.update = fn end,
            on_script_reset = function(fn) callbacks.reset = fn end } }, { __index = _G })
    env.require = function(name)
        if name == "SF6CCTrainingLibrary/Context" then return { pause_open = function() return s.paused end } end
        if name == "SF6CCTrainingLibrary/State" then return State end
        if name == "SF6CCTrainingLibrary/Library" then return { shared = function() return library end } end
        return require(name)
    end
    s.module = assert(loadfile("autorun/SF6CCTrainingLibrary/NativeSlotNames.lua", "t", env))()
    function s.update(n) for _ = 1, n or 1 do callbacks.update() end end
    function s.reset() callbacks.reset() end
    function s.counts() return sdk_calls, hook_installs, strings end
    function s.hook_names() local out = {}; for k in pairs(hooks) do out[#out + 1] = k end; return out end
    local function call(name, args, rv, body)
        local h = hooks[name]; if not h then return nil, rv end
        local previous = tls; tls = {}
        local skip = h.pre(args); if body then body() end
        local result = h.post(rv); tls = previous
        return skip, result
    end
    function s.write(text, source, slot)
        local values = obj({ items = { slot } })
        local args = { 0, text, 0, obj({ text = source or "栏位<PLUNUM>" }), values }
        call(WRITE, args, 99)
        return args[4]:call("ToString"), args[4]
    end
    function s.list_row(index, text)
        local group = index == 0 and record_group or play_group
        call(index == 0 and RECORD or PLAY, { 0, param, group, index }, 0)
        return s.write(text)
    end
    function s.picker(slot)
        local result, string
        call(PICKER, { 0, picker }, 0, function() result, string = s.write(obj({ name = "e_txt_name" }), nil, slot) end)
        return result, string
    end
    function s.overview_row(slot)
        local result
        call(OVERVIEW, { 0, param, obj(), 2 }, 0, function() result = s.write(obj({ name = "e_txt_name" }), nil, slot) end)
        return result
    end
    s.record_text, s.play_text, s.reversal, s.record_row, s.errors = record_text, play_text, reversal, record_row, errors
    return s
end

check("slot rows map by native page and _SlotID only", function()
    local f = fixture()
    local function row(fields) local o = { fields = fields }; function o:get_field(k) return self.fields[k] end; return o end
    local info = f.module.slot_info(row({ _FuncType = 118, _SlotID = 0 }), row({ _FuncType = 107 }))
    assert(info.slot == 1 and info.page == 107)
    info = f.module.slot_info(row({ _FuncType = 131, _SlotID = 7 }), row({ _FuncType = 108 }))
    assert(info.slot == 8 and info.page == 108)
    for _, bad in ipairs({ { 118, 8, 107 }, { 118, -1, 107 }, { 118, 0.5, 107 }, { 131, 0, 107 }, { 118, 0, 108 }, { 345, 0, 107 } }) do
        assert(f.module.slot_info(row({ _FuncType = bad[1], _SlotID = bad[2] }), row({ _FuncType = bad[3] })) == nil,
            "foreign or out-of-range row was renamed")
    end
end)

check("loading performs no SDK calls; hooks install once from a closed-menu active session", function()
    local f = fixture()
    assert(select(1, f.counts()) == 0 and select(2, f.counts()) == 0, "module load touched the SDK")
    f.session = nil; f.paused = false; f.update(30)
    assert(select(2, f.counts()) == 0, "installed without an active library session")
    f.session = 1; f.paused = true; f.update(30)
    assert(select(2, f.counts()) == 0, "installed while the pause menu was open")
    f.paused = false; f.update(1)
    local _, installs = f.counts()
    assert(installs == 6, "expected record, play, picker, overview and two text-writer hooks")
    for _, name in ipairs(f.hook_names()) do
        assert(not name:find("InitScrollList", 1, true) and not name:find("InitList", 1, true),
            "eight-slot names must not enlarge the reversal picker")
    end
    f.update(300)
    assert(select(2, f.counts()) == installs, "hooks were installed again")
end)

check("record and playback rows show permanent number-description labels", function()
    local f = fixture(); f.paused = false; f.update(1); f.paused = true
    local text, string = f.list_row(0, f.record_text)
    assert(text == "<PLUNUM> - 扇子" and string.permanent, "record slot 1 kept its native label")
    assert(f.list_row(1, f.play_text) == "<PLUNUM> - 空跳", "playback slot 8 kept its native label")
    local again = select(2, f.list_row(0, f.record_text))
    assert(again == string, "each repaint allocated a new label string")
    f.names[1] = "{0}"; assert(f.list_row(0, f.record_text) == "<PLUNUM> - {{0}}", "format braces must be escaped")
    f.names[1] = ""; assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "empty description must keep the native label")
    f.names[1] = "扇子"
    assert(f.write(f.record_text, "{0}帧") == "{0}帧", "frame counts must never be renamed")
    assert(#f.errors == 0, table.concat(f.errors, "\n"))
end)

check("no labels outside an active eight-slot session or with the menu closed", function()
    local f = fixture(); f.paused = false; f.update(1); f.paused = true
    f.ctx.bank_unsupported = true
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "legacy bank received eight-slot descriptions")
    f.ctx = { session = f.ctx.session, data = f.ctx.data, fighter_id = 28 }
    f.session = nil
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "inactive session renamed native rows")
    f.session = 1; f.paused = false
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "closed pause menu renamed native rows")
    f.paused = true
    f.record_row.fields._FuncType = 345
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "foreign row was renamed")
end)

check("reversal picker and overview use native slot bounds", function()
    local f = fixture(); f.paused = false; f.update(1); f.paused = true
    assert(f.picker(8) == "<PLUNUM> - 空跳", "picker slot 8 kept its native label")
    assert(f.picker(9) == "栏位<PLUNUM>", "picker renamed a slot beyond the native eight")
    assert(f.overview_row(1) == "<PLUNUM> - 空跳", "overview did not resolve the referenced recording")
    f.reversal.fields.SkillIndex = 8
    assert(f.overview_row(1) == "栏位<PLUNUM>", "overview named a recording beyond the native eight")
    assert(#f.errors == 0, table.concat(f.errors, "\n"))
end)

check("a failed installation stays inert and is never retried", function()
    local f = fixture({ fail_hook = 2 })
    f.paused = false; f.update(1)
    assert(#f.errors == 1 and f.errors[1]:find("injected hook failure", 1, true))
    local _, installs = f.counts()
    f.update(300)
    assert(select(2, f.counts()) == installs and #f.errors == 1, "failed installer retried")
    f.paused = true
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "partially installed hooks stayed active")
end)

check("script reset makes installed hooks inert", function()
    local f = fixture(); f.paused = false; f.update(1); f.paused = true
    assert(f.list_row(0, f.record_text) == "<PLUNUM> - 扇子")
    f.reset()
    assert(f.list_row(0, f.record_text) == "栏位<PLUNUM>", "reset left list names active")
end)

print(string.format("PASS %d native eight-slot list name checks (not live-game evidence)", passed))
