package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local consumer = require("func/ComboTrials/UnifiedActionConsumer")
local compiler = require("func/ComboTrials/ActionEventCompiler")

local function assert_equal(actual, expected, message)
    assert(actual == expected, string.format(
        "%s (expected=%s actual=%s)",
        message,
        tostring(expected),
        tostring(actual)
    ))
end

local function resolver(action_id)
    if tonumber(action_id) == 627 then return "2+MP", "direct" end
    return nil, "missing"
end

local direct_session = compiler.new({
    character = "Ingrid",
    frame = 0,
    motion_resolver = resolver,
})
local consumer_session = consumer.new_capture({
    character = "Ingrid",
    frame = 0,
    motion_resolver = resolver,
})

local samples = {
    { frame = 0, action_id = 1, action_frame = 0, direct_input = 0,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 1, action_id = 1, action_frame = 1, direct_input = 32,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 2, action_id = 627, action_frame = 0, direct_input = 32,
        facing_right = true, combo_count = 0, victim_hp = 10000 },
    { frame = 3, action_id = 627, action_frame = 1, direct_input = 0,
        facing_right = true, combo_count = 1, victim_hp = 9700 },
}

for _, sample in ipairs(samples) do
    assert(compiler.observe(direct_session, sample))
    assert(consumer.observe_capture(consumer_session, sample))
end

local direct = compiler.finalize(direct_session, {
    motion_resolver = resolver,
    flush_recording_contacts = false,
})
local through_consumer = consumer.finalize_capture(consumer_session, {
    motion_resolver = resolver,
    flush_recording_contacts = false,
})
assert_equal(#through_consumer.steps, #direct.steps,
    "consumer capture must preserve compiler step count")
for index, step in ipairs(direct.steps) do
    local projected = through_consumer.steps[index]
    assert_equal(projected.id, step.id,
        "consumer capture must preserve Action ID")
    assert_equal(projected.motion, step.motion,
        "consumer capture must preserve motion")
    assert_equal(projected.expected_combo, step.expected_combo,
        "consumer capture must preserve outcome facts")
end

local renderer = {
    get_command_display = function(_, action_id)
        if tonumber(action_id) == 900 then
            return nil, "suppress_transition", { ownership = "transition" }
        end
        return " 2+MP ", "direct", { ownership = "bcm" }
    end,
}

local motion, status, metadata = consumer.resolve_compiled_motion(
    "Ingrid",
    627,
    nil,
    nil,
    renderer
)
assert_equal(motion, "2+MP", "compiled motion must use the shared command resolver")
assert_equal(status, "direct", "compiled motion must preserve route status")
assert_equal(metadata.ownership, "bcm", "compiled motion must preserve metadata")

local transition_event = {
    id = 900,
    frame = 20,
    anchor = {
        pressed_buttons = 32,
        released_buttons = 0,
        held_buttons = 0,
    },
}
motion, status = consumer.resolve_compiled_motion(
    "Ingrid",
    900,
    transition_event,
    { events = { transition_event } },
    renderer
)
assert_equal(motion, ">P (取消)",
    "input-bound transitions must use the shared runtime command decision")
assert_equal(status, "player_input_transition",
    "transition status must remain unchanged")

local match = consumer.match_expected_action({ id = 627, motion = "2+MP" }, 627)
assert(match.matched and match.match_reason == "id",
    "expected Action matching must delegate without redefining V2")
assert(consumer.sequence_uses_input_truth({
    { relative_raw_inputs = { 0, 32, 0 } },
}), "input-truth detection must use the shared matcher policy")

local main = assert(io.open("autorun/TrainingComboTrials_v1.0.lua", "rb"))
local main_source = main:read("*a")
main:close()
assert(main_source:find(
        'UnifiedActionConsumer = require("func/ComboTrials/UnifiedActionConsumer")',
        1,
        true
    ), "main entry must load the unified consumer gateway")
assert(not main_source:find("ComboTrialsModules.ActionEventCompiler", 1, true),
    "main entry must not bypass the capture gateway")
assert(not main_source:find(
        "ComboTrialsModules.CommandResolver.resolve_unified_command_action",
        1,
        true
    ), "main entry must not bypass the command gateway")
assert(not main_source:find("ActionMatcher.match_expected_action", 1, true),
    "main entry must not bypass the expected-Action gateway")

print("UnifiedActionConsumer tests passed")
