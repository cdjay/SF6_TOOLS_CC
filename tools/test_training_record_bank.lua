local Bank = dofile("tools/training_record_bank/core.lua")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    assert(ok, name .. ": " .. tostring(err))
    passed = passed + 1
end
local function slot(input)
    return { name = "record", is_valid = true, is_active = true, weight = 5,
        frame = 2, input_num = 2, input_buff = { input or 16, 0 },
        fields = { Frame = 2, Weight = 5, IsActive = true, IsValid = true },
        input_fields = { Num = 2 } }
end
local function bank(fighter) return assert(Bank.open(assert(Bank.empty(fighter or 28)))) end

test("explicit save is the only writer and snapshots are detached", function()
    local b, calls = bank(), 0
    assert(not b.is_dirty())
    assert(b.add_slot(slot()) == 1)
    local snapshot = b.snapshot(); snapshot.records[1].recording.input_buff[1] = 999
    assert(b.snapshot().records[1].recording.input_buff[1] == 16)
    assert(b.is_dirty() and calls == 0)
    assert(b.save(function(document)
        calls = calls + 1
        assert(document.records[1].id == 1)
        document.records = {}
        assert(not b.delete(1))
        return true
    end))
    assert(calls == 1 and not b.is_dirty() and #b.snapshot().records == 1)
end)
test("exact content dedup preserves user name enable and weight", function()
    local b = bank()
    assert(b.add_slot(slot()) == 1)
    assert(b.edit(1, { name = "custom", enabled = false, weight = 0 }))
    local incoming = slot(); incoming.name = "other"; incoming.weight = 100
    incoming.fields.Weight = 100; incoming.fields.IsActive = false
    local id, added = b.add_slot(incoming)
    assert(id == 1 and added == false)
    local item = b.snapshot().records[1]
    assert(item.name == "custom" and item.enabled == false and item.weight == 0)
    incoming.input_buff[2] = 32
    assert(b.add_slot(incoming) == 2)
end)
test("unknown scalar differences conservatively prevent dedup", function()
    local b = bank()
    b.add_slot(slot())
    local incoming = slot(); incoming.input_fields.PlayMode = 1
    assert(b.add_slot(incoming) == 2)
    incoming.fields.Delay = 1
    assert(b.add_slot(incoming) == 3)
end)
test("delete and reopen never reuse saved IDs or renumber survivors", function()
    local b = bank()
    b.add_slot(slot(1)); b.add_slot(slot(2)); b.add_slot(slot(3))
    assert(b.delete(2))
    local stored
    assert(b.save(function(d) stored = d; return true end))
    b = assert(Bank.open(stored))
    assert(b.add_slot(slot(4)) == 4)
    local rows = b.snapshot().records
    assert(rows[1].id == 1 and rows[2].id == 3 and rows[3].id == 4)
end)
test("failed save keeps edits dirty and discard restores last saved bank", function()
    local b = bank()
    b.add_slot(slot())
    assert(b.save(function() return true end))
    b.edit(1, { name = "unsaved" })
    assert(not b.save(function() return false, "disk full" end))
    assert(b.is_dirty() and b.snapshot().records[1].name == "unsaved")
    assert(not b.save(function() error("write failed") end))
    assert(b.is_dirty())
    assert(b.discard())
    assert(not b.is_dirty() and b.snapshot().records[1].name == "record")
end)
test("merge maps source IDs to stable target IDs preserving target settings", function()
    local b, incoming = bank(), bank()
    b.add_slot(slot(1)); b.edit(1, { enabled = false, weight = 1 })
    incoming.add_slot(slot(2)); incoming.add_slot(slot(1))
    local map = assert(b.merge(incoming.snapshot()))
    assert(map[1] == 2 and map[2] == 1)
    local first = b.snapshot().records[1]
    assert(not first.enabled and first.weight == 1)
    assert(b.merge(incoming.snapshot())[1] == 2 and #b.snapshot().records == 2)
end)
test("cross character merge and unsupported fields reject atomically", function()
    local b, incoming = bank(), bank(19)
    incoming.add_slot(slot())
    assert(not b.merge(incoming.snapshot()))
    assert(not b.is_dirty())
    local document = Bank.empty(28); document.reversals = {}
    assert(not b.merge(document) and not b.is_dirty())
end)
test("200 recordings work offline and failed merge does not append a prefix", function()
    local b = bank()
    for i = 1, 199 do assert(b.add_slot(slot(i)) == i) end
    local incoming = bank(); incoming.add_slot(slot(200)); incoming.add_slot(slot(201))
    assert(not b.merge(incoming.snapshot()))
    assert(#b.snapshot().records == 199 and b.snapshot().next_id == 200)
    assert(b.add_slot(slot(200)) == 200)
    assert(not b.add_slot(slot(201)))
    assert(b.add_slot(slot(1)) == 1)
    assert(#b.snapshot().records == 200 and b.snapshot().next_id == 201)
end)
test("invalid names weights inputs and lengths never partially edit", function()
    local b = bank(); b.add_slot(slot())
    assert(not b.edit(1, { name = "changed", weight = -1 }))
    assert(not b.edit(1, { name = "<tag>" }))
    assert(not b.edit(1, { name = string.char(255) }))
    assert(not b.edit(1, { name = string.rep("a", 129) }))
    assert(not b.edit(1, { enabled = 1 }))
    assert(b.snapshot().records[1].name == "record")
    for _, value in ipairs({ -1, 4294967296, 0.5, "bad" }) do
        local s = slot(); s.input_buff[1] = value
        assert(not b.add_slot(s))
    end
    local s = slot(); s.input_buff[4] = 0
    assert(not b.add_slot(s))
    s = slot(); s.frame = 3
    assert(not b.add_slot(s))
    s = slot(); s.input_num = 1
    assert(not b.add_slot(s))
    assert(#b.snapshot().records == 1)
end)
test("3600 frame boundary is checked without changing playback bytes", function()
    local b, s = bank(), slot()
    s.frame, s.input_num, s.input_buff = 3600, 3600, {}
    for i = 1, 3600 do s.input_buff[i] = i end
    assert(b.add_slot(s) == 1)
    assert(b.snapshot().records[1].recording.input_buff[3600] == 3600)
    s.frame, s.input_num, s.input_buff[3601] = 3601, 3601, 0
    assert(not b.add_slot(s))
end)
test("duplicate IDs noncanonical documents and exhausted ID counter fail closed", function()
    local b = bank(); b.add_slot(slot())
    local d = b.snapshot(); d.records[2] = d.records[1]
    assert(not Bank.open(d))
    d = b.snapshot(); d.records[1].recording.raw = true
    assert(not Bank.open(d))
    d = b.snapshot(); d.next_id = 2147483647
    b = assert(Bank.open(d))
    assert(not b.add_slot(slot(2)))
    assert(not b.is_dirty())
end)
print(passed .. " offline recording bank tests passed")
