package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local Feedback = require("func/ComboTrials/ComboFeedback")

local OUTBOX = "SF6_TrainingRemoteControl_data/ComboFeedback/feedback-outbox-v1.json"
local ACK = "SF6_TrainingRemoteControl_data/ComboFeedback/feedback-ack-v1.json"
local stored = {}
local writes = {}
local encoded_value = nil
local next_id = 0
local fail_write = false

local function make_id()
    next_id = next_id + 1
    return string.format("%032x", next_id)
end

local producer = Feedback.new({
    probe = function(path)
        assert(path == OUTBOX, "only the fixed outbox may be probed")
        return stored[path] and "exists" or "missing"
    end,
    read = function(path)
        return stored[path]
    end,
    decode = function(raw)
        return raw
    end,
    encode = function(value)
        encoded_value = value
        return "encoded-feedback-outbox"
    end,
    atomic_write = function(path, raw)
        if fail_write then return false, "injected_write_failure" end
        writes[#writes + 1] = { path = path, raw = raw }
        stored[path] = encoded_value
        return true
    end,
    random_id = make_id,
    now = function() return "2026-08-17T00:00:00Z" end,
    build_identity = function(context)
        assert(type(context.sequence) == "table" and #context.sequence == 2,
            "feedback identity must use the frozen combo sequence")
        return {
            combo_id = "community-combo-1",
            revision_hash = "sha256:" .. string.rep("a", 64),
            identity_schema = "sf6cc.combo_identity.v1",
            title = "测试连段",
            author = "作者",
            character = "Ryu",
            declared_control = "classic",
            sequence_length = 2,
            local_filename = "must-not-leak.json",
        }
    end,
    mod_version = "1.1.9",
    game_build = "2026-08-03",
})

local sequence = {
    { id = 600, motion = "LP", raw_inputs = { 1, 2, 3 } },
    { id = 900, motion = "236+MP", timeline = { "1f : 2" } },
}

local ok, event = producer:submit({
    sequence = sequence,
    file_path = "TrainingComboTrials_data/CustomCombos/Ryu/private-name.json",
    character = "Ryu",
    declared_control = "classic",
    display_step_count = 2,
    category = "unrecognized_action_id",
    description = "第2步没有显示",
})
assert(ok == true and event.feedback_id == string.format("%032x", 1),
    "first feedback must be accepted with a durable id")
assert(#writes == 1 and writes[1].path == OUTBOX,
    "feedback must use the fixed atomic outbox path")
assert(encoded_value.schema == "sf6cc.combo_feedback_outbox.v1"
        and #encoded_value.items == 1,
    "initial feedback must create a valid outbox")
assert(event.schema == "sf6cc.combo_feedback.v1"
        and event.category == "unrecognized_action_id"
        and event.description == "第2步没有显示",
    "feedback fields are incorrect")
assert(event.combo.revision_hash == "sha256:" .. string.rep("a", 64)
        and event.combo.identity_schema == "sf6cc.combo_identity.v1"
        and event.combo.combo_id == "community-combo-1"
        and event.combo.step_count == 2,
    "feedback must use the canonical combo identity")
assert(event.runtime.mod_version == "1.1.9"
        and event.runtime.game_build == "2026-08-03",
    "feedback runtime version snapshot is missing")

local function assert_no_forbidden(value)
    if type(value) ~= "table" then return end
    for key, child in pairs(value) do
        local normalized = tostring(key):lower()
        assert(normalized ~= "file_path" and normalized ~= "filepath"
                and normalized ~= "local_filename" and normalized ~= "raw_inputs"
                and normalized ~= "relative_raw_inputs" and normalized ~= "timeline"
                and normalized ~= "account" and normalized ~= "machine_id",
            "feedback leaked forbidden field: " .. tostring(key))
        assert_no_forbidden(child)
    end
end
assert_no_forbidden(event)

stored[ACK] = {
    schema = "sf6cc.combo_feedback_ack.v1",
    acknowledged_feedback_ids = { event.feedback_id },
}
local second_ok = producer:submit({
    sequence = sequence,
    character = "Ryu",
    declared_control = "classic",
    display_step_count = 2,
    category = "demo_error",
    description = "demo stopped",
})
assert(second_ok == true and #encoded_value.items == 1
        and encoded_value.items[1].category == "demo_error",
    "client acknowledgements must prune uploaded feedback before append")

local writes_before_invalid = #writes
local invalid_ok, invalid_error = producer:submit({
    sequence = sequence,
    category = "not-a-category",
})
assert(invalid_ok == false and invalid_error == "invalid_category"
        and #writes == writes_before_invalid,
    "unknown feedback categories must fail without writing")

local long_ok, long_error = producer:submit({
    sequence = sequence,
    category = "other",
    description = string.rep("x", Feedback.MAX_DESCRIPTION_BYTES + 1),
})
assert(long_ok == false and long_error == "description_too_long",
    "oversized descriptions must fail bounded")

stored[OUTBOX] = { schema = "wrong", items = {} }
local malformed_ok, malformed_error = producer:submit({
    sequence = sequence,
    category = "detection_error",
})
assert(malformed_ok == false and malformed_error == "invalid_outbox_schema",
    "malformed outbox data must fail closed")

local full_items = {}
for index = 1, Feedback.MAX_ITEMS do
    full_items[index] = {
        schema = Feedback.ITEM_SCHEMA,
        feedback_id = string.format("%032x", index + 1000),
        category = "other",
    }
end
stored[ACK] = nil
stored[OUTBOX] = { schema = Feedback.SCHEMA, items = full_items }
local full_writes = #writes
local full_ok, full_error = producer:submit({
    sequence = sequence,
    category = "other",
})
assert(full_ok == false and full_error == "outbox_full" and #writes == full_writes,
    "a full feedback queue must preserve its last valid contents")

stored[OUTBOX] = { schema = Feedback.SCHEMA, items = {} }
local previous_outbox = stored[OUTBOX]
fail_write = true
local write_ok, write_error = producer:submit({
    sequence = sequence,
    category = "detection_error",
})
fail_write = false
assert(write_ok == false and write_error == "injected_write_failure"
        and stored[OUTBOX] == previous_outbox,
    "an atomic write failure must preserve the last valid outbox")

local native_source = assert(io.open("native/reframework-sf6cc-atomic-file/src/plugin.cpp", "r"))
local native_text = native_source:read("*a")
native_source:close()
assert(native_text:find("ComboFeedback/feedback%-outbox%-v1%.json"),
    "native fixed-path bridge does not allow the feedback outbox")
assert(native_text:find('lua_setfield(state, -2, "random_id")', 1, true),
    "native bridge does not expose a feedback-specific random id API")

print("combo feedback tests passed")
