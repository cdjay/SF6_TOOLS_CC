package.path="autorun/?.lua;"..package.path
local Notes = dofile("autorun/SF6CCTrainingLibrary/TrainingConfigNotes.lua")
local PATH = "SF6CC_TrainingConfigs/configs/Mai.json"
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}; for k, x in pairs(v) do t[k] = copy(x) end; return t
end
local function fixture(mode)
    local s = { files = { [PATH] = "original bytes" }, writes = {},
        data = { schema = "sf6cc.training_setup.v2", description = "old", title = "title", created_at = "date",
            slots = { { buff = { 1, 2, 3 }, untouched = true } }, unknown = { future = "keep" } } }
    local encodes = {}
    s.store = Notes.new({
        read = function(p) return s.files[p] end,
        exists = function(p) return s.files[p] ~= nil end,
        stamp = function() return "20260913_210000" end,
        decode = function(raw) return copy(raw == "original bytes" and s.data or encodes[raw]) end,
        encode = function(data)
            if mode == "encode_error" then error("bad") end
            local raw = "encoded" .. data.title .. data.description
            if mode == "large" then raw=raw..string.rep(" ",5*1024*1024) end
            if mode == "oversize" then raw=raw..string.rep(" ",16*1024*1024) end
            encodes[raw] = copy(data)
            if mode == "input_null" then encodes[raw].slots[1].input_buff = nil end
            if mode == "annotation_loss" then encodes[raw].annotations = nil end
            if mode == "roundtrip_loss" then encodes[raw].unknown = nil end
            s.saved = copy(data); return raw
        end,
        write = function(p, raw)
            s.writes[#s.writes + 1] = { path = p, raw = raw }
            if p ~= PATH and mode == "backup_failure" then return false end
            if p == PATH and mode == "restore_failure" then s.files[p] = "truncated"; return false end
            if p == PATH and raw ~= "original bytes" and mode == "write_failure" then
                s.files[p] = "truncated"; return false
            end
            s.files[p] = raw
            if p ~= PATH and mode == "concurrent_backup" then s.files[PATH] = "external change" end
            return true
        end,
    })
    return s
end
local n = 0
local function test(name, fn) fn(); n = n + 1; print("PASS notes store: " .. name) end
test("only title changes, exact original backup precedes write", function()
    local s = fixture(); local edit = assert(s.store.prepare(PATH))
    assert(#s.writes == 0 and edit.text == "title")
    assert(edit.save("\u{5907}\u{6ce8}"))
    assert(#s.writes == 2 and s.writes[1].path ~= PATH and s.writes[1].raw == "original bytes")
    assert(s.saved.title == "\u{5907}\u{6ce8}" and s.saved.description == "old" and s.saved.created_at == "date")
    assert(s.saved.slots[1].buff[3] == 3 and s.saved.slots[1].untouched and s.saved.unknown.future == "keep")
    assert(not edit.save("again") and #s.writes == 2)
end)
test("cancel and unchanged title have no writes; empty name is rejected", function()
    local s = fixture(); assert(s.store.prepare(PATH)); assert(#s.writes == 0)
    assert(s.store.prepare(PATH).save("title") and #s.writes == 0)
    assert(not s.store.prepare(PATH).save("") and #s.writes == 0)
end)
test("external edit or deletion is not overwritten", function()
    for _, raw in ipairs({ "external change", false }) do
        local s = fixture(); local edit = s.store.prepare(PATH); s.files[PATH] = raw or nil
        assert(not edit.save("new") and #s.writes == 0)
    end
end)
for _, mode in ipairs({ "encode_error", "roundtrip_loss", "backup_failure", "write_failure", "restore_failure", "concurrent_backup" }) do
    test(mode, function()
        local s = fixture(mode); local edit = assert(s.store.prepare(PATH))
        local ok, message = edit.save("new"); assert(not ok)
        if mode == "restore_failure" then assert(message:find("name_", 1, true))
        elseif mode == "concurrent_backup" then assert(s.files[PATH] == "external change")
        else assert(s.files[PATH] == "original bytes") end
    end)
end
test("schema and path scope protect unrelated files", function()
    local s = fixture()
    for _, p in ipairs({ "other.json", "SF6CC_TrainingConfigs/configs/../other.json", "C:/other.json", PATH .. ":x" }) do
        assert(not s.store.prepare(p))
    end
    s.data.schema = "xt.combo_trial"; assert(not s.store.prepare(PATH) and #s.writes == 0)
end)
test("invalid names cannot write; long existing title is not silently truncated", function()
    local s = fixture()
    for _, text in ipairs({ string.rep("x", 16), "<tag>", "a\nb", string.char(255) }) do
        assert(not s.store.prepare(PATH).save(text))
    end
    s.data.title = string.rep("x", 16)
    assert(s.store.prepare(PATH).text == "" and #s.writes == 0)
    s.data.description = string.rep("old note", 20)
    assert(s.store.prepare(PATH).save("replacement"))
    assert(s.saved.title == "replacement" and s.saved.description == s.data.description)
end)
test("backend loads note dependency during autorun, not deferred callback", function()
    local startup, reads, writes, loads = true, 0, 0, 0
    local env
    env = setmetatable({
        require = function(name)
            assert(startup, "Callback module search path no longer includes autorun")
            if name == "SF6CCTrainingLibrary/TrainingConfigCompatibility" then return dofile("autorun/SF6CCTrainingLibrary/TrainingConfigCompatibility.lua") end
            if name == "SF6CCTrainingLibrary/TrainingRecordImport" then return assert(loadfile("autorun/SF6CCTrainingLibrary/TrainingRecordImport.lua", "t", env))() end
            if name == "SF6CCTrainingLibrary/TrainingSlotLayout" then return dofile("autorun/SF6CCTrainingLibrary/TrainingSlotLayout.lua") end
            if name == "SF6CCTrainingLibrary/TrainingGuardSettings" then return assert(loadfile("autorun/SF6CCTrainingLibrary/TrainingGuardSettings.lua", "t", env))() end
            if name == "SF6CCTrainingLibrary/NativeOwnership" then return dofile("autorun/SF6CCTrainingLibrary/NativeOwnership.lua") end
            assert(name == "SF6CCTrainingLibrary/TrainingConfigNotes"); loads = loads + 1; return Notes
        end,
        fs = { read = function(path)
            assert(path == PATH); reads = reads + 1; return "original"
        end, write = function() writes = writes + 1; error("No writes during preparation") end },
        json = { load_string = function(raw)
            assert(raw == "original")
            return { schema = "sf6cc.training_setup.v2", description = "", slots = {} }
        end },
    }, { __index = _G })
    local backend = assert(loadfile("autorun/SF6CCTrainingLibrary/Records.lua", "t", env))()
    startup = false
    assert(reads == 0 and writes == 0)
    local ok, edit = pcall(backend.prepare_note_edit, PATH)
    assert(ok and edit and edit.text == "", tostring(edit))
    assert(loads == 1 and reads == 1 and writes == 0)
end)

test("snapshot update preserves metadata and backs up before replacing all runtime fields", function()
    local s = fixture()
    s.data.fighter_id, s.data.source_player = 19, "P2"
    local edit = assert(s.store.prepare_update(PATH))
    local snapshot = { schema=s.data.schema, fighter_id=19, source_player="P2", created_at="now",
        title="default", description="", slots={}, reversals={down={},guard={},damage={}},
        annotations={record_slots={}}, settings={record={}} }
    for i=1,8 do snapshot.slots[i]={slot=i,name="slot"..i,buff={i}} end
    for _,g in ipairs({"down","guard","damage"}) do
        for i=1,10 do snapshot.reversals[g][i]={slot=i,skill_index=7,type=1} end
    end
    assert(edit.save(snapshot) and #s.writes==2 and s.writes[1].raw=="original bytes")
    assert(s.saved.title=="title" and s.saved.description=="old" and s.saved.unknown.future=="keep")
    assert(s.saved.created_at=="now" and #s.saved.slots==8 and s.saved.slots[8].buff[1]==8)
    for _,g in ipairs({"down","guard","damage"}) do assert(#s.saved.reversals[g]==10) end
    assert(not edit.save(snapshot))
end)

test("snapshot update rejects unreadable, foreign-character and changed target without overwrite", function()
    local s=fixture(); s.data.fighter_id=19; s.data.source_player="P2"
    assert(not s.store.prepare_update("outside.json"))
    local edit=assert(s.store.prepare_update(PATH))
    assert(not edit.save({schema=s.data.schema,fighter_id=24,source_player="P2",slots={}}))
    assert(#s.writes==0)
    edit=assert(s.store.prepare_update(PATH)); s.files[PATH]="external change"
    assert(not edit.save(s.data) and #s.writes==0)
end)

for _,mode in ipairs({"backup_failure","write_failure","restore_failure","concurrent_backup","roundtrip_loss","encode_error","large","oversize"}) do
    test("snapshot update "..mode,function()
        local s=fixture(mode); s.data.fighter_id=19; s.data.source_player="P2"
        local edit=assert(s.store.prepare_update(PATH))
        local snapshot=copy(s.data)
        snapshot.reversals={down={},guard={},damage={}}; snapshot.settings={}; snapshot.annotations={}
        local ok,msg=edit.save(snapshot)
        assert(ok==(mode=="large"))
        if mode=="restore_failure" then assert(msg:find("update_",1,true))
        elseif mode=="concurrent_backup" then assert(s.files[PATH]=="external change")
        elseif not ok then assert(s.files[PATH]=="original bytes") end
    end)
end
for _,case in ipairs({
    {frame=0,num=0,buff={},expected=true},
    {frame=0,num=0,buff={0},expected=false},
    {frame=1,num=1,buff={16},expected=false},
    {frame=1,num=1,buff={},expected=false},
    {frame=0,num=1,buff={},expected=false},
}) do
    test("null buffer equivalence only for truly empty recordings "..case.frame.."/"..case.num.."/"..#case.buff,function()
        local s=fixture("input_null"); s.data.fighter_id=19; s.data.source_player="P2"
        local snapshot=copy(s.data)
        snapshot.slots={{slot=1,frame=case.frame,input_num=case.num,input_buff=case.buff}}
        snapshot.reversals={down={},guard={},damage={}}; snapshot.settings={}; snapshot.annotations={}
        local ok=s.store.prepare_update(PATH).save(snapshot)
        assert(ok==case.expected)
        if not ok then assert(#s.writes==0 and s.files[PATH]=="original bytes") end
    end)
end
test("empty annotation loss and metadata-only buffer loss remain rejected",function()
    local s=fixture("annotation_loss"); s.data.fighter_id=19; s.data.source_player="P2"
    local snapshot=copy(s.data); snapshot.reversals={}; snapshot.settings={}; snapshot.annotations={}
    assert(not s.store.prepare_update(PATH).save(snapshot) and #s.writes==0)
    s=fixture("input_null")
    s.data.slots={{frame=0,input_num=0,input_buff={}}}
    assert(not s.store.prepare(PATH).save("new") and #s.writes==0)
end)
print(n .. " configuration edit store tests passed")
