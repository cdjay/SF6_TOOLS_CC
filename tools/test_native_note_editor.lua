package.path = "autorun/?.lua;" .. package.path
local Controller = dofile("autorun/SF6CCTrainingLibrary/Library.lua")
local Notes = dofile("autorun/SF6CCTrainingLibrary/TrainingConfigNotes.lua")
local function fixture(mode)
    local s = { now = 0, calls = 0, delegates = 0, hides = 0, titles = 0, saves = 0, hooks = {},
        ctx = { allowed = true, busy = false, session = {}, data = {}, fighter_id = 1, menu_closed = false },
        gs = { in_pause_menu = true } }
    local records = {
        list_configs = function() return {
            { path = "a.json", filename = "a.json" }, { path = "b.json", filename = "b.json" },
        } end,
        read_config_metadata = function() return { description = s.saved or "old" } end,
        prepare_note_edit = function() return { description = s.saved or "old" } end,
        commit_note_edit = function(_, text) s.saves = s.saves + 1; s.saved = text; return true, "saved" end,
    }
    if mode=="slot" then
        records.get_record_capacity=function() return 80 end
        records.get_slot_name=function(i) assert(i==80); return s.saved or "old" end
        records.set_slot_name=function(i,text)
            assert(i==80); s.slot_writes=(s.slot_writes or 0)+1; s.saved=text; return true,"named"
        end
    end
    s.lib = Controller.new(records, function() return s.ctx end); s.lib.refresh()
    local function type_ref(name) return { get_full_name = function() return name end } end
    local function widget()
        local w = { add_ref = function() end }
        local title = { call = function(_, method, value)
            if method == "get_Name" then return "e_text_title" end
            if method == "get_Child" or method == "get_Next" then return nil end
            assert(method == "set_Message" and value == (mode=="slot" and "槽位80名称" or "\u{5907}\u{6ce8}")); s.titles = s.titles + 1
        end, get_type_definition = function() return type_ref("via.gui.Text") end }
        local root = { call = function(_, method)
            if method == "get_Name" then return "c_main" end
            assert(method == "get_Child"); return title
        end }
        local agent = { call = function(_, m) assert(m == "get_ControlMain"); return root end }
        local flow = { get_field = function(_, f) assert(f == "Flow"); return mode == "foreign_title" and {} or w end }
        flow.get_type_definition = function()
            return { get_fields = function() return { { get_type = function() return type_ref("app.UIAgent") end,
                get_data = function(owner, obj) assert(obj == flow); return agent end } } end,
                get_parent_type = function() return nil end }
        end
        w.call = function(_, method)
            if method == "get_FlowParam" then return flow end
            if method == "get_IsEnd" then return s.ended == true end
            if method == "get_IsShow" then return true end
            assert(method == "RequestHide(System.Boolean, System.Boolean)"); s.hides = s.hides + 1
        end
        return w
    end
    local env = setmetatable({
        os = { time = function() return s.now end },
        require = function(name)
            assert(not s.installed or mode ~= "closed_search_path", "No require during native callbacks")
            if name == "SF6CCTrainingLibrary/Context" then return {pause_open=function() return s.gs.in_pause_menu end} end
            if name == "SF6CCTrainingLibrary/TrainingConfigNotes" then return Notes end
            assert(name == "SF6CCTrainingLibrary/Library")
            return { shared = function() return s.lib end, runtime_context = function() return s.ctx end }
        end,
        sdk = { create_managed_string = function(text)
            assert(type(text)=="string")
            s.strings=(s.strings or 0)+1
            return {text=text,refs=0,add_ref=function(self) self.refs=self.refs+1 end,
                release=function(self) self.refs=self.refs-1; assert(self.refs==0); s.released=(s.released or 0)+1 end}
        end, create_delegate = mode ~= "unsupported" and function(name, count)
            assert(name == "app.UITextInputDialog.ResultFunc" and count == 1)
            s.delegates = s.delegates + 1; s.delegate = { add_ref = function() end }; return s.delegate
        end or nil,
            find_type_definition = function(name)
                return { get_method = function(_, method)
                    return { key = name .. ":" .. method, call = function(_, target, delegate, req, visual, initial, priority)
                        assert(method:match("^OpenTextInputDialog") and delegate == s.delegate and req == 77 and visual == 9)
                        -- Installed REFramework a0e9010f checks lua_isnumber
                        -- before lua_isstring when marshalling native arguments.
                        if type(initial)=="string" and tonumber(initial) then
                            error("numeric Lua string passed as double bits, not System.String")
                        end
                        if type(initial)=="table" then
                            assert(initial.refs==1,"native prefill string must stay rooted through dialog lifetime")
                            initial=initial.text
                        end
                        assert(initial == (s.saved or "old") and s.ctx.menu_closed and not s.gs.in_pause_menu)
                        if mode == "factory_error" then error("test") end
                        s.calls = s.calls + 1; s.widget = widget(); return s.widget
                    end }
                end, get_field = function(_, field)
                    return { get_data = function() return field == "ReciperMemo" and 77 or 9 end }
                end }
            end,
            hook = function(method, pre, post) s.hooks[method.key] = { pre = pre, post = post } end,
            to_managed_object = function(v) return v end },
        re = { on_pre_application_entry = function(name, f) assert(name == "LateUpdateBehavior"); s.frame = f end,
            on_script_reset = function(f) s.reset = f end },
        thread = { get_hook_storage = function() s.storage = s.storage or {}; return s.storage end },
        log = { warn = function() end },
        json = { dump_file = function() error("Editor must not persist text or diagnostics") end },
    }, { __index = _G })
    s.editor = assert(loadfile("autorun/SF6CCTrainingLibrary/NativeNoteEditor.lua", "t", env))().install()
    s.installed = true
    function s.advance(n) for _ = 1, n or 6 do s.frame(); s.lib.tick() end end
    function s.open()
        s.ctx.menu_closed, s.gs.in_pause_menu, s.ended = false, true, false
        assert(s.editor.request(mode=="slot" and 80 or nil)); local before = s.calls; s.advance(); assert(s.calls == before)
        s.ctx.menu_closed, s.gs.in_pause_menu = true, false; s.advance(); s.advance()
    end
    function s.fire(method, w, text, callback)
        local h = s.hooks["app.UITextInputDialog:" .. method]
        local value = text and { call = function(_, m) assert(m == "ToString"); return text end }
        assert(h.pre({false, w, value}) == nil)
        if callback then s.delegate[0]({}) end
        assert(h.post(42) == 42)
    end
    function s.confirm(text)
        s.fire("Decide()", s.widget)
        s.fire("InvokeResultEvent(System.String)", s.widget, text, true)
        assert(s.saves == 0 or s.saved ~= text)
        s.ended = true; s.advance()
    end
    return s
