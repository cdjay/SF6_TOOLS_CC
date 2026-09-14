local Session = require("tools/training_record_bank/session")
local Bank = require("tools/training_record_bank/core")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k, v in pairs(t) do out[k] = copy(v) end; return out
end
local function slot(input)
    return { name = "saved", is_valid = true, is_active = true, weight = 1,
        frame = 1, input_num = 1, input_buff = { input or 16 }, fields = {}, input_fields = {} }
end
local function fixture()
    -- Opaque codec fixture: these tests verify workflow, not a JSON implementation.
    local wires, files, reads, writes, serial = {}, {}, 0, 0, 0
    local codec = {
        encode = function(d) serial = serial + 1; local key = "wire:" .. serial; wires[key] = copy(d); return key end,
        decode = function(bytes) assert(wires[bytes], "decode failed"); return copy(wires[bytes]) end,
    }
    local storage = {
        read = function(fighter) reads = reads + 1; local f = files[fighter]; if f then return f.bytes, f.version end end,
        replace = function(fighter, bytes, expected)
            writes = writes + 1
            local current = files[fighter]
            assert((current and current.version) == expected, "external change")
            local version = string.format("%064x", writes)
            files[fighter] = { bytes = bytes, version = version }
            return bytes, version
        end,
    }
    local function seed(fighter, next_id)
        local d = assert(Bank.empty(fighter)); d.next_id = next_id or 1
        files[fighter] = { bytes = codec.encode(d), version = string.rep("a", 64) }
    end
    return Session.new(codec, storage), codec, storage, files, seed, function() return reads, writes end
