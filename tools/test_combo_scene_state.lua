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
assert(SceneState.requires_timeline_catch_up(first) == false,
    "an ordinary portable scene must restore state without consuming hitstop inputs")

first.recorded_by = nil
first.scene_state.recorded_by = 1
roles = SceneState.resolve_roles(first, 0)
assert(roles.actor.scene_side == "p2" and roles.actor.player_index == 0,
    "scene recorded_by must be used when the step alias is absent")
assert(roles.defender.scene_side == "p1" and roles.defender.player_index == 1,
    "recorded P1 must become the defender for a P2 recording")
assert(SceneState.defender_is_burnout(first) == true, "recorded_by must orient defender burnout")
assert(SceneState.requires_timeline_catch_up(first) == true,
    "defender burnout must retain the legacy missed-input-hook workaround")

assert(SceneState.resolve_roles({}, 0) == nil, "missing scene_state must stay compatible")
local legacy_only = {
    recorded_by = 1,
    snapshot_gauges = {
        attacker = { current_hp = 2500, heal_hp = 2500, max_hp = 10000 },
        victim = { current_hp = 7000, heal_hp = 9000, max_hp = 10000 },
        defender_drive = 0,
        defender_burnout = true,
    },
}
local legacy_roles = SceneState.resolve_roles(legacy_only, 0)
assert(legacy_roles.actor.scene_side == "p2"
    and SceneState.resources(legacy_roles.actor).hp == 2500,
    "snapshot-only WTT files must restore the recorded actor by role")
local legacy_defender_resources = SceneState.resources(legacy_roles.defender)
assert(legacy_defender_resources.hp == 7000
    and legacy_defender_resources.heal_hp == 9000
    and legacy_defender_resources.drive == 0,
    "snapshot-only WTT files must retain defender virtual damage and Drive")
assert(SceneState.status(legacy_roles.defender).burnout == true,
    "snapshot-only WTT files must retain defender burnout")

local conflicting = {
    recorded_by = 0,
    scene_state = {
        recorded_by = 0,
        players = {
            p1 = { resources = { hp = 10000 } },
            p2 = {
                resources = { hp = 8000, drive = 30000 },
                status = { burnout = false },
            },
        },
    },
    snapshot_gauges = {
        attacker = { current_hp = 2500, heal_hp = 2500, max_hp = 10000 },
        victim = { current_hp = 8000, heal_hp = 9000, max_hp = 10000 },
        defender_drive = 0,
        defender_burnout = true,
    },
}
local conflicting_roles = SceneState.resolve_roles(conflicting, 0)
assert(SceneState.resources(conflicting_roles.actor).hp == 10000,
    "V2 scene_state must outrank stale legacy HP")
assert(SceneState.resources(conflicting_roles.defender).heal_hp == 9000,
    "a matching legacy HP snapshot may extend V2 with virtual damage")
assert(SceneState.resources(conflicting_roles.defender).drive == 30000
    and SceneState.status(conflicting_roles.defender).burnout == false,
    "V2 Drive and status must outrank stale legacy fields")
assert(SceneState.synchronize_legacy_snapshot(conflicting) == 4,
    "transcription must report each legacy field synchronized to the V2 scene")
assert(conflicting.snapshot_gauges.attacker.current_hp == 10000
    and conflicting.snapshot_gauges.attacker.heal_hp == 10000
    and conflicting.snapshot_gauges.victim.heal_hp == 9000
    and conflicting.snapshot_gauges.defender_drive == 30000
    and conflicting.snapshot_gauges.defender_burnout == false,
    "synchronization must preserve virtual-damage delta while removing conflicts")
assert(SceneState.requires_timeline_catch_up({
        snapshot_gauges = { defender_burnout = true },
    }) == true,
    "legacy burnout snapshots must retain timeline catch-up compatibility")
assert(SceneState.requires_timeline_catch_up({ has_piyo = true }) == true,
    "legacy stun recordings must retain timeline catch-up compatibility")

print("combo scene state tests passed")
