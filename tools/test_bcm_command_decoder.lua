package.path = "autorun/?.lua;autorun/?/init.lua;" .. package.path

-- The runtime BCM decoder must produce exactly the generator's classic
-- notation. The full 2026-08-03 check (31 fighters, 3276 triggers, 0
-- differences) needs the local dumps; this test keeps a 40-trigger selection
-- covering every notation family (tools/fixtures/bcm_command_decoder_fixture.json).

local Json = require("tools/training_record_bank/vendor/dkjson")
local Decoder = require("func/ComboTrials/BcmCommandDecoder")

assert(Decoder.decode_buttons(144, 0) == "Throw")
assert(Decoder.decode_buttons(288, 0) == "Parry")
assert(Decoder.decode_buttons(576, 0) == "DI")
assert(Decoder.decode_buttons(112, 0) == "P" and Decoder.decode_buttons(112, 64) == "PP"
    and Decoder.decode_buttons(112, 128) == "PPP")
assert(Decoder.decode_buttons(896, 64) == "KK")
assert(Decoder.decode_buttons(16 | 256, 0) == "LP+MK")
assert(Decoder.decode_buttons(32 | 64, 81952) == "MP/HP")
assert(Decoder.decode_buttons(32 | 64, 82016) == "MP+HP")
assert(Decoder.decode_buttons(nil, nil) == "")

assert(Decoder.normalize_motion("5252") == "22")
assert(Decoder.normalize_motion("656") == "66")
assert(Decoder.normalize_motion("6") == "6", "a single direction is not a repeated tap")
assert(Decoder.normalize_motion("23626") == "236236")
assert(Decoder.normalize_motion("626") == "623")
assert(Decoder.normalize_motion("4136") == "41236")

assert(Decoder.format_charge_motion("46", {}) == "[4]6")
assert(Decoder.format_charge_motion("146", {
    { direction = "1", type = 1, charge_release = true },
    { direction = "6", type = 0, charge_release = false },
}) == "[4]6", "the release direction defines the held opposite")

local file = assert(io.open("tools/fixtures/bcm_command_decoder_fixture.json", "rb"))
local fixture = assert(Json.decode(file:read("*a")))
file:close()
local objects = fixture.objects
local EMPTY = { f = {} }
local access = {
    field = function(object, name)
        local value = object and object.f and object.f[name]
        if type(value) == "table" then return objects[value.ref] end
        return value
    end,
    elements = function(array)
        local list = {}
        for index, ref in ipairs(array.i or {}) do
            list[index] = (ref ~= Json.null and objects[ref]) or EMPTY
        end
        return list
    end,
}

local categories = {}
for _, case in ipairs(fixture.cases) do
    local expected = case.classic_display ~= Json.null and case.classic_display or nil
    local got = Decoder.classic_display(access, objects[case.trigger])
    assert(got == expected, string.format("%s trigger %s action %s: got %s, generator %s",
        case.fighter, tostring(case.trigger_index), tostring(case.action_id), tostring(got), tostring(expected)))
    categories[case.category] = true
end
for _, name in ipairs({ "charge", "360", "720", "air", "system", "multi_button", "any_button",
    "repeated_tap", "double_motion", "support_profile", "no_classic", "normal" }) do
    assert(categories[name], "fixture must cover " .. name)
end

-- Live accessor: REFramework objects via get_field / get_elements.
local function managed(fields)
    local object = {}
    function object:get_field(name) return fields[name] end
    return object
end
local function array(items)
    local object = {}
    function object:get_elements() return items end
    return object
end
local input = managed({ type = 0, normal = managed({ ok_key_flags = 8 }), charge = managed({ id = 0, is_release = false }) })
local down = managed({ type = 0, normal = managed({ ok_key_flags = 2 }), charge = managed({ id = 0, is_release = false }) })
local command = managed({ inputs = array({ down, input }), input_num = 2, charge_bit = 0 })
local trigger = managed({
    norm_NG = false, cond_owner_state_flags = 0, category_flags = 0,
    norm = managed({ command_ptr = array({ command }), ok_key_flags = 64, ok_key_cond_flags = 0, dc_exc_flags = 0 }),
})
assert(Decoder.classic_display(Decoder.live_access, trigger) == "26+HP")
assert(Decoder.classic_display(Decoder.live_access, managed({ norm_NG = true })) == nil)

print("BCM command decoder tests passed")
