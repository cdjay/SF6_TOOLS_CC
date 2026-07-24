local Validator = {
    name = "ComboTrials.Validator"
}

function Validator.calculate_frame_diff(actual_delay, expected_delay)
    return actual_delay - (expected_delay or 0)
end

function Validator.is_pressure_tail_step(step)
    if not step then return false end
    return step.validation_role == "pressure_tail"
end

function Validator.is_non_damage_transition(expected, prev_step)
    if type(expected) ~= "table" or type(prev_step) ~= "table" then return false end

    local expected_combo = tonumber(expected.expected_combo)
    local previous_combo = tonumber(prev_step.expected_combo)
    local expected_damage = tonumber(expected.damage_at_step)
    local previous_damage = tonumber(prev_step.damage_at_step)

    return expected_combo ~= nil
        and previous_combo ~= nil
        and expected_combo == previous_combo
        and expected_damage ~= nil
        and previous_damage ~= nil
        and expected_damage == previous_damage
end

function Validator.check_combo(params)
    local combo_ok = true
    local expected = params.expected
    local prev_step = params.prev_step
    local current_combo = params.current_combo or 0

    if Validator.is_pressure_tail_step(expected) then
        return true
    end

    if prev_step and prev_step.expected_combo ~= nil then
        local skip_strict_check = (prev_step.is_projectile_hit == true)
        if not skip_strict_check and current_combo ~= prev_step.expected_combo then
            local current_hit_already_counted =
                (expected.expected_combo or 0) > prev_step.expected_combo
                and current_combo > prev_step.expected_combo
                and current_combo <= expected.expected_combo
            local previous_hit_counted_on_transition =
                Validator.is_non_damage_transition(expected, prev_step)
                and current_combo == (tonumber(prev_step.expected_combo) or 0) + 1
            if current_hit_already_counted or previous_hit_counted_on_transition then
                -- The current move can update combo_cnt on the same frame as its action.
                -- A non-damaging transition (drive rush, stance switch, etc.) may
                -- likewise be the first frame where the previous hit becomes visible.
                combo_ok = true
            elseif params.opponent_knocked_down and current_combo == 0 and prev_step.expected_combo == 0 then
                combo_ok = true
            elseif prev_step.expected_combo == 0 and current_combo > 0 then
                combo_ok = true
            elseif current_combo == 0 and prev_step.expected_combo > 0 then
                -- Oki / cross-up setup: combo dropped naturally (opponent got up)
                combo_ok = true
            elseif expected and expected.expected_combo == 0 then
                -- RESET TOLERANCE 2.0 (Standing Reset / Oki):
                -- The sequence intends for the combo to drop to 0 after this move.
                -- So it doesn't matter if the combo counter is still running (early input)
                -- or has just naturally dropped to 0. Both states are valid.
                combo_ok = true
            else
                combo_ok = false
            end
        end
    end

    return combo_ok
end

function Validator.has_attacker_hp_snapshot(sequence)
    local first = type(sequence) == "table" and sequence[1] or nil
    local gauges = type(first) == "table" and first.snapshot_gauges or nil
    local attacker = type(gauges) == "table" and gauges.attacker or nil
    return type(attacker) == "table" and tonumber(attacker.current_hp) ~= nil
end

function Validator.build_hp_context(sequence, step_index)
    if type(sequence) ~= "table" then return nil end
    if Validator.has_attacker_hp_snapshot(sequence) then
        return nil
    end

    local index = tonumber(step_index)
    local previous = index and index > 1 and sequence[index - 1] or nil
    if type(previous) ~= "table" then return nil end

    local previous_expected_hp = tonumber(previous.expected_hp)
    local previous_actual_hp = tonumber(previous.actual_hp)
    if previous_expected_hp == nil or previous_actual_hp == nil then
        return nil
    end

    return {
        legacy_relative_hp = true,
        previous_expected_hp = previous_expected_hp,
        previous_actual_hp = previous_actual_hp
    }
end

function Validator.check_hp(expected_hp, current_hp, is_oki, expected, hp_context)
    local hp_ok = true
    if Validator.is_pressure_tail_step(expected) then
        return true
    end
    if expected_hp ~= nil and current_hp ~= nil then
        -- HP Validation is strict only for post-hit setup/oki phases.
        if is_oki then
            local expected_value = tonumber(expected_hp)
            local current_value = tonumber(current_hp)
            if type(hp_context) == "table" and hp_context.legacy_relative_hp == true then
                local previous_expected = tonumber(hp_context.previous_expected_hp)
                local previous_actual = tonumber(hp_context.previous_actual_hp)
                if expected_value ~= nil and current_value ~= nil
                    and previous_expected ~= nil and previous_actual ~= nil then
                    local expected_change = expected_value - previous_expected
                    local actual_change = current_value - previous_actual
                    hp_ok = actual_change == expected_change
                else
                    hp_ok = current_hp == expected_hp
                end
            elseif current_hp ~= expected_hp then
                hp_ok = false
            end
        end
    end
    return hp_ok
end

return Validator
