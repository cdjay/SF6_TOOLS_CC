local SequenceGrouping = {
    name = "ComboTrials.SequenceGrouping"
}

-- Grouping is playback structure, not presentation text.  Most legacy trials
-- encode a follow-up by prefixing motion with ">", but generated command
-- displays intentionally contain only the command itself.  Character chains
-- whose runtime actions carry the missing relationship belong here.
local STRUCTURAL_FOLLOWUP_PREDECESSORS = {
    deejay = {}
}

local function add_chain(character_rules, chain)
    for index = 2, #chain do
        character_rules[chain[index]] = chain[index - 1]
    end
end

-- Dee Jay SA2 starts its rhythm sequence on LP.  The SA2 activation and the
-- first LP stay on separate rows; the remaining timed inputs share the LP row.
add_chain(STRUCTURAL_FOLLOWUP_PREDECESSORS.deejay, {
    1219, 1220, 1221, 1222, 1223, 1224, 1225
})
add_chain(STRUCTURAL_FOLLOWUP_PREDECESSORS.deejay, {
    1230, 1231, 1232, 1233, 1234, 1235, 1236
})

local function normalize_character_name(character_name)
    return tostring(character_name or ""):lower():gsub("[^%w]", "")
end

function SequenceGrouping.character_from_sequence(sequence, explicit_character)
    if type(explicit_character) == "string" and explicit_character ~= "" then
        return explicit_character
    end
    local first = type(sequence) == "table" and sequence[1] or nil
    local meta = type(first) == "table" and first._xt_meta or nil
    if type(meta) == "table" then return meta.character end
    return nil
end

function SequenceGrouping.is_structural_followup(character_name, previous_action_id, action_id)
    local rules = STRUCTURAL_FOLLOWUP_PREDECESSORS[normalize_character_name(character_name)]
    if not rules then return false end
    local required_predecessor = rules[tonumber(action_id)]
    return required_predecessor ~= nil and required_predecessor == tonumber(previous_action_id)
end

function SequenceGrouping.ensure_followup_prefix(motion)
    local value = tostring(motion or "")
    if value:match("^%s*>") then return value end
    return ">" .. value
end

function SequenceGrouping.assign_groups(sequence, explicit_character)
    if type(sequence) ~= "table" then return sequence end

    local character_name = SequenceGrouping.character_from_sequence(sequence, explicit_character)
    local gid = 0
    for index, step in ipairs(sequence) do
        local motion = tostring(step.motion or ""):match("^%s*(.-)%s*$") or ""
        local previous = index > 1 and sequence[index - 1] or nil
        local is_followup = motion:sub(1, 1) == ">"
            or (previous and SequenceGrouping.is_structural_followup(
                character_name,
                previous.id,
                step.id
            ))

        -- Juri: the hit after 1218 is not a real follow-up, break the group.
        if is_followup and previous and tonumber(previous.id) == 1218 then
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
