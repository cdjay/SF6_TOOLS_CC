local Bank = require("tools/training_record_bank/core")
local Codec = require("tools/training_record_bank/json_codec")
local mode, input, output = arg[1], arg[2], arg[3]
assert(mode == "seed" or mode == "verify" or mode == "capacity")
local file = assert(io.open(input, "rb"))
local bytes = assert(file:read("*a")); assert(file:close())
local bank = assert(Bank.open(Codec.decode(bytes)))
assert(bank.snapshot().fighter_id == 28)
local function slot(value, name)
    return { name = name or "对空", is_valid = true, is_active = true, weight = 5,
        frame = 2, input_num = 2, input_buff = { value, 4294967295 },
        fields = { NativeFloat = 1.2000000476837158, NegativeZero = -0.0 }, input_fields = {} }
end
if mode == "seed" then
    assert(#bank.snapshot().records == 0)
    bank.add_slot(slot(1)); bank.add_slot(slot(2)); bank.add_slot(slot(3))
    bank.edit(1, { name = "中文名称", enabled = false, weight = 0 }); bank.delete(2)
    assert(bank.set_reference("guard", 7, 3))
elseif mode == "verify" then
    local d = bank.snapshot()
    assert(d.next_id == 4 and #d.records == 2 and d.records[1].id == 1 and d.records[2].id == 3)
    assert(d.records[1].name == "中文名称" and not d.records[1].enabled and d.records[1].weight == 0)
    assert(d.records[1].recording.input_buff[2] == 4294967295)
    assert(d.records[1].recording.fields.NativeFloat == 1.2000000476837158)
    assert(1 / d.records[1].recording.fields.NegativeZero == -math.huge)
    assert(d.record_refs[1].group == "guard" and d.record_refs[1].record_id == 3)
    assert(not bank.delete(3) and bank.reference_plan(8, 10)[1].record_index == 1)
    assert(bank.add_slot(slot(4)) == 4)
else
    for i = 1, 200 do assert(bank.add_slot(slot(i)) == i) end
end
local result = Codec.encode(bank.snapshot())
assert(Codec.encode(Codec.decode(result)) == result)
local out = assert(io.open(output, "wb")); assert(out:write(result)); assert(out:flush()); assert(out:close())
print("PASS Lua JSON " .. mode)
