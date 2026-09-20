local M = {}

local function field(obj, name)
    if obj == nil then return nil end
    return obj:get_field(name)
end

local function number(value)
    local n = tonumber(value)
    if n and n == n and math.abs(n) <= 9007199254740991 then return n end
    return nil
end

local function required(value, name)
    assert(value ~= nil, "unavailable: " .. name)
    return value
end

local function raw_fixed(value)
    return number(field(value, "v"))
end

local engine_fields = {
    { "engine_action_id", "id" },
    { "engine_action_frame_raw", "frame", true },
    { "engine_frame_num_raw", "frame_num", true },
    { "engine_margin_start_raw", "margin_start_frame", true },
    { "engine_speed_raw", "speed", true },
    { "engine_state_flags", "state_flags" },
    { "engine_battle_version", "battle_version" },
    { "engine_loop_count", "loop_count" },
    { "engine_style_index", "style_index" },
}

local function meter_cell(item)
    local cells = field(item, "frameMeterDataList")
    if not cells then return {} end
    local size = number(cells:get_size())
    local index = number(field(item, "currentFrame"))
    local out = { display_meter_size = size, display_meter_index = index }
    -- Only the observed 80-cell buffer is supported; never wrap an invalid cursor.
    if size ~= 80 or not index or index % 1 ~= 0 or index < 0 or index >= size then return out end
    local cell = cells:get_element(index)
    if not cell then return out end
    local frame_type = number(field(cell, "FrameType"))
    if not frame_type or frame_type % 1 ~= 0 then return out end
    local flags = { display_meter_empty = "IsEmpty", display_meter_changed = "IsChanged",
        display_meter_end = "IsEnd", display_meter_not_add = "IsNotAdd", display_meter_not_whole = "IsNotWhole" }
    local read = { display_meter_type = frame_type }
    for name, native in pairs(flags) do
        local value = field(cell, native)
        if type(value) ~= "boolean" then return out end
        read[name] = value and 1 or 0
    end
    if number(field(item, "currentFrame")) ~= index then return {} end
    for name, value in pairs(read) do out[name] = value end
    return out
end

