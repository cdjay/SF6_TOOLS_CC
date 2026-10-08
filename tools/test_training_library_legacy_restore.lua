-- Legacy (>8) recording bank: only the explicit restore job may run. Fake SDK only.
package.path = "autorun/?.lua;" .. package.path
local passed = 0
local function check(name, fn) fn(); passed = passed + 1; print("PASS " .. name) end

local session, data = {}, {}
local ctx
local function legacy() return { allowed = true, session = session, data = data, fighter_id = 28, busy = false,
    menu_closed = false, error = "当前录像不是8栏位", bank_unsupported = true, slot_count = 80 } end
local function native() return { allowed = true, session = session, data = data, fighter_id = 28, busy = false,
    menu_closed = false, slot_count = 8 } end
local calls = { restore = 0, summary = 0 }
local restore_result = { true, "已恢复为原生8栏位：保留第1～8栏，丢弃 7 段录像，清理 1 项反击设置" }
local records = {
    list_configs = function() return { { path = "a.json", filename = "a.json" } } end,
    read_config_metadata = function() return { fighter_id = 28, record_slots = 8 } end,
    restore_native_bank = function() calls.restore = calls.restore + 1; return table.unpack(restore_result) end,
    legacy_bank_summary = function() calls.summary = calls.summary + 1; return { size = 80, discarded = 7, reversal_refs = 1 } end,
}
local Library = dofile("autorun/SF6CCTrainingLibrary/Library.lua")
local lib = Library.new(records, function() return ctx end)
lib.refresh()

check("a legacy bank refuses every operation except restoring eight native slots", function()
    ctx = legacy()
    for _, kind in ipairs({ "save", "export", "import", "clear", "refresh", "backup", "restore" }) do
        assert(not lib.request(kind) and not lib.has_pending(), kind .. " ran on a legacy bank")
    end
    assert(lib.status == "当前录像超过8栏位，请先恢复为原生8栏位" and not lib.status_ok)
    assert(lib.request("restore_native") and lib.has_pending())
end)
check("restore runs once, only after the pause menu closes", function()
    lib.tick(); assert(calls.restore == 0, "restored while the menu was open")
    ctx.menu_closed = true
    local revision = lib.result_revision
    lib.tick(); lib.tick()
    assert(calls.restore == 1 and not lib.has_pending() and lib.result_revision == revision + 1)
    assert(lib.status_ok and lib.status:find("已恢复为原生8栏位", 1, true))
end)
check("a native bank refuses a repeated restore and resumes normal operations", function()
    ctx = native()
    assert(not lib.request("restore_native") and lib.status == "当前录像已是原生8栏位")
    assert(lib.request("refresh") and lib.has_pending())
    ctx.menu_closed = true; lib.tick(); assert(not lib.has_pending())
end)
check("environment change cancels a queued restore without running it", function()
    ctx = legacy(); assert(lib.request("restore_native"))
    ctx = legacy(); ctx.session = {}; ctx.menu_closed = true
    lib.tick()
    assert(calls.restore == 1 and not lib.has_pending() and lib.status == "环境改变，操作已取消")
end)
check("a failed restore reports a generic result and keeps details in the log", function()
    restore_result = { false, "恢复失败：injected" }
    ctx = legacy(); assert(lib.request("restore_native")); ctx.menu_closed = true; lib.tick()
    assert(calls.restore == 2 and not lib.status_ok and lib.status == "恢复未完成，请检查录像和反击设置")
    restore_result = { true, "已恢复为原生8栏位" }
end)
check("legacy summary is cached per context and result revision", function()
    calls.summary = 0
    ctx = legacy()
    local summary = lib.legacy_summary()
    assert(summary.size == 80 and summary.discarded == 7 and calls.summary == 1)
    lib.legacy_summary(); lib.legacy_summary(); assert(calls.summary == 1, "summary reread native data every update")
    ctx = legacy(); ctx.data = {}
    lib.legacy_summary(); assert(calls.summary == 2, "new training data must refresh the summary")
    ctx = native(); assert(lib.legacy_summary() == nil and calls.summary == 2)
end)

local Runtime = dofile("autorun/SF6CCTrainingLibrary/NativeEightRuntime.lua")
check("a session that began on a legacy bank never autoloads, even after restoring", function()
    local autoloads, identity = 0, { session = 1001, data = 2001, record = 3001 }
    local current
    local function address(t) return { get_address = function() return t end } end
    local runtime = Runtime.new({
        library = { cancel = function() end, abandon = function() end, autoload = function() autoloads = autoloads + 1 end },
        context = function() return current end,
        save_idle = function() return true end,
    })
    local function make(legacy_bank)
        return { allowed = true, session = address(identity.session), data = address(identity.data),
            record_func = address(identity.record), fighter_id = 28, busy = false, menu_closed = true,
            slot_count = legacy_bank and 80 or 8, bank_unsupported = legacy_bank or nil,
            error = legacy_bank and "当前录像不是8栏位" or nil }
    end
    current = make(true)
    for _ = 1, 60 do runtime.tick() end
    assert(runtime.state() == "active" and autoloads == 0, "legacy session autoloaded")
    current = make(false) -- restored in place: same session, data and recorder
    for _ = 1, 60 do runtime.tick() end
    assert(runtime.state() == "active" and autoloads == 0, "restored slots were overwritten by autoload")
    identity.data = 2002 -- next training entry
    current = make(false)
    for _ = 1, 60 do runtime.tick() end
    assert(autoloads == 1, "a new native session must autoload as before")
end)
print(string.format("PASS %d legacy recording bank restore checks (not live-game evidence)", passed))
