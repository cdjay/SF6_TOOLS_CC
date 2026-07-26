local SceneState = {
    name = "ComboTrials.SceneState",
    SCHEMA_V2 = "xt.combo_trial.scene.v2",
}

local function normalized_player_index(value)
    return tonumber(value) == 1 and 1 or 0
end

local function scene_player(scene, side)
    if type(scene) ~= "table" or type(scene.players) ~= "table" then return nil end
    local player = scene.players[side]
    return type(player) == "table" and player or nil
end

function SceneState.resolve_roles(first_step, playing_player)
    if type(first_step) ~= "table" then return nil end
    local scene = first_step.scene_state
    if type(scene) ~= "table" then return nil end

    local recorded_by = normalized_player_index(first_step.recorded_by or scene.recorded_by)
    local actor_side = recorded_by == 1 and "p2" or "p1"
    local defender_side = recorded_by == 1 and "p1" or "p2"
    local actor_index = normalized_player_index(playing_player)

    return {
        scene = scene,
        recorded_by = recorded_by,
        actor = {
            role = "actor",
            scene_side = actor_side,
            player_index = actor_index,
            state = scene_player(scene, actor_side),
        },
        defender = {
            role = "defender",
            scene_side = defender_side,
            player_index = 1 - actor_index,
            state = scene_player(scene, defender_side),
        },
    }
end

function SceneState.resources(role)
    local state = type(role) == "table" and role.state or nil
    return type(state) == "table" and type(state.resources) == "table"
        and state.resources or nil
end

function SceneState.status(role)
    local state = type(role) == "table" and role.state or nil
    return type(state) == "table" and type(state.status) == "table"
        and state.status or nil
end

function SceneState.defender_is_burnout(first_step)
    local roles = SceneState.resolve_roles(first_step, 0)
    local status = roles and SceneState.status(roles.defender) or nil
    return type(status) == "table" and status.burnout == true
end

return SceneState
