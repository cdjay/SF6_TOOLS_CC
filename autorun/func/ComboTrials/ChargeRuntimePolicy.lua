local ChargeRuntimePolicy = {
    name = "ComboTrials.ChargeRuntimePolicy",
}

local POLICIES = {
    Ingrid = {
        charge_stock_actions = { [969] = true },
    },
    JP = {
        autodetect_charge_max = true,
        evaluate = function(frames, charge_min, charge_max)
            if charge_min and frames <= charge_min then return "Instant" end
            if charge_max and frames >= charge_max then return "FAKE" end
            return "Partial"
        end,
    },
    Lily = {
        autodetect_charge_max = true,
        track_physical_hold = true,
        evaluate = function(frames, charge_min, charge_max)
            if charge_min and frames <= charge_min then return "Lv1" end
            if charge_max and frames >= charge_max then return "Lv3" end
            return "Lv2"
        end,
    },
    Luke = {
        evaluate = function(frames, charge_min, _, perfect_min, perfect_max)
            if not perfect_min then return nil end
            local instant_threshold = charge_min or (perfect_min - 5)
            if frames <= instant_threshold then return "Instant" end
            if frames >= perfect_min and frames <= (perfect_max or perfect_min + 2) then
                return "PERFECT!"
            end
            if frames < perfect_min then return "Partial" end
            return "LATE"
        end,
    },
}

local function policy(character)
    return POLICIES[tostring(character or "")]
end

function ChargeRuntimePolicy.is_charge_stock_action(character, action_id)
    local selected = policy(character)
    local actions = selected and selected.charge_stock_actions
    local id = tonumber(action_id)
    return type(actions) == "table" and id ~= nil and actions[id] == true
end

function ChargeRuntimePolicy.should_track_physical_hold(character)
    local selected = policy(character)
    return selected ~= nil and selected.track_physical_hold == true
end

function ChargeRuntimePolicy.should_autodetect_charge_max(character)
    local selected = policy(character)
    return selected ~= nil and selected.autodetect_charge_max == true
end

function ChargeRuntimePolicy.evaluate_status(
    character,
    frames,
    charge_min,
    charge_max,
    perfect_min,
    perfect_max
)
    local selected = policy(character)
    if selected and selected.evaluate then
        local result = selected.evaluate(
            frames,
            charge_min,
            charge_max,
            perfect_min,
            perfect_max
        )
        if result ~= nil then return result end
    end
    if charge_min and frames <= charge_min then return "Instant" end
    if charge_max and frames >= charge_max then return "Maxed" end
    if frames > 0 then return "Partial" end
    return "Instant"
end

return ChargeRuntimePolicy
