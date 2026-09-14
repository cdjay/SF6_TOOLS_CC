local Bank = require("tools/training_record_bank/core")
local Codec = require("tools/training_record_bank/json_codec")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run); assert(ok, name .. ": " .. tostring(err)); passed = passed + 1
end
local function bank(count)
    local b = assert(Bank.open(assert(Bank.empty(28))))
    for i = 1, count or 0 do
        b.add_slot({ name = "record", is_valid = true, is_active = true, weight = 1,
            frame = 1, input_buff = { i }, fields = {}, input_fields = {} })
    end
    return b
end
test("referenced deletion refuses until explicitly unlinked", function()
    local b = bank(3)
    assert(b.set_reference("down", 1, 3))
    assert(b.set_reference("guard", 2, 3))
    assert(not b.delete(3) and #b.snapshot().records == 3)
    assert(b.set_reference("down", 1, nil) and not b.delete(3))
    assert(b.set_reference("guard", 2, nil) and b.delete(3))
    assert(b.snapshot().next_id == 4)
end)
test("deleting another recording changes projection not stable reference", function()
    local b = bank(3); b.set_reference("damage", 7, 3)
    assert(b.reference_plan(8, 10)[1].record_index == 2)
    assert(b.delete(2))
    local plan = assert(b.reference_plan(8, 10))
    assert(plan[1].record_id == 3 and plan[1].record_index == 1 and plan[1].slot == 7)
    assert(b.snapshot().record_refs[1].record_id == 3)
end)
test("capacity checks reject entire plan without truncating any rows", function()
    local b = bank(9); b.set_reference("guard", 11, 9)
    assert(not b.reference_plan(8, 10))
    assert(not b.reference_plan(9, 10))
    assert(b.reference_plan(9, 11)[1].record_index == 8)
    assert(not b.reference_plan(201, 200) and not b.reference_plan(9, 0))
end)
test("merge remaps references and preserves existing target selection settings", function()
    local target, incoming = bank(1), bank(2)
    target.edit(1, { enabled = false, weight = 0 })
    incoming.set_reference("guard", 5, 2)
    incoming.set_reference("down", 1, 1)
    local map = assert(target.merge(incoming.snapshot()))
    assert(map[1] == 1 and map[2] == 2)
    assert(#target.snapshot().record_refs == 2)
    assert(target.snapshot().record_refs[2].record_id == 2)
    assert(not target.snapshot().records[1].enabled and target.snapshot().records[1].weight == 0)
    assert(target.merge(incoming.snapshot()) and #target.snapshot().record_refs == 2)
end)
test("reference conflict aborts appended recordings and ID allocation too", function()
    local target, incoming = bank(1), bank(2)
    target.set_reference("down", 1, 1); incoming.set_reference("down", 1, 2)
    local before = Codec.encode(target.snapshot())
    assert(not target.merge(incoming.snapshot()))
    assert(Codec.encode(target.snapshot()) == before)
end)
test("dangling duplicate unknown and fractional references never load", function()
    local cases = {
        { { group = "down", slot = 1, record_id = 9 } },
        { { group = "other", slot = 1, record_id = 1 } },
        { { group = "down", slot = 1.5, record_id = 1 } },
        { { group = "down", slot = 1, record_id = 1, skill_index = 0 } },
        { { group = "down", slot = 1, record_id = 1 }, { group = "down", slot = 1, record_id = 1 } },
    }
    for _, refs in ipairs(cases) do
        local d = bank(1).snapshot(); d.record_refs = refs
        assert(not Bank.open(d))
    end
    local b = bank(1)
    assert(not b.set_reference("down", 201, 1) and not b.set_reference("down", 1, 2))
    assert(#b.snapshot().record_refs == 0)
end)
test("three independent groups have bounded 200 reference positions", function()
    local b = bank(1)
    for _, group in ipairs({ "down", "guard", "damage" }) do
        for i = 1, 200 do assert(b.set_reference(group, i, 1)) end
    end
    assert(#b.snapshot().record_refs == 600)
    assert(#b.reference_plan(1, 200) == 600 and not b.reference_plan(1, 10))
    assert(not b.set_reference("guard", 201, 1))
end)
test("draft1 migrates in memory only and cannot smuggle new references", function()
    local d = bank(2).snapshot(); d.schema = Bank.LEGACY_SCHEMA; d.record_refs = nil
    local b = assert(Bank.open(d))
    assert(b.snapshot().schema == Bank.SCHEMA and #b.snapshot().record_refs == 0)
    assert(d.schema == Bank.LEGACY_SCHEMA and d.record_refs == nil and not b.is_dirty())
    d.record_refs = {}; assert(not Bank.open(d))
end)
test("JSON reload retains bindings and normalizes only reference ordering", function()
    local b = bank(3)
    b.set_reference("damage", 4, 3); b.set_reference("guard", 1, 1); b.set_reference("down", 2, 3)
    local bytes = Codec.encode(b.snapshot())
    b = assert(Bank.open(Codec.decode(bytes)))
    assert(Codec.encode(b.snapshot()) == bytes and not b.delete(3))
    local refs = b.snapshot().record_refs
    assert(refs[1].group == "down" and refs[2].group == "guard" and refs[3].group == "damage")
end)
test("integer-valued float positions cannot duplicate a reference location", function()
    local b = bank(2)
    b.set_reference("down", 1, 1); b.set_reference("down", 1.0, 2)
    assert(#b.snapshot().record_refs == 1 and b.snapshot().record_refs[1].record_id == 2)
    local d = b.snapshot()
    d.record_refs[2] = { group = "down", slot = 1, record_id = 1 }
    assert(not Bank.open(d))
end)
print(passed .. " stable recording reference tests passed")
