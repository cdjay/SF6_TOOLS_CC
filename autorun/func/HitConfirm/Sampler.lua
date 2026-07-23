local Sampler = {}
Sampler.__index = Sampler

local function numeric_field(object, field_name)
    if not object then return 0 end
    local ok, value = pcall(function() return object:get_field(field_name) end)
    if not ok or value == nil then return 0 end
    return tonumber(value) or tonumber(tostring(value)) or 0
end

local function action_id(player)
    if not player then return -1 end
    local result = -1
    pcall(function()
        local action_param = player.mpActParam
        local action_part = action_param and action_param.ActionPart
        local engine = action_part and action_part._Engine
        if engine then result = tonumber(engine:get_ActionID()) or -1 end
    end)
    return result
end

local function read_input_type(player_index)
    local input_type = nil
    pcall(function()
        local manager = sdk.get_managed_singleton("app.training.TrainingManager")
        local training_data = manager and manager:get_field("_tData")
        if not training_data then return end
        local containers = { training_data:get_field("SelectMenu"), training_data:get_field("ParameterSetting") }
        for _, container in ipairs(containers) do
            local player_data = container and container.PlayerDatas and container.PlayerDatas[player_index or 0]
            if player_data then
                local field = player_data:get_type_definition():get_field("InputType")
                local value = field and field:get_data(player_data) or player_data.InputType
                input_type = tonumber(value) or tonumber(tostring(value))
                if input_type ~= nil then return end
            end
        end
    end)
    return input_type
end

function Sampler.new(game_state)
    return setmetatable({ game_state = game_state, control_mode = "unknown", control_refresh = 0 }, Sampler)
end

function Sampler:read(case)
    local game_state = self.game_state
    local p1, p2 = game_state.p1, game_state.p2
    local combo_count = numeric_field(p1, "combo_cnt")
    local damage_type = numeric_field(p2, "damage_type")
    local hit_stop = numeric_field(p2, "hit_stop")
    local contact = nil
    if hit_stop > 0 then
        if case._block_damage_types[damage_type] then
            contact = "block"
        elseif case._hit_damage_types[damage_type] or combo_count > 0 then
            contact = "hit"
        end
    end

    self.control_refresh = self.control_refresh - 1
    if self.control_refresh <= 0 then
        self.control_refresh = 300
        local input_type = read_input_type(0)
        self.control_mode = input_type == 0 and "classic" or (input_type == 1 and "modern" or "unknown")
    end

    local character_info = _G._shared_player_info and _G._shared_player_info[0] or nil
    return {
        frame = tonumber(game_state.frame) or 0,
        action_id = action_id(p1),
        combo_count = combo_count,
        damage_type = damage_type,
        hit_stop = hit_stop,
        contact = contact,
        character_id = character_info and tonumber(character_info.id) or nil,
        character_key = character_info and character_info.key or nil,
        control_mode = self.control_mode
    }
end

return Sampler
