-- Exercise the real controller and verified file transaction without native writes.
package.path = "autorun/?.lua;" .. package.path
local Store = require("SF6CCTrainingLibrary/TrainingConfigNotes")
local Controller = require("SF6CCTrainingLibrary/Library")
local A = "SF6CC_TrainingConfigs/configs/Mai_A.json"
local B = "SF6CC_TrainingConfigs/configs/Mai_B.json"
local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}; for key, child in pairs(value) do out[key] = copy(child) end; return out
end
local function equal(a, b)
    assert(type(a) == type(b))
    if type(a) ~= "table" then assert(a == b); return end
    for key, value in pairs(a) do equal(value, b[key]) end
    for key in pairs(b) do assert(a[key] ~= nil) end
end
local function fixture()
    local s = { files = { [A] = "originalA", [B] = "originalB" }, writes = 0, imports = 0 }
    local original = { schema = "sf6cc.training_setup.v2", title = "舞的训练", description = "保留原备注",
        fighter_id = 28, fighter_name = "Mai", source_player = "P2", created_at = "original-time",
        slots = {}, reversals = { down = {}, guard = {}, damage = {} }, settings = { mode = 1 },
        annotations = { record_slots = { { slot = 80, text = "防跳" } } }, unknown = { keep = true } }
    for i = 1, 80 do original.slots[i] = { slot = i, frame = i, input_num = i, input_buff = { i } } end
    for _, group in pairs(original.reversals) do
        for i = 1, 10 do group[i] = { slot = i, skill_index = 79, weight = i } end
    end
    local encoded = { originalA = copy(original), originalB = copy(original) }
    encoded.originalB.title = "其他训练"
    s.before = copy(original)
    local serial = 0
    local store = Store.new({
        read = function(path) return s.files[path] end,
        decode = function(raw) return copy(encoded[raw]) end,
        encode = function(data) serial = serial + 1; local raw = "encoded" .. serial; encoded[raw] = copy(data); return raw end,
        write = function(path, raw) s.writes = s.writes + 1; s.files[path] = raw; return true end,
        exists = function(path) return s.files[path] ~= nil end, stamp = function() return "test" end,
    })
    function s.read(path) return copy(encoded[s.files[path]]) end
    s.ctx = { allowed = true, busy = false, session = {}, data = {}, fighter_id = 28, menu_closed = false }
    s.lib = Controller.new({
        list_configs = function() return { { path = A, filename = "Mai_A.json" }, { path = B, filename = "Mai_B.json" } } end,
        read_config_metadata = s.read,
        prepare_note_edit = store.prepare,
        commit_note_edit = function(edit, text) return edit.save(text) end,
        import_from_file = function() s.imports = s.imports + 1; error("rename must not import") end,
        export_new = function() error("rename must not export") end,
        set_slot_name = function() error("rename must not change recording names") end,
    }, function() return s.ctx end)
    s.lib.refresh()
    function s.begin()
        local token = assert(s.lib.begin_note_edit())
        s.ctx.menu_closed = true
        local text = s.lib.prepare_note_edit(token)
        return token, text
    end
    function s.rename(text)
        local token = s.begin()
        assert(s.lib.submit_note_edit(token, text))
        s.lib.tick()
        return s.lib.status_ok
    end
    return s
end
local n = 0
local function test(name, fn) fn(); n = n + 1; print("PASS config name: " .. name) end
test("prefills title; writes only title and refreshes by stable path", function()
    local s = fixture(); local token, text = s.begin()
    assert(text == "舞的训练", "configuration editor still prefills notes instead of title")
    assert(not s.lib.select(2) and not s.lib.request("import"))
    assert(s.lib.submit_note_edit(token, "反击练习"))
    s.ctx.menu_closed = false; s.lib.tick(); assert(s.writes == 0)
    s.ctx.menu_closed = true; s.lib.tick(); s.lib.tick()
    assert(s.writes == 2 and s.imports == 0 and s.lib.selection().path == A)
    local after = s.read(A); assert(after.title == "反击练习")
    after.title = s.before.title; equal(after, s.before)
    assert(s.read(B).title == "其他训练")
    assert(s.lib.selection_label() == "不知火舞 Mai [反击练习]")
    assert(s.lib.selection_details().notes == "保留原备注")
    assert(s.lib.select(2) and s.lib.select(1))
    local next_token, next_text = s.begin(); assert(next_text == "反击练习")
    s.lib.cancel_note_edit(next_token); assert(s.writes == 2)
end)
test("rejects blank, overlong, markup and invalid UTF8 names", function()
    for _, text in ipairs({ "", "   ", string.rep("字", 16), "<tag>", "a\nb", string.char(255) }) do
        local s = fixture(); assert(not s.rename(text) and s.writes == 0); equal(s.read(A), s.before)
    end
end)
test("repeated numeric and Chinese names never touch recordings", function()
    local s = fixture()
    for _, text in ipairs({ "0012", "1e3", "压制练习", "舞的训练" }) do
        assert(s.rename(text)); assert(s.read(A).title == text and s.imports == 0)
        local after = s.read(A); after.title = s.before.title; equal(after, s.before)
    end
end)
test("context changes and external file changes do not overwrite", function()
    local s = fixture(); local token = s.begin()
    assert(s.lib.submit_note_edit(token, "cancel")); s.ctx.session = {}; s.lib.tick()
    assert(s.writes == 0)
    s = fixture(); token = s.begin(); s.files[A] = "external"
    assert(s.lib.submit_note_edit(token, "cancel")); s.lib.tick()
    assert(not s.lib.status_ok and s.files[A] == "external" and s.writes == 0)
end)
print(n .. " configuration name integration tests passed")
