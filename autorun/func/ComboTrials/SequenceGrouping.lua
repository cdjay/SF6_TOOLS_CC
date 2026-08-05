local SequenceGrouping = {
    name = "ComboTrials.SequenceGrouping"
}

function SequenceGrouping.character_from_sequence(sequence, explicit_character)
    if type(explicit_character) == "string" and explicit_character ~= "" then
        return explicit_character
    end
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    if type(meta) == "table" then return meta.character end
    return nil
end

function SequenceGrouping.is_structural_followup(grouping_rules, previous_action_id, action_id)
    local predecessors = type(grouping_rules) == "table"
        and grouping_rules.predecessor_by_action or nil
    local required_predecessors = type(predecessors) == "table"
        and predecessors[tonumber(action_id)] or nil
    if type(required_predecessors) == "table" then
        return required_predecessors[tonumber(previous_action_id)] == true
    end
    return required_predecessors ~= nil
        and required_predecessors == tonumber(previous_action_id)
end

function SequenceGrouping.ensure_followup_prefix(motion)
    local value = tostring(motion or "")
    if value:match("^%s*>") then return value end
    return ">" .. value
end

function SequenceGrouping.assign_groups(sequence, explicit_character, grouping_rules)
    if type(sequence) ~= "table" then return sequence end

    local gid = 0
    for index, step in ipairs(sequence) do
        local motion = tostring(step.motion or ""):match("^%s*(.-)%s*$") or ""
        local previous = index > 1 and sequence[index - 1] or nil
        local is_followup = motion:sub(1, 1) == ">"
            or (previous and SequenceGrouping.is_structural_followup(
                grouping_rules,
                previous.id,
                step.id
            ))

        local break_after_ids = type(grouping_rules) == "table"
            and grouping_rules.break_after_ids or nil
        if is_followup and previous and type(break_after_ids) == "table"
            and break_after_ids[tonumber(previous.id)] == true then
            is_followup = false
            step.motion = motion:gsub("^>%s*", "")
        end

        if is_followup and previous then
            step.group_id = previous.group_id
        else
            gid = gid + 1
            step.group_id = gid
        end
    end
    return sequence
end

return SequenceGrouping
