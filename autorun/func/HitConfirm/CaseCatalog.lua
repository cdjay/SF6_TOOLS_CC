local Catalog = {}

local function list_to_set(values)
    local result = {}
    for _, value in ipairs(type(values) == "table" and values or {}) do
        local number = tonumber(value)
        if number then result[number] = true end
    end
    return result
end

local function prepare_case(case)
    case.revision = tonumber(case.revision) or 1
    case.character = type(case.character) == "table" and case.character or {}
    case.starter = type(case.starter) == "table" and case.starter or {}
    case.followups = type(case.followups) == "table" and case.followups or {}
    case.opponent_strategy = type(case.opponent_strategy) == "table" and case.opponent_strategy or { id = "random_guard" }
    case.contact = type(case.contact) == "table" and case.contact or {}
    case.rules = type(case.rules) == "table" and case.rules or {}
    case._starter_ids = list_to_set(case.starter.action_ids)
    case._followup_ids = {}
    case._followup_by_action = {}
    for _, followup in ipairs(case.followups) do
        for action_id in pairs(list_to_set(followup.action_ids)) do
            case._followup_ids[action_id] = true
            case._followup_by_action[action_id] = followup
        end
    end
    case._hit_damage_types = list_to_set(case.contact.hit_damage_types)
    case._block_damage_types = list_to_set(case.contact.block_damage_types)
    case.rules.hit_confirm_frames = tonumber(case.rules.hit_confirm_frames) or 45
    case.rules.block_confirm_frames = tonumber(case.rules.block_confirm_frames) or 24
    case.rules.followup_hit_frames = tonumber(case.rules.followup_hit_frames) or 45
    case.rules.minimum_combo_count = tonumber(case.rules.minimum_combo_count) or 2
    case.rules.neutral_reset_frames = tonumber(case.rules.neutral_reset_frames) or 3
    return case
end

function Catalog.build(character, starter, followup)
    assert(type(character) == "table", "character is required")
    assert(type(starter) == "table", "starter move is required")
    assert(type(followup) == "table", "followup move is required")
    local title = string.format("%s：%s → %s", tostring(character.display_name or character.name),
        tostring(starter.command), tostring(followup.command))
    return prepare_case({
        id = string.format("free:%s:%d:%d", tostring(character.key or character.name),
            tonumber(starter.action_id) or -1, tonumber(followup.action_id) or -1),
        revision = 2,
        title = title,
        short_title = tostring(starter.command) .. " → " .. tostring(followup.command),
        character = character,
        starter = {
            command = starter.command,
            label = starter.label,
            action_ids = starter.action_ids or { starter.action_id }
        },
        followups = {
            {
                id = "selected",
                command = followup.command,
                label = followup.label,
                action_ids = followup.action_ids or { followup.action_id },
                derived = followup.is_derived == true
            }
        },
        opponent_strategy = { id = "random_guard", label = "随机防御" },
        contact = { hit_damage_types = { 3 }, block_damage_types = { 30 } },
        rules = {
            hit_confirm_frames = 45,
            block_confirm_frames = 24,
            followup_hit_frames = 45,
            minimum_combo_count = 2,
            neutral_reset_frames = 3
        }
    })
end

function Catalog.empty()
    return prepare_case({
        id = "unavailable",
        revision = 2,
        title = "等待当前角色出招表",
        short_title = "等待角色",
        character = {},
        starter = { command = "--", action_ids = { -999999 } },
        followups = { { id = "selected", command = "--", action_ids = { -999998 } } },
        opponent_strategy = { id = "random_guard", label = "随机防御" },
        contact = { hit_damage_types = { 3 }, block_damage_types = { 30 } },
        rules = {}
    })
end

return Catalog
