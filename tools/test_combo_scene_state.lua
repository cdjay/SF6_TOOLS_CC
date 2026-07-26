package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local SceneState = require("func/ComboTrials/SceneState")

local first = {
    recorded_by = 0,
    scene_state = {
        schema = "xt.combo_trial.scene.v2",
        players = {
            p1 = { resources = { hp = 2000 }, status = { burnout = true } },
            p2 = { resources = { hp = 9000 }, status = { stance = "crouching" } },
        },
    },
}

local roles = SceneState.resolve_roles(first, 1)
assert(roles.actor.scene_side == "p1" and roles.actor.player_index == 1,
    "recorded P1 actor must map to the current playing side")
assert(roles.defender.scene_side == "p2" and roles.defender.player_index == 0,
    "recorded P2 defender must map opposite the current playing side")
assert(SceneState.resources(roles.actor).hp == 2000, "actor resources must follow role mapping")
assert(SceneState.status(roles.defender).stance == "crouching", "defender status must follow role mapping")
assert(SceneState.defender_is_burnout(first) == false, "only the defender burnout state may drive stun demo rules")

first.recorded_by = nil
first.scene_state.recorded_by = 1
roles = SceneState.resolve_roles(first, 0)
assert(roles.actor.scene_side == "p2" and roles.actor.player_index == 0,
    "scene recorded_by must be used when the step alias is absent")
assert(roles.defender.scene_side == "p1" and roles.defender.player_index == 1,
    "recorded P1 must become the defender for a P2 recording")
assert(SceneState.defender_is_burnout(first) == true, "recorded_by must orient defender burnout")

assert(SceneState.resolve_roles({}, 0) == nil, "missing scene_state must stay compatible")

print("combo scene state tests passed")
