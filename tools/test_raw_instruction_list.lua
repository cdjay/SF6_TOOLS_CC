package.path = table.concat({
    "./autorun/?.lua",
    "./autorun/?/init.lua",
    package.path,
}, ";")

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")
local RawInstructionList = require("func/ComboTrials/Raw/RawInstructionList")

local definitions = {
    d1 = { inputs = { { direction = "2" }, { direction = "3" }, { direction = "6" } } },
}
local bindings = {
    [600] = {
        { profile_name = "norm", enabled = true,
            command_definition_uids = { "d1" }, variant_indexes = { 0 },
            direct_command_tokens = { "236+HP" },
            raw_command_uid = "c1", raw_trigger_uid = "t1", trigger_index = 1,
            command_no = 1, command_index = 6 },
        { profile_name = "easy", enabled = true,
            command_definition_uids = {}, variant_indexes = {},
            direct_command_tokens = { "SP+H" },
            raw_command_uid = "c2", raw_trigger_uid = "t1", trigger_index = 1 },
        { profile_name = "norm", enabled = false,
            command_definition_uids = { "d1" }, variant_indexes = { 0 },
            direct_command_tokens = { "236+HP" },
            raw_command_uid = "c3", raw_trigger_uid = "t2", trigger_index = 2 },
    },
    [601] = {
        { profile_name = "norm", enabled = false,
            command_definition_uids = {}, variant_indexes = {},
            direct_command_tokens = {},
            raw_command_uid = "c4", raw_trigger_uid = "t3", trigger_index = 3 },
    },
    [602] = {
        { profile_name = "norm", enabled = true,
            command_definition_uids = { "d1" }, variant_indexes = { 0 },
            direct_command_tokens = { "236+HP", "214+HP" },
            raw_command_uid = "c5", raw_trigger_uid = "t4", trigger_index = 4,
            command_no = 1, command_index = 6 },
    },
}
local catalog = {
    get_bindings = function(_, action_id) return bindings[action_id] end,
    get_definition = function(_, uid) return definitions[uid] end,
}

local trace = AtomicTrace.new()
assert(trace:append({ action_id = 600, enter_frame = 1 }))
assert(trace:append({ action_id = 600, enter_frame = 2 }))
assert(trace:append({ action_id = 601, enter_frame = 3 }))
assert(trace:append({ action_id = 999, enter_frame = 4 }))
assert(trace:append({ action_id = 602, enter_frame = 5 }))
trace:finalize()

local rows = assert(RawInstructionList.build_rows(trace, catalog, "easy"))
assert(#rows == 5, "one Atomic instance must produce one row")
assert(rows[1].action_id == 600 and rows[2].action_id == 600)
assert(rows[1].occurrence == 1 and rows[2].occurrence == 2)
assert(#rows[1].variants == 3, "duplicates and all direct variants must remain")
assert(rows[1].variants[1].profile_name == "easy", "preferred profile only changes order")
assert(rows[1].variants[2].raw_command_uid == "c1")
assert(rows[1].variants[3].raw_command_uid == "c3")
assert(rows[1].variants[2].inputs[1].direction == "2")
assert(rows[1].display_text:find("%[easy%] SP%+H") ~= nil)
assert(rows[1].display_text:find("%[norm v0%] 236%+HP") ~= nil)
assert(rows[1].display_text:find("Action 600 #1", 1, true) ~= nil)
assert(rows[2].display_text:find("Action 600 #2", 1, true) ~= nil)
assert(rows[1].display_text:find("disabled", 1, true) ~= nil)
assert(rows[3].status == "NO_DIRECT_BCM_BINDING")
assert(rows[3].display_text == "Action 601 #1")
assert(#rows[3].variants == 0, "empty profile rows are facts but not direct commands")
assert(rows[4].status == "NO_DIRECT_BCM_BINDING")
assert(rows[4].display_text == "Action 999 #1")
assert(#rows[4].variants == 0)
assert(#rows[5].variants == 2, "independent direct tokens must not be truncated")
assert(rows[5].variants[1].command_definition_uid == "d1")
assert(rows[5].variants[2].command_definition_uid == nil)
assert(rows[5].variants[2].command_token == "214+HP")

local invalid, invalid_error = RawInstructionList.build_rows("bad", catalog)
assert(invalid == nil and invalid_error == "invalid_atomic_trace")

print("raw instruction list tests passed")
