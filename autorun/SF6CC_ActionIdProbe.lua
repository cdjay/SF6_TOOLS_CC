-- SF6CC_ActionIdProbe.lua
-- Temporary diagnostic panel for identifying live action IDs in training mode.

local imgui = imgui
local re = re
local GameState = require("func/GameState")

local state = {
    p1 = { current_id = -1, last_id = -1, frame = 0, input = 0, state_flags = -1 },
    p2 = { current_id = -1, last_id = -1, frame = 0, input = 0, state_flags = -1 },
}

local function read_player(player, output)
    output.current_id, output.frame, output.input, output.state_flags = -1, 0, 0, -1
    if not player then return end

    pcall(function()
        local player_type = player:get_type_definition()
        local input = player_type:get_field("pl_input_new"):get_data(player) or 0
        local switches = player_type:get_field("pl_sw_new"):get_data(player) or 0
        output.input = input | switches

        local act_param = player:get_field("mpActParam")
        local action_part = act_param and act_param:get_field("ActionPart") or nil
        local engine = action_part and action_part:get_field("_Engine") or nil
        if not engine then return end

        output.current_id = tonumber(engine:call("get_ActionID")) or -1
        local action_frame = engine:call("get_ActionFrame")
        output.frame = action_frame and tonumber(action_frame:call("ToString()")) or 0

        local param = engine:get_field("mParam")
        local flags = param and param:get_type_definition():get_field("state_flags") or nil
        output.state_flags = flags and tonumber(flags:get_data(param)) or -1
    end)

    -- Idle, walk and dash IDs are not useful for this investigation. Keep the
    -- last meaningful action visible after its animation has already ended.
    if output.current_id > 50 then output.last_id = output.current_id end
end

re.on_frame(function()
    read_player(GameState.p1, state.p1)
    read_player(GameState.p2, state.p2)
end)

local function draw_player(label, value)
    imgui.text(label .. " 当前 Action ID: " .. tostring(value.current_id)
        .. "  帧: " .. tostring(value.frame))
    imgui.text(label .. " 最近非待机 Action ID: " .. tostring(value.last_id)
        .. "  输入: 0x" .. string.format("%X", value.input)
        .. "  state_flags: " .. tostring(value.state_flags))
end

re.on_draw_ui(function()
    if not imgui.tree_node("SF6CC 动作 ID 探针") then return end
    imgui.text_colored("在目标状态按一次 MK / 2MK，记录“最近非待机 Action ID”。", 0xFF00FFFF)
    draw_player("P1", state.p1)
    draw_player("P2", state.p2)
    if imgui.button("清空最近动作") then
        state.p1.last_id = -1
        state.p2.last_id = -1
    end
    imgui.tree_pop()
end)
