package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local p1 = { vital_new = 10000, vital_old = 10000, heal_new = 10000, vital_max = 10000 }
local p2 = { vital_new = 9000, vital_old = 9000, heal_new = 9000, vital_max = 10000 }
package.loaded["func/GameState"] = { p1 = p1, p2 = p2 }
package.loaded["func/ComboTrials/SceneState"] = {
    resolve_roles = function()
        return { actor = { player_index = 0 } }
    end,
    resources = function()
        return { hp = 4200 }
    end,
}
local restored_live_resources = false
package.loaded["func/ComboTrials/SceneStateRuntime"] = {
    restore_live_resources = function()
        restored_live_resources = true
    end,
}

local function object(fields)
    fields = fields or {}
    function fields:get_field(name)
        return self[name]
    end
    return fields
end

local player_params = object({
    Vital_Type = 0,
    Vital_Point = 100,
    Vital_Point_Type = 0,
    Vital_Timer = 0,
    Is_Vital_Infinity = false,
    Is_Vital_No_Recovery = false,
    Is_Vital_Recovery_Timer = false,
    Is_KO = false,
    Is_Point_Lock = false,
})
local param_func = {}
function param_func:get_type_definition()
    return {
        get_full_name = function() return "app.training.ParamFunc" end,
        get_method = function() return {} end,
    }
end
function param_func:call(method, player_index, value)
    if method == "SetVitalPoint" and player_index == 0 then
        player_params.Vital_Point = value
    end
end

local parameter_setting = object({
    ParamFunc = param_func,
    PlayerDatas = { [0] = player_params, [1] = object({ Vital_Point = 100 }) },
})
local training_data = object({ ParameterSetting = parameter_setting })
local tf_parameter_setting = {
    apply_count = 0,
    get_type_definition = function()
        return { get_full_name = function() return "app.training.tf_ParameterSetting" end }
    end,
    call = function(self, method)
        if method == "bApply" then self.apply_count = self.apply_count + 1 end
    end,
}
local entries = {
    call = function(_, method, index)
        if method == "get_Count" then return 1 end
        if method == "get_Item" and index == 0 then
            return object({ value = tf_parameter_setting })
        end
    end,
}
local training_manager = object({
    _IsReqRefresh = false,
    _tData = training_data,
    _tfFuncs = object({ _entries = entries }),
})

sdk = {
    get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return training_manager end
        return nil
    end,
}

local HpVital = require("func/ComboTrials/HpVital")
local state = {
    sequence = {
        { recorded_by = 0, _xt_meta = { title = "HP fixture" } },
    },
    playing_player = 0,
    current_step = 1,
}
HpVital.init({
    trial_state = state,
    file_system = { diag_log = function() end },
    json = { dump_file = function() end },
    dev_test_state = {},
    debug_path = "unused.json",
    get_engine_frame_count = function() return 123 end,
    is_dev_test_enabled = function() return false end,
})

assert(HpVital.normalize_hp_value(99.6) == 100,
    "HP normalization must retain nearest-integer rounding")
local snapshot = HpVital.read_player_hp_snapshot(p1)
assert(snapshot.current_hp == 10000 and snapshot.max_hp == 10000
        and snapshot.heal_hp == 10000,
    "runtime HP snapshots must retain all available fields")
assert(HpVital.hp_snapshot_to_vital_point({ current_hp = 4200, max_hp = 10000 }) == 42,
    "recorded HP must retain the existing percentage conversion")

state._pending_victim_hp = 1
state._pending_attacker_hp = 2
state._hp_inject_frames = 3
state._saved_vital_p1 = {}
state._saved_vital_p2 = {}
HpVital.clear_trial_vital_state()
assert(state._pending_victim_hp == nil and state._pending_attacker_hp == nil
        and state._hp_inject_frames == 0
        and state._saved_vital_p1 == nil and state._saved_vital_p2 == nil,
    "trial vital cleanup must retain the same state reset")

HpVital.init_hp_restore_attempt("fixture", 0)
assert(state._hp_restore.found == true
        and state._hp_restore.snapshot.current_hp == 4200
        and state._hp_restore.target_player == 0,
    "scene HP discovery must retain actor-side targeting")
assert(HpVital.apply_hp_restore_training_setting_once("fixture_training") == true,
    "training Vital_Point application must report the existing write success")
assert(player_params.Vital_Point == 42
        and state._hp_snapshot_applied_current_session == true
        and state._hp_training_setting_backup.players[0].fields.Vital_Point == 100,
    "training HP writes must preserve backup-before-write ordering")

assert(HpVital.apply_pending_hp_restore_once("fixture_runtime") == true,
    "runtime HP injection must finish the pending restore")
assert(p1.vital_new == 4200 and p1.vital_old == 4200 and p1.heal_new == 4200,
    "runtime HP injection must retain all three field writes")

local restore_debug = HpVital.restore_hp_training_setting_if_needed("fixture_restore", 0)
assert(player_params.Vital_Point == 100
        and restore_debug.bapply_ok == true
        and state._hp_training_setting_backup == nil
        and state._hp_snapshot_applied_current_session == false,
    "training HP restore must replay the backup and clear it after bApply")

state._saved_drive_settings = { [0] = { DG_Type = 2, DG_Point = 4000 } }
state._saved_super_settings = { [0] = { SA_Type = 3, SA_Point = 25000 } }
player_params.DG_Type = 0
player_params.DG_Point = 0
player_params.SA_Type = 0
player_params.SA_Point = 0
HpVital.restore_trial_vital(true)
assert(player_params.DG_Type == 2 and player_params.DG_Point == 4000
        and player_params.SA_Type == 3 and player_params.SA_Point == 25000
        and restored_live_resources == true,
    "trial vital restore must retain gauge restoration and live-resource ordering")

print("combo HP vital tests passed")
