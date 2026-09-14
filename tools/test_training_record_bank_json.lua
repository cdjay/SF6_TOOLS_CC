local Bank = require("tools/training_record_bank/core")
local Codec = require("tools/training_record_bank/json_codec")
local passed = 0
local function test(name, run)
    local ok, err = pcall(run); assert(ok, name .. ": " .. tostring(err)); passed = passed + 1
end
local function fixture()
    local b = assert(Bank.open(assert(Bank.empty(28))))
    b.add_slot({ name = "对空\"反击\\", is_valid = true, is_active = false, weight = 0,
        frame = 3, input_num = 3, input_buff = { 0, 4294967295, 16 },
        fields = { FloatValue = 1.5, Flag = true, NativeText = "中文\n换行" }, input_fields = {} })
    return b
end
test("empty bank keeps records as JSON array", function()
    local document = Bank.empty(28)
    local bytes = Codec.encode(document)
    assert(bytes:find('"records":[]', 1, true))
    assert(Codec.encode(Codec.decode(bytes)) == bytes)
end)
test("unicode quoted names unsigned inputs and empty objects roundtrip", function()
    local b = fixture(); local bytes = Codec.encode(b.snapshot())
    local decoded = Codec.decode(bytes)
    local item = decoded.records[1]
    assert(item.name == "对空\"反击\\" and not item.enabled and item.weight == 0)
    assert(item.recording.input_buff[2] == 4294967295)
    assert(item.recording.fields.NativeText == "中文\n换行")
    assert(bytes:find('"input_fields":{}', 1, true))
    assert(Codec.encode(decoded) == bytes)
end)
test("sorted object keys make equal documents byte deterministic without mutation", function()
    local a = fixture().snapshot()
    local b = fixture().snapshot()
    b.records[1].recording.fields = { NativeText = "中文\n换行", Flag = true, FloatValue = 1.5 }
    assert(Codec.encode(a) == Codec.encode(b))
    assert(getmetatable(a) == nil and getmetatable(a.records) == nil)
end)
test("wrong JSON container shape null corruption and trailing content reject", function()
    local empty = Codec.encode(Bank.empty(28))
    for _, bad in ipairs({ "null", "{", empty .. "{}", empty:gsub('"records":%[%]', '"records":{}') }) do
        assert(not pcall(Codec.decode, bad))
    end
    local bytes = Codec.encode(fixture().snapshot())
    assert(not pcall(Codec.decode, bytes:gsub('"input_fields":{}', '"input_fields":[]')))
    assert(not pcall(Codec.decode, bytes:gsub('"weight":0', '"weight":null')))
end)
test("stable IDs survive actual JSON save delete and reload", function()
    local b = fixture(); b.delete(1)
    b = assert(Bank.open(Codec.decode(Codec.encode(b.snapshot()))))
    local item = fixture().snapshot().records[1]
    assert(b.add_slot({ name = item.name, is_valid = true, is_active = item.enabled, weight = item.weight,
        frame = item.recording.frame, input_buff = item.recording.input_buff,
        fields = item.recording.fields, input_fields = item.recording.input_fields }) == 2)
end)
test("SDK integer-valued floats have canonical integer JSON tokens", function()
    local integer = Bank.empty(28)
    local float = Bank.empty(28.0); float.next_id = 1.0
    assert(Codec.encode(integer) == Codec.encode(float))
end)
test("native scalar floating point values retain exact binary precision", function()
    local d = fixture().snapshot()
    for _, value in ipairs({ 1.2000000476837158, 1.2345678901234567, -0.00000012345678901234567 }) do
        d.records[1].recording.fields.FloatValue = value
        local decoded = Codec.decode(Codec.encode(d))
        assert(decoded.records[1].recording.fields.FloatValue == value, "native scalar precision changed")
    end
    d.records[1].recording.fields.FloatValue = -0.0
    local decoded = Codec.decode(Codec.encode(d))
    assert(1 / decoded.records[1].recording.fields.FloatValue == -math.huge)
end)
print(passed .. " actual JSON bank tests passed")