function M.new(sdk_api)
    -- Only type/field definitions are retained. Scene-owned objects stay local to a sample.
    local battle = required(sdk_api.find_type_definition("gBattle"), "gBattle")
    local definitions = {}
    for _, name in ipairs({ "Player", "Team", "Game", "Round" }) do
        definitions[name] = required(battle:get_field(name), "gBattle." .. name)
    end
    local sampler = {}
    local function singleton(name) return sdk_api.get_managed_singleton(name) end
    local function static(name) return definitions[name]:get_data(nil) end

    function sampler:identity()
        local manager = singleton("app.BattleReplayDataManager")
        local core = field(manager, "<BattleCore_>k__BackingField")
        local controller = field(core, "m_BRControl")
        local replay = field(controller, "_BattleReplay")
        if not replay then return nil end
        -- Despite its name, _CurrentReplayID is the zero-based list index,
        -- not the public CFN identifier stored on ReplayingData.ReplayID.
        local index = number(field(manager, "_CurrentReplayID"))
        local list = field(manager, "_ReplayList")
        local count = number(field(list, "_size"))
        local items = field(list, "_items")
        if not index or index % 1 ~= 0 or index < 0 or not count or count % 1 ~= 0
            or index >= count or not items or count > items:get_size() then return nil end
        local selected = items:get_element(index)
        local id = field(selected, "ReplayID")
        if type(id) ~= "string" or id == "" then return nil end
        local version = number(field(field(field(selected, "ReplayData"), "ReplayInfo"), "Version"))
        if version and (version < 0 or version % 1 ~= 0) then version = nil end
        return { replay = replay, replay_id = id, version = version,
            replay_list_index = index, replaying_data = selected, core = core }
    end

    function sampler:context()
        local flow = field(field(singleton("app.bFlowManager"), "m_flow_work"), "_FlowMap")
        if number(field(flow, "_ID")) ~= 10 then return nil end
        local context = self:identity()
        if not context or context.replay:call("get_Replay") ~= true then return nil end
        return context
    end

    function sampler:position(context)
        local ok, result = pcall(function()
            local round = number(context.replay:call("get_ReplayRound"))
            local frame = number(context.replay:call("get_ReplayTime"))
            local after = number(context.replay:call("get_ReplayRound"))
            if not round or round ~= after or round < 0 or round % 1 ~= 0 or not frame or frame < 0 or frame % 1 ~= 0 then return nil end
            return { round = round, frame = frame }
        end)
        return ok and result or nil
    end

    function sampler:local_side(context)
        local ok, side=pcall(function()
            local login=singleton("app.LoginManager")
            if not login or login:call("get_IsLogin")~=true then return nil end
            local id=number(login:call("get_ShortId"))
            if not id or id<=0 then return nil end
            local network=field(context.replaying_data,"ReplayInfo")
            local found
            for s=1,2 do
                local player=field(field(network,"player"..s.."_info"),"player")
                if number(field(player,"short_id"))==id then
                    if found then return nil end
                    found=s
                end
            end
            return found
        end)
        return ok and side or nil
    end

    function sampler:metadata(context)
        local selected = required(context.replaying_data, "selected replay metadata")
        assert(field(selected, "ReplayID") == context.replay_id, "replay identity changed during sample")
        local info = required(field(field(selected, "ReplayData"), "ReplayInfo"), "replay info")
        local network = field(selected, "ReplayInfo")
        local metadata = {
            replay_id = context.replay_id, replay_list_index = context.replay_list_index,
            version = number(field(info, "Version")),
            round_count = number(field(info, "RoundNum")), stage_id = number(field(info, "StageId")),
            random_seed = number(field(info, "RandomSeed")), players = {},
            source = "BattleReplayDataManager._ReplayList", hook = "app.BattleFlow.UpdateFrameMain:post",
            recovery_fields_profile = "raw_player_recovery_v1",
            engine_fields_profile = "raw_engine_param_v1",
            frame_meter_profile = "native_cursor_cell_v1",
        }
        for side = 1, 2 do
            local player = required(field(network, "player" .. side .. "_info"), "player metadata")
            local personal = field(player, "player")
            metadata.players[side] = {
                name = field(personal, "fighter_id"), short_id = number(field(personal, "short_id")),
                fighter_id = required(number(field(player, "character_id")), "fighter_id"),
                playing_fighter_id = number(field(player, "playing_character_id")),
                control_mode = required(number(field(player, "battle_input_type")), "control_mode"),
                league_rank = number(field(player, "league_rank")),
                league_point = number(field(player, "league_point")), master_rating = number(field(player, "master_rating")),
            }
        end
        return metadata
    end

    function sampler:sample(context, render_tick, thread_id, result)
        local game, round = required(static("Game"), "Game"), required(static("Round"), "Round")
        local players = required(field(static("Player"), "mcPlayer"), "players")
        local teams = required(field(static("Team"), "mcTeam"), "teams")
        local objects = { required(players:get_element(0), "P1"), required(players:get_element(1), "P2") }
        local values = {
            round = number(context.replay:call("get_ReplayRound")),
            replay_frame = number(context.replay:call("get_ReplayTime")),
            battle_round = number(field(round, "RoundNo")), stage_frame = number(field(game, "stage_timer")),
            render_tick = render_tick, thread_id = thread_id, update_result = result,
            fight_st = number(field(game, "fight_st")), play_timer = number(field(round, "play_timer")),
            play_timer_ms = number(field(round, "play_timer_ms")),
        }
        for side, player in ipairs(objects) do
            local prefix = "p" .. side .. "."
            for _, name in ipairs({ "vital_new", "vital_old", "vital_max", "heal_new", "focus_new", "focus_max",
                "act_st", "hit_st", "hit_st_old", "hit_stop", "damage_type", "combo_cnt", "pl_input_new", "pl_sw_new" }) do
                values[prefix .. name] = required(number(field(player, name)), name)
            end
            local team = required(teams:get_element(side - 1), "team")
            for _, name in ipairs({ "mSuperGauge", "mSuperGaugeMax", "mSingleDamage", "mComboDamage", "mComboCount" }) do
                values[prefix .. name] = required(number(field(team, name)), name)
            end
            local engine = required(field(field(field(player, "mpActParam"), "ActionPart"), "_Engine"), "action engine")
            values[prefix .. "action_id"] = required(number(engine:call("get_ActionID")), "action id")
            values[prefix .. "action_frame_raw"] = required(raw_fixed(engine:call("get_ActionFrame")), "action frame")
            -- Raw evidence only: margin, duration and flags do not prove actionability.
            -- Keep a failed block absent; never export partially read native state after an exception.
            local engine_values = {}
            local engine_ok = pcall(function()
                local param = field(engine, "mParam")
                if not param then return end
                for _, spec in ipairs(engine_fields) do
                    local value = field(param, spec[2])
                    local n
                    if spec[3] then n = raw_fixed(value) else n = number(value) end
                    if n and n % 1 == 0 then engine_values[spec[1]] = n end
                end
            end)
            if engine_ok then
                for name, value in pairs(engine_values) do values[prefix .. name] = value end
            end
            local pos = required(field(player, "pos"), "position")
            for _, axis in ipairs({ "x", "y", "z" }) do
                values[prefix .. axis .. "_raw"] = required(raw_fixed(field(pos, axis)), axis)
            end
            local facing = field(player, "rl_dir")
            assert(type(facing) == "boolean", "facing is not boolean")
            values[prefix .. "facing_right"] = facing and 1 or 0
            -- These are evidence fields, not a derived "can attack" predicate.
            -- Missing values stay absent, so export marks them unavailable, never zero.
            for _, name in ipairs({ "guard_time", "damage_time", "pose_st" }) do
                local ok, value = pcall(function() return number(field(player, name)) end)
                if ok and value and value % 1 == 0 then values[prefix .. name] = value end
            end
            local move_ok, move = pcall(function() return field(player, "free_to_move") end)
            if move_ok and type(move) == "boolean" then values[prefix .. "free_to_move"] = move and 1 or 0 end
            local source = field(player, "damage_pl_add")
            values[prefix .. "damage_source"] = 0
            if source then
                values[prefix .. "damage_source"] = -1
                for source_side, object in ipairs(objects) do
                    if source:get_address() == object:get_address() then values[prefix .. "damage_source"] = source_side end
                end
            end
        end
        -- Display data is optional and may lag the simulation; never stamp it with the battle clock.
        local display_values = {}
        local display_ok = pcall(function()
            local tm = singleton("app.training.TrainingManager")
            local display = tm and tm:call("get_DisplayFunc")
            local data = field(display, "_gData")
            if not data then return end
            local names = { display_prev_frame = "PrevFrame", display_stun_frame = "StunFrame",
                display_attack_side = "AtkSide", meter_frame = "FMCurrentFrame",
                meter_start_frame = "FMStartFrame", meter_stop_frame = "FMStopFrame" }
            for name, native in pairs(names) do display_values[name] = number(field(data, native)) end
            local active_ok, active = pcall(function() return number(field(data, "FMActive")) end)
            if active_ok then display_values.meter_active = active end
            local pd = field(data, "PlayerDatas")
            if not pd then return end
            local meter_values = {}
            for side = 1, 2 do
                local item = pd:get_element(side - 1)
                local names_p = { display_current_frame = "currentFrame", display_prev_action_frame = "prevActionFrame",
                    display_atk_margin = "atkFrameMarginFrame", display_hit_id = "hitID" }
                for name, native in pairs(names_p) do display_values["p" .. side .. "." .. name] = number(field(item, native)) end
                local cell_ok, cell_values = pcall(meter_cell, item)
                if cell_ok then
                    for name, value in pairs(cell_values) do meter_values["p" .. side .. "." .. name] = value end
                end
            end
            -- This display clock is independent of the battle clock; keep stale-but-stable data labelled.
            if display_values.display_prev_frame ~= nil
                and number(field(data, "PrevFrame")) == display_values.display_prev_frame then
                for name, value in pairs(meter_values) do display_values[name] = value end
            end
        end)
        if display_ok then for key, value in pairs(display_values) do values[key] = value end end
        return values
    end
    return sampler
end

return M
