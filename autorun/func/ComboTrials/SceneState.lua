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

local function legacy_gauges(first_step)
    local gauges = type(first_step) == "table" and first_step.snapshot_gauges or nil
    return type(gauges) == "table" and gauges or nil
end

local function shallow_copy(value)
    local output = {}
    for key, child in pairs(type(value) == "table" and value or {}) do
        output[key] = child
    end
    return output
end

function SceneState.resolve_roles(first_step, playing_player)
    if type(first_step) ~= "table" then return nil end
    local scene = first_step.scene_state
    local gauges = legacy_gauges(first_step)
    if type(scene) ~= "table" and gauges == nil then return nil end
    scene = type(scene) == "table" and scene or {}

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
            first_step = first_step,
        },
        defender = {
            role = "defender",
            scene_side = defender_side,
            player_index = 1 - actor_index,
            state = scene_player(scene, defender_side),
            first_step = first_step,
        },
    }
end

function SceneState.resources(role)
    local role_name = type(role) == "table" and role.role or nil
    local state = type(role) == "table" and role.state or nil
    local resources = type(state) == "table" and type(state.resources) == "table"
        and state.resources or nil
    local output = shallow_copy(resources)
    local gauges = legacy_gauges(type(role) == "table" and role.first_step or nil)
    local snapshot = gauges and (
        role_name == "actor" and gauges.attacker
            or (role_name == "defender" and gauges.victim or nil)
    ) or nil
    local snapshot_hp = type(snapshot) == "table" and tonumber(snapshot.current_hp) or nil

    -- scene_state is the V2 authority. Legacy HP fills absent scene data, and
    -- may add heal_hp only when both formats agree on current HP.
    if output.hp == nil and snapshot_hp ~= nil then
        output.hp = snapshot_hp
        output.heal_hp = tonumber(snapshot.heal_hp)
        output.max_hp = tonumber(snapshot.max_hp)
    elseif snapshot_hp ~= nil and tonumber(output.hp) == snapshot_hp then
        if output.heal_hp == nil then output.heal_hp = tonumber(snapshot.heal_hp) end
        if output.max_hp == nil then output.max_hp = tonumber(snapshot.max_hp) end
    end
    if role_name == "defender" and output.drive == nil and gauges then
        output.drive = tonumber(gauges.defender_drive)
    end
    return next(output) ~= nil and output or nil
end

function SceneState.status(role)
    local role_name = type(role) == "table" and role.role or nil
    local state = type(role) == "table" and role.state or nil
    local status = type(state) == "table" and type(state.status) == "table"
        and state.status or nil
    local output = shallow_copy(status)
    local gauges = legacy_gauges(type(role) == "table" and role.first_step or nil)
    if role_name == "defender" and output.burnout == nil
        and gauges and type(gauges.defender_burnout) == "boolean" then
        output.burnout = gauges.defender_burnout
    end
    return next(output) ~= nil and output or nil
end

local function synchronize_hp_snapshot(snapshot, scene_hp)
    if type(snapshot) ~= "table" or tonumber(scene_hp) == nil then return 0 end
    local hp = tonumber(scene_hp)
    local old_hp = tonumber(snapshot.current_hp)
    local old_heal = tonumber(snapshot.heal_hp)
    local heal_delta = old_hp and old_heal and math.max(0, old_heal - old_hp) or 0
    local changed = 0
    if old_hp ~= hp then
        snapshot.current_hp = hp
        changed = changed + 1
    end
    if old_heal ~= nil then
        local synchronized_heal = hp + heal_delta
        local max_hp = tonumber(snapshot.max_hp)
        if max_hp then synchronized_heal = math.min(max_hp, synchronized_heal) end
        if old_heal ~= synchronized_heal then
            snapshot.heal_hp = synchronized_heal
            changed = changed + 1
        end
    end
    return changed
end

-- Transcribed V2 files retain legacy snapshot_gauges for WTT readers. When
-- both formats exist, rewrite only the already-present legacy fields so both
-- readers receive the same scene settings.
function SceneState.synchronize_legacy_snapshot(first_step)
    if type(first_step) ~= "table" or type(first_step.scene_state) ~= "table"
        or type(first_step.snapshot_gauges) ~= "table" then
        return 0
    end
    local roles = SceneState.resolve_roles(first_step, 0)
    if not roles then return 0 end
    local gauges = first_step.snapshot_gauges
    local actor_state = roles.actor.state
    local defender_state = roles.defender.state
    local actor_resources = type(actor_state) == "table" and actor_state.resources or nil
    local defender_resources =
        type(defender_state) == "table" and defender_state.resources or nil
    local defender_status = type(defender_state) == "table" and defender_state.status or nil
    local changed = 0

    changed = changed + synchronize_hp_snapshot(
        gauges.attacker,
        type(actor_resources) == "table" and actor_resources.hp or nil
    )
    changed = changed + synchronize_hp_snapshot(
        gauges.victim,
        type(defender_resources) == "table" and defender_resources.hp or nil
    )
    if gauges.defender_drive ~= nil
        and type(defender_resources) == "table"
        and tonumber(defender_resources.drive) ~= nil
        and tonumber(gauges.defender_drive) ~= tonumber(defender_resources.drive) then
        gauges.defender_drive = tonumber(defender_resources.drive)
        changed = changed + 1
    end
    if gauges.defender_burnout ~= nil
        and type(defender_status) == "table"
        and type(defender_status.burnout) == "boolean"
        and gauges.defender_burnout ~= defender_status.burnout then
        gauges.defender_burnout = defender_status.burnout
        changed = changed + 1
    end
    return changed
end

function SceneState.defender_is_burnout(first_step)
    local roles = SceneState.resolve_roles(first_step, 0)
    local status = roles and SceneState.status(roles.defender) or nil
    return type(status) == "table" and status.burnout == true
end

function SceneState.requires_timeline_catch_up(first_step)
    if type(first_step) ~= "table" then return false end
    local gauges = first_step.snapshot_gauges
    return first_step.has_piyo == true
        or (type(gauges) == "table" and gauges.defender_burnout == true)
        or SceneState.defender_is_burnout(first_step)
end

return SceneState
