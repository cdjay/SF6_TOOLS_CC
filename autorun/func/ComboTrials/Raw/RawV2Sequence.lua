-- RawV2Sequence.lua
-- Adapts a finalized Atomic Trace to the frozen Combo V2 step container when
-- the Legacy action compiler cannot produce steps. Action order and duplicate
-- occurrences remain unchanged. The adapter never consults raw input, BCM, AC
-- or presentation data: V2 input and V2 Action facts are independent streams.

local RawV2Sequence = {
    name = "ComboTrials.Raw.RawV2Sequence",
}

local AtomicTrace = require("func/ComboTrials/Raw/AtomicTrace")

local function nonnegative_integer(value, fallback)
    value = tonumber(value)
    if value == nil or value % 1 ~= 0 or value < 0 then return fallback end
    return value
end

function RawV2Sequence.build(trace, step_facts)
    if not AtomicTrace.is_trace(trace) then return nil, "invalid_atomic_trace" end
    local instances = trace:get_instances()
    if #instances == 0 then return nil, "empty_atomic_trace" end

    local sequence = {}
    local previous_enter_frame = nil
    for index, instance in ipairs(instances) do
        local enter_frame = nonnegative_integer(instance.enter_frame, nil)
        local delay = 0
        if enter_frame ~= nil and previous_enter_frame ~= nil then
            delay = math.max(0, enter_frame - previous_enter_frame)
        end
        if enter_frame ~= nil then previous_enter_frame = enter_frame end

        local fact = type(step_facts) == "table" and step_facts[index] or nil
        sequence[index] = {
            id = instance.action_id,
            motion = "Action " .. tostring(instance.action_id),
            expected_combo = nonnegative_integer(
                type(fact) == "table" and fact.expected_combo or nil, 0),
            delay_from_prev = delay,
            counter_type = 0,
        }
    end
    return sequence
end

return RawV2Sequence
