-- ChargeRuntimePolicy.lua
-- How a held button is judged. The default is Instant / Partial / Maxed
-- against an action's charge_min / charge_max. A fighter whose hold works
-- differently declares it in its exception file (exceptions/<key>.json,
-- "_charge_policy"), so a new fighter needs data, not code:
--
--   evaluation             "thresholds" (default) | "levels" | "perfect_window"
--   labels                 levels: { <= charge_min, between, >= charge_max }
--   autodetect_charge_max  take charge_max from the first release when unset
--   track_physical_hold    follow the physical button instead of the input
--                          buffer (the hold starts before the action does)
--   charge_stock_actions   Action IDs that bank a charge instead of spending it
--
-- perfect_window judges Instant / Partial / PERFECT! / LATE against the
-- action's perfect_min / perfect_max and falls back to thresholds when the
-- action has no perfect window.

local ChargeRuntimePolicy = {
    name = "ComboTrials.ChargeRuntimePolicy",
}

local DEFAULT = { evaluation = "thresholds" }
local EVALUATIONS = { thresholds = true, levels = true, perfect_window = true }
local registered = {}

local function non_empty_string(value)
    return type(value) == "string" and value ~= ""
end

-- Returns a validated policy, or nil and a reason.
function ChargeRuntimePolicy.normalize(document)
    if document == nil then return DEFAULT end
    if type(document) ~= "table" then return nil, "_charge_policy must be an object" end
    local evaluation = document.evaluation or "thresholds"
    if not EVALUATIONS[evaluation] then return nil, "unknown evaluation " .. tostring(evaluation) end
    local policy = {
        evaluation = evaluation,
        autodetect_charge_max = document.autodetect_charge_max == true,
        track_physical_hold = document.track_physical_hold == true,
        charge_stock_actions = {},
    }
    if evaluation == "levels" then
        local labels = document.labels
        if type(labels) ~= "table" or #labels ~= 3
            or not (non_empty_string(labels[1]) and non_empty_string(labels[2]) and non_empty_string(labels[3])) then
            return nil, "levels needs three labels"
        end
        policy.labels = { labels[1], labels[2], labels[3] }
    end
    if document.charge_stock_actions ~= nil then
        if type(document.charge_stock_actions) ~= "table" then
            return nil, "charge_stock_actions must be a list of Action IDs"
        end
        for _, value in ipairs(document.charge_stock_actions) do
            local id = math.tointeger(tonumber(value))
            if id == nil then return nil, "charge_stock_actions must be a list of Action IDs" end
            policy.charge_stock_actions[id] = true
        end
    end
    return policy
end

-- Installs the policy read from a fighter's exception file; nil restores the
-- default. An invalid document also restores the default and returns the
-- reason.
function ChargeRuntimePolicy.register(character, document)
    local key = tostring(character or "")
    local policy, reason = ChargeRuntimePolicy.normalize(document)
    registered[key] = policy ~= DEFAULT and policy or nil
    return policy ~= nil, reason
end

function ChargeRuntimePolicy.policy(character)
    return registered[tostring(character or "")] or DEFAULT
end

function ChargeRuntimePolicy.is_charge_stock_action(character, action_id)
    local actions = ChargeRuntimePolicy.policy(character).charge_stock_actions
    local id = math.tointeger(tonumber(action_id))
    return type(actions) == "table" and id ~= nil and actions[id] == true
end

function ChargeRuntimePolicy.should_track_physical_hold(character)
    return ChargeRuntimePolicy.policy(character).track_physical_hold == true
end

function ChargeRuntimePolicy.should_autodetect_charge_max(character)
    return ChargeRuntimePolicy.policy(character).autodetect_charge_max == true
end

function ChargeRuntimePolicy.uses_perfect_window(character)
    return ChargeRuntimePolicy.policy(character).evaluation == "perfect_window"
end

-- Level names for the exception editor ({ low, mid, high }), nil unless the
-- fighter uses levels.
function ChargeRuntimePolicy.level_labels(character)
    return ChargeRuntimePolicy.policy(character).labels
end

local function evaluate_thresholds(frames, charge_min, charge_max)
    if charge_min and frames <= charge_min then return "Instant" end
    if charge_max and frames >= charge_max then return "Maxed" end
    if frames > 0 then return "Partial" end
    return "Instant"
end

local function evaluate_levels(labels, frames, charge_min, charge_max)
    if charge_min and frames <= charge_min then return labels[1] end
    if charge_max and frames >= charge_max then return labels[3] end
    return labels[2]
end

local function evaluate_perfect_window(frames, charge_min, perfect_min, perfect_max)
    if not perfect_min then return nil end
    local instant_threshold = charge_min or (perfect_min - 5)
    if frames <= instant_threshold then return "Instant" end
    if frames >= perfect_min and frames <= (perfect_max or perfect_min + 2) then
        return "PERFECT!"
    end
    if frames < perfect_min then return "Partial" end
    return "LATE"
end

function ChargeRuntimePolicy.evaluate_status(
    character,
    frames,
    charge_min,
    charge_max,
    perfect_min,
    perfect_max
)
    local selected = ChargeRuntimePolicy.policy(character)
    if selected.evaluation == "levels" then
        return evaluate_levels(selected.labels, frames, charge_min, charge_max)
    end
    if selected.evaluation == "perfect_window" then
        local result = evaluate_perfect_window(frames, charge_min, perfect_min, perfect_max)
        if result ~= nil then return result end
    end
    return evaluate_thresholds(frames, charge_min, charge_max)
end

return ChargeRuntimePolicy