end
local n = 0
local function check(name, fn) fn(); n = n + 1; print("PASS native notes: " .. name) end
check("prefill, native title, deferred save and refreshed metadata", function()
    local s = fixture(); s.open(); assert(s.titles == 1 and s.editor.title_changed)
    assert(not s.lib.select(1)); s.confirm("\u{5907}\u{6ce8}")
    assert(s.saves == 1 and s.lib.selection().metadata.description == "\u{5907}\u{6ce8}" and not s.lib.has_pending())
end)
check("nil cancel discards; empty confirmation clears", function()
    local s = fixture(); s.open()
    s.fire("Cancel()", s.widget); s.fire("InvokeResultEvent(System.String)", s.widget, nil, true)
    s.ended = true; s.advance(); assert(s.saves == 0 and not s.lib.has_pending())
    s.open(); s.confirm(""); assert(s.saves == 1 and s.saved == "")
end)
check("repeated edits reuse delegate and never reuse a finished transaction", function()
    local s = fixture(); s.open(); s.confirm("first"); s.open(); s.confirm("second")
    assert(s.delegates == 1 and s.calls == 2 and s.saves == 2)
end)
check("foreign result is not read and wrong title ownership is not changed", function()
    local s = fixture("foreign_title"); s.open(); assert(s.titles == 0)
    local h = s.hooks["app.UITextInputDialog:InvokeResultEvent(System.String)"]
    h.pre({false, {}, {call = function() error("Foreign text read") end}})
    s.ended = true; s.advance(); assert(s.saves == 0)
end)
check("unknown result and oversized text cannot save", function()
    local s = fixture(); s.open(); s.fire("InvokeResultEvent(System.String)", s.widget, "text", true)
    s.ended = true; s.advance(); assert(s.saves == 0)
    s.open(); s.confirm(string.rep("x", 16)); assert(s.saves == 0)
end)
check("context change, timeout, reset release the file without saving", function()
    for _, mode in ipairs({ "scene", "timeout", "reset" }) do
        local s = fixture(); s.open()
        if mode == "scene" then s.ctx.allowed = false; s.advance()
        elseif mode == "timeout" then s.now = 121; s.advance()
        else s.reset() end
        assert(s.hides == 1 and s.saves == 0 and not s.lib.has_pending())
    end
end)
check("pending context change and unsupported interface cannot open", function()
    local s = fixture(); assert(s.editor.request()); s.ctx.session = {}; s.advance()
    assert(s.calls == 0 and not s.lib.has_pending())
    s = fixture("unsupported"); assert(not s.editor.request() and not s.lib.has_pending())
end)
check("factory failure releases transaction and disables repeated attempts", function()
    local s = fixture("factory_error"); s.open(); s.advance(60)
    assert(s.calls == 0 and not s.lib.has_pending() and not s.editor.request())
    assert(s.strings==1 and s.released==1,"failed factory retained the prefill root")
end)
check("native result validation uses dependency captured at installation", function()
    local s = fixture("closed_search_path"); s.open(); s.confirm("note")
    assert(s.saves == 1 and s.saved == "note")
end)
check("numeric names reopen after save and selection changes without disabling the editor",function()
    for _,mode in ipairs({"slot","notes"}) do
        for _,text in ipairs({"1111","0012","1e3","0x10","-3","1.5",""}) do
            local s=fixture(mode); s.saved=text
            s.open()
            assert(s.calls==1 and s.editor.available(),"prefill could not open: "..text)
            s.confirm("0022")
            assert(not s.lib.has_pending() and s.lib.select(2) and s.lib.select(1))
            s.open()
            assert(s.calls==2 and s.editor.available(),"second edit disabled after numeric name")
            s.confirm("新的名称")
            assert(s.saved=="新的名称" and s.delegates==1)
            assert(s.strings==2 and s.released==2,"prefill roots leaked between completed dialogs")
        end
    end
end)
check("slot80 reuses native input dialog, prefills subsequent edit and does not save a file",function()
    local s=fixture("slot"); s.open(); s.confirm("对空")
    assert(s.saved=="对空" and s.slot_writes==1 and s.saves==0)
    s.open(); s.confirm("防跳")
    assert(s.saved=="防跳" and s.slot_writes==2 and s.saves==0 and s.delegates==1)
end)
print(n .. " native note editor tests passed")
