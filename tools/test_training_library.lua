-- Standalone controller tests; no engine, native writes or disk access.
package.path = "autorun/?.lua;" .. package.path
local Module = dofile("autorun/SF6CCTrainingLibrary/Library.lua")
local passed = 0
local function fixture()
    local ctx = { allowed = true, session = {}, data = {}, fighter_id = 19, busy = false, menu_closed = false }
    local calls = { list = 0, export = 0, import = 0, context = 0 }
    local files = { { path = "configs/a.json", filename = "a.json" }, { path = "configs/b.json", filename = "b.json" } }
    local records = {
        list_configs = function() calls.list = calls.list + 1; return files end,
        read_config_metadata = function(path)
            return { title = path == "configs/a.json" and "A" or "B", fighter_id = 19, source_player = "P2" }
        end,
        export_new = function() calls.export = calls.export + 1; return true, "exported", "configs/b.json" end,
        import_from_file = function(path, options)
            calls.import = calls.import + 1; calls.path, calls.options = path, options
            return true, "imported"
        end,
    }
    local lib = Module.new(records, function() calls.context = calls.context + 1; return ctx end)
    return lib, ctx, calls, records, files
end
local function test(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

test("frame presentation delegates to the live records reader without importing or exporting",function()
    local lib,_,calls,records=fixture()
    assert(lib.record_frames()==nil)
    local snapshot={fighter_id=19,frames={55,0,167}}
    records.get_record_frames=function() return snapshot end
    assert(lib.record_frames()==snapshot and calls.export==0 and calls.import==0 and calls.list==0)
end)

test("abandon drops an initializing job without native cleanup or context access",function()
    local lib,ctx,calls,records=fixture()
    local cancelled=0
    records.begin_import=function()
        return true,"initializing",nil,nil,{kind="initializing",count=1,
            task={tick=function() return false end,cancel=function() cancelled=cancelled+1 end}}
    end
    lib.refresh(); assert(lib.request("import")); ctx.menu_closed=true; lib.tick()
    assert(lib.has_pending())
    local reads=calls.context
    lib.abandon(); assert(not lib.has_pending() and calls.context==reads and cancelled==0)
    lib.tick(); assert(cancelled==0)
end)

test("backup and restore are deferred jobs with captured options and session checks",function()
    for _,kind in ipairs({"backup","restore"}) do
        local lib,ctx,_,records=fixture()
        local applied=0
        records.backup_current=function() applied=applied+1; return true,"backed up" end
        records.restore_latest_backup=function(options)
            assert(options.clear_empty_slots); applied=applied+1; return true,"restored"
        end
        assert(lib.request(kind)); lib.tick(); assert(applied==0)
        lib.options.clear_empty_slots=false
        ctx.menu_closed=true; lib.tick(); lib.tick()
        assert(applied==1 and not lib.has_pending())
        assert(lib.request(kind)); ctx.session={}; lib.tick(); assert(applied==1)
    end
end)
test("input error requests cancellation, native cleanup waits for the safe job tick",function()
    local lib,ctx,_,records=fixture()
    local cancelled=0
    records.begin_import=function()
        return true,"initializing",nil,nil,{kind="initializing",count=1,
            task={tick=function() return false end,cancel=function() cancelled=cancelled+1 end}}
    end
    lib.refresh(); lib.request("import"); ctx.menu_closed=true; lib.tick()
    lib.request_cancel(); assert(cancelled==0 and lib.has_pending())
    lib.tick(); lib.tick(); assert(cancelled==1 and not lib.has_pending())
end)

test("clear works without saved files, waits for pause close and never changes catalog", function()
    local lib, ctx, calls, records = fixture()
    local cleared = 0
    records.clear_current_configuration = function()
        cleared = cleared + 1
        return true, "全部清空", "backup.json"
    end
    assert(lib.request("clear") and not lib.request("clear"))
    lib.tick(); assert(cleared == 0)
    ctx.menu_closed = true
    lib.tick(); lib.tick()
    assert(cleared == 1 and not lib.has_pending() and lib.status_ok)
    assert(lib.status == "全部清空" and lib.result_revision == 1 and lib.revision == 0)
    assert(calls.list == 0 and calls.import == 0 and calls.export == 0 and not lib.selection())
end)

test("clear rejects busy or changed environments and reports backend failures without retry", function()
    local lib, ctx, _, records = fixture()
    local cleared = 0
    records.clear_current_configuration = function() cleared = cleared + 1; return false, "failed" end
    ctx.busy = true; assert(not lib.request("clear"))
    ctx.busy = false; ctx.allowed = false; assert(not lib.request("clear"))
    ctx.allowed = true; assert(lib.request("clear"))
    ctx.session = {}; ctx.menu_closed = true; lib.tick()
    assert(cleared == 0 and not lib.has_pending())
    assert(lib.request("clear")); lib.tick(); lib.tick()
    assert(cleared == 1 and not lib.status_ok and not lib.has_pending())
    records.clear_current_configuration = function() cleared = cleared + 1; error("clear failure") end
    assert(lib.request("clear")); lib.tick(); lib.tick()
    assert(cleared == 2 and not lib.status_ok and not lib.has_pending())
end)
test("eight-slot mode rejects oversized import and overwrite before queueing", function()
    local lib, ctx, calls, records = fixture()
    lib.refresh()
    lib.entries[1].metadata.record_slots=80
    assert(not lib.request("import") and not lib.has_pending())
    assert(lib.status:find("超过8栏位",1,true))
    assert(not lib.request("save") and not lib.has_pending())
    assert(lib.status:find("无法覆盖",1,true))
    ctx.menu_closed=true; lib.tick()
    assert(calls.import==0)
end)
test("idle has no context lookup or IO", function()
    local lib, _, calls = fixture()
    for _ = 1, 1000 do lib.tick() end
    assert(calls.context == 0 and calls.list == 0 and calls.import == 0 and calls.export == 0)
end)
test("browsing never imports; pause defers IO; one confirmation one import", function()
    local lib, ctx, calls = fixture()
    assert(lib.refresh() and lib.select(2))
    assert(calls.import == 0 and lib.request("import"))
    assert(not lib.request("import") and not lib.select(1))
    lib.options.clear_empty_slots = false
    lib.tick(); assert(calls.import == 0)
    ctx.menu_closed = true
    lib.tick(); lib.tick()
    assert(calls.import == 1 and calls.path == "configs/b.json" and calls.options.clear_empty_slots)
end)
test("export without selection, refresh and select exported path", function()
    local lib, ctx, calls = fixture()
    assert(lib.request("export")); ctx.menu_closed = true; lib.tick()
    assert(calls.export == 1 and calls.list == 1 and lib.selected == 2)
    assert(lib.status == "已导出：b.json")
end)

test("save updates selected file once after menu closes, without export or import", function()
    local lib, ctx, calls, records = fixture()
    local saved = 0
    records.save_current = function(path)
        saved = saved + 1; assert(path == "configs/a.json")
        return true, "saved", path
    end
    assert(not lib.request("save"))
    assert(lib.refresh() and lib.request("save") and not lib.select(2))
    lib.tick(); assert(saved == 0)
    ctx.menu_closed = true; lib.tick(); lib.tick()
    assert(saved == 1 and calls.export == 0 and calls.import == 0)
    assert(lib.selection().path == "configs/a.json" and lib.status_ok)
    assert(lib.status == "已保存：a.json")
    assert(lib.request("save")); ctx.fighter_id = 24; lib.tick()
    assert(saved == 1 and not lib.has_pending())
end)
test("empty library rejects import but permits export", function()
    local lib, _, calls, _, files = fixture()
    files[1], files[2] = nil, nil
    assert(lib.refresh() and not lib.selection())
    assert(not lib.request("import") and lib.request("export") and calls.import == 0)
end)
for _, change in ipairs({ "session", "data", "fighter", "unsafe", "error", "busy", "unknown_busy" }) do
    test("queued request cancelled on " .. change, function()
        local lib, ctx, calls = fixture()
        assert(lib.request("export"))
        if change == "session" then ctx.session = {}
        elseif change == "data" then ctx.data = {}
        elseif change == "fighter" then ctx.fighter_id = 24
        elseif change == "unsafe" then ctx.allowed = false
        elseif change == "error" then ctx.error = "stale cached fighter"
        elseif change == "busy" then ctx.busy = true
        else ctx.busy = nil end
        ctx.menu_closed = true; lib.tick()
        assert(not lib.has_pending() and calls.export == 0 and not lib.status_ok)
    end)
end
test("busy and stale context reject before queue", function()
    local lib, ctx = fixture()
    ctx.busy = true; assert(not lib.request("export"))
    ctx.busy = false; ctx.error = "unavailable"; assert(not lib.request("export"))
end)
test("exceptions and returned failures do not retry or throw", function()
    local lib, ctx, calls, records = fixture()
    records.export_new = function() calls.export = calls.export + 1; error("write failed") end
    ctx.menu_closed = true; assert(lib.request("export")); lib.tick(); lib.tick()
    assert(calls.export == 1 and not lib.status_ok and not lib.has_pending())
    records.export_new = function() return false, "denied" end
    assert(lib.request("export")); lib.tick(); assert(not lib.status:find("denied", 1, true) and not lib.status_ok)
end)
test("refresh failure preserves previous selection", function()
    local lib, _, _, records = fixture()
    lib.refresh(); lib.select(2)
    records.list_configs = function() error("unreadable") end
    assert(not lib.refresh() and lib.selection().path == "configs/b.json")
end)
test("library size bounded and overflow preserves previous snapshot", function()
    local lib, _, _, _, files = fixture()
    assert(lib.refresh()); local revision = lib.revision
    for i = 3, 257 do files[i] = { path = "configs/" .. i .. ".json" } end
    assert(not lib.refresh() and #lib.entries == 2 and lib.revision == revision)
end)
test("title markup and control chars sanitized; invalid UTF8 bounded", function()
    local lib, _, _, records = fixture()
    records.read_config_metadata = function(path)
        return { title = path == "configs/a.json" and "<ICON hp>\nA" or string.char(255) }
    end
    lib.refresh()
    assert(not lib.labels[1]:find("[<>%c]") and lib.labels[2] == "未命名配置")
end)
test("refresh queue waits for closed native menu; reset cancels", function()
    local lib, ctx, calls = fixture()
    assert(lib.request("refresh")); lib.tick(); assert(calls.list == 0)
    ctx.menu_closed = true; lib.tick(); assert(calls.list == 1)
    assert(lib.request("export")); lib.cancel(); lib.tick(); assert(calls.export == 0)
end)
test("failed automatic load is not retried by redraw", function()
    local lib, _, calls, records = fixture()
    records.list_configs = function() calls.list = calls.list + 1; error("unreadable") end
    for _ = 1, 300 do if not lib.loaded then lib.refresh() end end
    assert(calls.list == 1 and not lib.status_ok)
end)
test("runtime context uses verified recorder getters and rejects stale context", function()
    local saved_sdk = sdk
    local saved_context=package.loaded["SF6CCTrainingLibrary/Context"]
    local saved_records=package.loaded["SF6CCTrainingLibrary/Records"]
    local rec = { call = function(_, name)
        assert(name == "IsRecording" or name == "IsReplayNow"); return false
    end }
    local tm = { get_field = function(_, name)
        if name == "_IsInit" then return true end
        assert(name == "_tData"); return rec
    end, call = function(_, name) assert(name == "get_RecordFunc"); return rec end }
    local pause = { get_field = function(_, name) assert(name == "_CurrentPauseTypeBit"); return 64 end }
    sdk = { get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return tm end
        assert(name == "app.PauseManager"); return pause
    end }
    package.loaded["SF6CCTrainingLibrary/Context"] = { is_training_allowed = function() return true end,
        training_state = function() return "training" end }
    package.loaded["SF6CCTrainingLibrary/Records"] = { get_context = function() return { fighter_id = 19 } end }
    local runtime_module=dofile("autorun/SF6CCTrainingLibrary/Library.lua")
    local ctx = runtime_module.runtime_context()
    assert(ctx.session == tm and ctx.data == rec and ctx.fighter_id == 19 and ctx.menu_closed and not ctx.busy)
    rec.call = function() return nil end
    assert(runtime_module.runtime_context().busy)
    sdk = saved_sdk
    package.loaded["SF6CCTrainingLibrary/Context"]=saved_context
    package.loaded["SF6CCTrainingLibrary/Records"]=saved_records
end)
test("same-character duplicate titles have stable display numbers without file changes",function()
    local lib,ctx,_,records,files=fixture()
    records.read_config_metadata=function(path)
        return {title=path:find("reserved",1,true) and "同名（1）" or "同名",
            fighter_id=path:find("other",1,true) and 28 or 19,source_player="P2"}
    end
    files[3]={path="configs/other.json"}; files[4]={path="configs/reserved.json"}
    assert(lib.refresh())
    assert(lib.labels[1]=="同名（2）" and lib.labels[2]=="同名（3）" and lib.labels[3]=="同名")
    assert(lib.entries[1].metadata.title=="同名" and files[1].path=="configs/a.json")
    local before={}
    for i,e in ipairs(lib.entries) do before[e.path]=lib.labels[i] end
    files[1],files[2]=files[2],files[1]
    lib.refresh()
    for i,e in ipairs(lib.entries) do assert(lib.labels[i]==before[e.path]) end
    lib.select(2); assert(lib.request("import")); ctx.menu_closed=true; lib.tick()
    assert(lib.result_configuration.title=="同名（2）" and lib.result_configuration.revision==lib.result_revision)
    lib.select(1)
    assert(lib.result_configuration.title=="同名（2）","selection changed the completed operation name")
    assert(lib.request("export")); lib.tick()
    assert(lib.result_configuration.title=="同名（3）","save-as used source rather than destination title")
end)

test("selection details follow file without rereading JSON", function()
    local lib, _, _, records = fixture()
    local reads = 0
    records.read_config_metadata = function(path)
        reads = reads + 1
        return { title = "same", created_at = path == "configs/a.json" and "2026-09-13 19:00:00" or "2026-09-13 19:01:00",
            fighter_name = "Mai", fighter_id = 28, source_player = "P2", valid_slots = 2,
            active_slots = 1, active_reversals = 3, description = path }
    end
    assert(lib.refresh())
    assert(lib.selection_label() == "不知火舞 Mai【same（1）】")
    assert(lib.select(2))
    for _ = 1, 100 do
        local d = lib.selection_details()
        assert(d.file == "b.json" and d.saved == "2026-09-13 19:01:00")
        assert(d.character == "不知火舞 Mai / ID 28 / P2")
        assert(d.slots == "有效录像 2/8，启用 1；启用反击 3/30" and d.notes == "configs/b.json")
    end
    assert(reads == 2)
end)
test("real metadata reader summarizes saved facts without changing the file", function()
    local data = { created_at = "2026-09-13 19:01:00", slots = {
        { is_valid = true, is_active = true }, { is_valid = true, is_active = false }, { is_valid = false, is_active = true } },
        reversals = { down = { { active = true } }, guard = { { active = false } }, damage = { { active = true } } } }
    local env = setmetatable({ json = { load_file = function() return data end } }, { __index = _G })
    local backend = assert(loadfile("autorun/SF6CCTrainingLibrary/Records.lua", "t", env))()
    local meta = backend.read_config_metadata("example.json")
    assert(meta.valid_slots == 2 and meta.active_slots == 1 and meta.active_reversals == 2)
    assert(meta.created_at == data.created_at and #data.slots == 3)
    data = {}
    meta = backend.read_config_metadata("missing-fields.json")
    assert(meta.valid_slots == nil and meta.active_reversals == nil and meta.created_at == "")
end)
test("extended metadata and both menu details count beyond the old eight slots", function()
    local data = { slots = {}, reversals = { down = {}, guard = {}, damage = {} } }
    for i = 1, 50 do data.slots[i] = { slot = i, is_valid = true, is_active = true } end
    for i = 1, 40 do data.reversals.down[i] = { slot = i, active = true } end
    local env = setmetatable({ json = { load_file = function() return data end } }, { __index = _G })
    local backend = assert(loadfile("autorun/SF6CCTrainingLibrary/Records.lua", "t", env))()
    local lib, _, _, records = fixture()
    records.read_config_metadata = backend.read_config_metadata
    assert(lib.refresh())
    assert(lib.selection_details().slots == "有效录像 50/50，启用 50；启用反击 40/60")
    assert(#data.slots == 50 and #data.reversals.down == 40)
end)

test("Chinese outcome comes from receipt, not English diagnostic parsing", function()
    local lib, ctx, _, records = fixture()
    assert(lib.refresh())
    records.import_from_file = function()
        return true, "Imported 3 slot(s), ForceApply OK", "backup.json", "", {
            kind = "import", written = 3, cleared = 5, reversals = 30, apply_state = "applied" }
    end
    assert(lib.request("import")); ctx.menu_closed = true; lib.tick()
    assert(lib.status == "已导入 3 个录像栏位，清空 5 个，恢复 30 项反击设置；已应用")
    records.import_from_file = function()
        return true, "ForceApply failed", "backup.json", "", {
            kind = "import", written = 3, cleared = 5, reversals = 30, apply_state = "failed" }
    end
    assert(lib.request("import")); lib.tick()
    assert(not lib.status_ok and not lib.status:find("ForceApply", 1, true))
end)
test("configuration name transaction locks selected file and defers prepare/save IO", function()
    local lib, ctx, calls, records = fixture()
    assert(lib.refresh()); local prep, commit = 0, 0
    local edit = { text = "old" }
    records.prepare_note_edit = function(path) prep = prep + 1; assert(path == "configs/a.json"); return edit end
    records.commit_note_edit = function(e, text) commit = commit + 1; assert(e == edit and text == "new"); return true, "saved" end
    local token = assert(lib.begin_note_edit())
    assert(prep == 0 and not lib.select(2) and not lib.request("export") and not lib.refresh())
    ctx.menu_closed = true; assert(lib.prepare_note_edit(token) == "old" and prep == 1)
    assert(lib.submit_note_edit(token, "new")); assert(commit == 0)
    ctx.menu_closed = false; lib.tick(); assert(commit == 0)
    ctx.menu_closed = true; lib.tick(); lib.tick(); assert(commit == 1 and lib.status_ok)
    assert(lib.selection().path == "configs/a.json" and calls.import == 0 and calls.export == 0)
    assert(not lib.submit_note_edit(token, "again"))
end)
test("cancellation and changed context never commit configuration names", function()
    local lib, ctx, _, records = fixture(); lib.refresh()
    local commits = 0
    records.prepare_note_edit = function() return { text = "" } end
    records.commit_note_edit = function() commits = commits + 1 end
    local token = lib.begin_note_edit(); ctx.menu_closed = true; lib.prepare_note_edit(token)
    lib.cancel_note_edit(token); assert(not lib.has_pending() and not lib.submit_note_edit(token, "x"))
    token = lib.begin_note_edit(); lib.prepare_note_edit(token); assert(lib.submit_note_edit(token, "x"))
    ctx.session = {}; lib.tick(); assert(commits == 0 and not lib.has_pending())
    assert(not lib.submit_note_edit(nil, "x"))
end)
test("note preparation exception is logged once without writes or retries", function()
    local lib, ctx, calls, records = fixture(); lib.refresh()
    local attempts, messages, old_log = 0, {}, log
    log = { warn = function(message) messages[#messages + 1] = message end }
    records.prepare_note_edit = function()
        attempts = attempts + 1; error("note-prepare-test-error")
    end
    records.commit_note_edit = function() error("Must not save after failed preparation") end
    local token = assert(lib.begin_note_edit()); ctx.menu_closed = true
    assert(lib.prepare_note_edit(token) == nil)
    for _ = 1, 100 do lib.tick() end
    log = old_log
    assert(attempts == 1 and #messages == 1 and messages[1]:find("note-prepare-test-error", 1, true),
        "Note preparation exception was swallowed without a diagnostic")
    assert(not lib.status_ok and not lib.has_pending() and calls.import == 0 and calls.export == 0)
end)
test("P2 mismatch previews and rejects before queuing without hiding other files", function()
    local lib, ctx, calls, records = fixture()
    records.read_config_metadata = function(path)
        return { fighter_id = path == "configs/a.json" and 28 or 19, source_player = "P2" }
    end
    lib.refresh()
    local ok, message, code = lib.selection_compatibility()
    assert(not ok and code == "mismatch" and message:find("28", 1, true) and message:find("19", 1, true))
    assert(not lib.request("import") and not lib.has_pending() and calls.import == 0)
    assert(#lib.entries == 2 and lib.select(2))
    ok, _, code = lib.selection_compatibility()
    assert(ok and code == "match" and lib.request("import"))
    ctx.fighter_id = 28; ctx.menu_closed = true; lib.tick()
    assert(calls.import == 0 and not lib.has_pending())
end)
test("unknown metadata and stale P2 never pass even with mismatch override", function()
    local lib, ctx, calls, records = fixture()
    lib.options.reject_fighter_mismatch = false
    records.read_config_metadata = function() return {} end
    lib.refresh()
    assert(not lib.request("import") and calls.import == 0)
    lib.entries[1].metadata.fighter_id = 28
    local ok, _, code = lib.selection_compatibility()
    assert(ok and code == "override")
    ctx.error = "cached P2 is stale"
    ok, _, code = lib.selection_compatibility()
    assert(not ok and code == "unknown_current" and not lib.request("import"))
    assert(not lib.has_pending())
end)
test("remember successful configuration and reload for P2 only, not on browsing", function()
    local _, ctx, calls, records = fixture()
    local remembered, saves = {}, 0
    local choices = {load=function() return remembered end,
        save=function(value) remembered=value; saves=saves+1; return true end}
    local lib=Module.new(records,function() return ctx end,choices)
    lib.refresh(); lib.select(2); assert(saves==0)
    ctx.menu_closed=true; assert(lib.request("import")); lib.tick()
    assert(remembered["19"]=="configs/b.json" and saves==1)
    assert(not lib.autoload(28))
    local fresh=Module.new(records,function() return ctx end,choices)
    assert(fresh.autoload(19)); fresh.tick(); assert(calls.import==2)
    records.list_configs=function() return {} end
    assert(not fresh.autoload(19) and calls.import==2)
end)
test("autoload chooses only the remembered current-P2 path and never falls back to another configuration",function()
    local _,ctx,calls,records=fixture()
    local choices={load=function() return {["28"]="configs/a.json",["19"]="configs/b.json"} end,
        save=function() return true end}
    records.read_config_metadata=function(path)
        return {fighter_id=path=="configs/a.json" and 28 or 19,source_player="P2"}
    end
    local lib=Module.new(records,function() return ctx end,choices)
    ctx.menu_closed=true; ctx.fighter_id=28
    assert(lib.autoload(28)); lib.tick(); assert(calls.path=="configs/a.json" and calls.import==1)
    ctx.fighter_id=19
    assert(lib.autoload(19)); lib.tick(); assert(calls.path=="configs/b.json" and calls.import==2)
    ctx.fighter_id=26
    local scans=calls.list
    assert(not lib.autoload(26) and not lib.has_pending() and calls.list==scans)
    ctx.fighter_id=19
    records.list_configs=function() return {{path="configs/a.json"}} end
    assert(not lib.autoload(19) and not lib.has_pending()); lib.tick(); assert(calls.import==2)
    records.list_configs=function() return {{path="configs/b.json"}} end
    records.read_config_metadata=function() return {fighter_id=28,source_player="P2"} end
    lib.options.reject_fighter_mismatch=false
    assert(not lib.autoload(19) and not lib.has_pending()); lib.tick(); assert(calls.import==2)
end)
print(passed .. " training library controller tests passed")
test("slot rename is deferred, repeatable, shared and never writes a config file",function()
    local lib,ctx,calls,records=fixture()
    local names={}
    records.get_record_capacity=function() return 80 end
    records.get_slot_name=function(i) return names[i] or "" end
    records.set_slot_name=function(i,text) names[i]=text; return true,"named" end
    assert(lib.can_edit_slot_names())
    assert(not lib.begin_note_edit(81) and not lib.begin_note_edit(0))
    for _,slot in ipairs({1,80,80}) do
        ctx.menu_closed=false
        local token=assert(lib.begin_note_edit(slot))
        assert(not lib.request("export"))
        ctx.menu_closed=true
        assert(lib.prepare_note_edit(token)==(names[slot] or ""))
        assert(lib.submit_note_edit(token,"新名字"))
        assert(lib.has_pending()); lib.tick()
        assert(names[slot]=="新名字" and not lib.has_pending())
    end
    assert(calls.export==0 and calls.import==0 and calls.list==0)
    local token=assert(lib.begin_note_edit(2)); assert(lib.prepare_note_edit(token)=="")
    assert(lib.submit_note_edit(token,"取消")); ctx.fighter_id=1; lib.tick()
    assert(names[2]==nil)
end)