end
test("new banks write only on explicit save and reopen retained content", function()
    local session, codec, storage, _, _, counts = fixture()
    assert(session.select(28)); assert(session.add_slot(slot()) == 1)
    for _ = 1, 100 do assert(session.snapshot().fighter_id == 28 and session.is_dirty()) end
    local reads, writes = counts(); assert(reads == 1 and writes == 0)
    assert(session.save()); assert(not session.is_dirty())
    local other = Session.new(codec, storage); assert(other.select(28))
    assert(other.snapshot().records[1].recording.input_buff[1] == 16)
end)
test("character switch discards unsaved edits without touching either file", function()
    local s, _, _, _, seed, counts = fixture(); seed(28); seed(19)
    assert(s.select(28)); s.add_slot(slot())
    assert(s.select(19) and #s.snapshot().records == 0 and not s.is_dirty())
    assert(s.select(28) and #s.snapshot().records == 0)
    local _, writes = counts(); assert(writes == 0)
end)
test("read failure is not a new empty bank and invalidates old selection", function()
    local s, _, storage, _, _, counts = fixture()
    s.select(28); s.add_slot(slot())
    storage.read = function() error("sharing violation") end
    assert(not s.select(19) and s.snapshot() == nil)
    assert(not s.save() and not s.add_slot(slot()))
    local _, writes = counts(); assert(writes == 0)
end)
test("invalid read receipts corruption and wrong character refuse load", function()
    for _, bad in ipairs({ "missing_bytes", "missing_token", "token", "json", "character", "record" }) do
        local s, codec, storage, _, seed = fixture(); seed(28)
        local bytes = codec.encode(assert(Bank.empty(bad == "character" and 19 or 28)))
        if bad == "record" then
            local doc = Bank.empty(28); doc.records[1] = { id = 5 }
            bytes = codec.encode(doc)
        end
        storage.read = function()
            if bad == "missing_bytes" then return nil, string.rep("a", 64) end
            if bad == "missing_token" then return bytes end
            if bad == "token" then return bytes, "BAD" end
            if bad == "json" then return "broken", string.rep("a", 64) end
            return bytes, string.rep("a", 64)
        end
        assert(not s.select(28) and not s.save())
    end
end)
test("lossy encoder including mutation is detected before any write", function()
    local s, codec, _, _, _, counts = fixture()
    s.select(28); s.add_slot(slot())
    local encode = codec.encode
    codec.encode = function(d) d.records[1].recording.input_buff[1] = 99; return encode(d) end
    assert(not s.save() and s.is_dirty() and not s.needs_reload())
    assert(s.snapshot().records[1].recording.input_buff[1] == 16)
    local _, writes = counts(); assert(writes == 0)
    codec.encode = encode
    assert(s.save())
end)
test("codec exceptions and oversized serialization leave editable dirty bank", function()
    local s, codec, _, _, _, counts = fixture()
    s.select(28); s.add_slot(slot())
    codec.encode = function() error("encoding failed") end
    assert(not s.save() and s.is_dirty() and not s.needs_reload())
    codec.encode = function() return string.rep("x", Session.MAX_BYTES + 1) end
    assert(not s.save() and s.is_dirty() and not s.needs_reload())
    local _, writes = counts(); assert(writes == 0)
end)
test("external edit prevents overwrite and blocks blind save retries", function()
    local s, _, _, files, seed, counts = fixture(); seed(28)
    s.select(28); s.add_slot(slot())
    files[28].version = string.rep("b", 64)
    assert(not s.save() and s.is_dirty() and s.needs_reload())
    assert(not s.save()); local _, writes = counts(); assert(writes == 1)
    assert(s.select(28) and not s.needs_reload() and not s.is_dirty())
end)
test("commit then exception requires reload and cannot duplicate recordings", function()
    local s, _, storage = fixture(); s.select(28); s.add_slot(slot())
    local replace = storage.replace
    storage.replace = function(...) replace(...); error("response lost after publication") end
    assert(not s.save() and s.is_dirty() and s.needs_reload())
    assert(s.select(28) and #s.snapshot().records == 1 and not s.is_dirty())
    assert(s.add_slot(slot()) == 1 and #s.snapshot().records == 1)
end)
test("returned failures and wrong receipts never report saved", function()
    for _, failure in ipairs({ "false", "token", "bytes" }) do
        local s, _, storage = fixture(); s.select(28); s.add_slot(slot())
        storage.replace = function(_, bytes)
            if failure == "false" then return false, "disk full" end
            if failure == "token" then return bytes, nil end
            return "wrong", string.rep("a", 64)
        end
        assert(not s.save() and s.is_dirty() and s.needs_reload())
    end
end)
test("selection and editing are locked during read and publication", function()
    local s, _, storage = fixture()
    local read, replace = storage.read, storage.replace
    storage.read = function(...)
        assert(not s.select(19) and not s.close() and not s.add_slot(slot()))
        return read(...)
    end
    s.select(28); s.add_slot(slot())
    storage.replace = function(...)
        assert(not s.select(19) and not s.close() and not s.delete(1))
        return replace(...)
    end
    assert(s.save() and s.snapshot().fighter_id == 28)
end)
test("runtime capture stages edits without IO and retains saved baseline", function()
    local s, _, _, _, _, counts = fixture()
    assert(s.select(28)); assert(s.add_slot(slot()) == 1); assert(s.save())
    local doc = s.snapshot(); doc.records[1].weight = 7
    local _, before = counts()
    assert(s.stage(doc) and s.is_dirty())
    local _, after = counts(); assert(after == before)
    doc.records[1].weight = 99
    assert(s.snapshot().records[1].weight == 7)
    assert(s.discard() and s.snapshot().records[1].weight == 1)
end)
test("runtime capture rejects character changes ID reuse and reference loss atomically", function()
    local s = fixture(); assert(s.select(28)); s.add_slot(slot(16)); s.add_slot(slot(32))
    assert(s.delete(1)); local good = s.snapshot()
    local wrong = copy(good); wrong.fighter_id = 19
    assert(not s.stage(wrong))
    wrong = copy(good); wrong.records[1].id = 1
    assert(not s.stage(wrong))
    wrong = copy(good); wrong.next_id = 2
    assert(not s.stage(wrong))
    assert(s.set_reference("down", 1, 2)); wrong = s.snapshot(); wrong.record_refs = {}
    assert(not s.stage(wrong) and #s.snapshot().record_refs == 1)
    assert(s.snapshot().records[1].id == 2)
end)
print(passed .. " offline bank session tests passed")
