package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local p1 = {
    vital_new = 10000,
    vital_old = 10000,
    heal_new = 10000,
    heal_old = 10000,
    vital_max = 10000,
}
local p2 = {
    vital_new = 10000,
    vital_old = 10000,
    heal_new = 10000,
    heal_old = 10000,
    vital_max = 10000,
}
package.loaded["func/GameState"] = { p1 = p1, p2 = p2 }
package.loaded["func/ComboTrials/SceneState"] = {
    resolve_roles = function()
        return {
            actor = { player_index = 0 },
            defender = { player_index = 1 },
        }
    end,
    resources = function(role)
        if role.player_index == 0 then
            return { hp = 4200, heal_hp = 4500 }
        end
        return nil
    end,
    status = function()
        return nil
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
    Vital_Timer = 90,
    Is_Vital_Infinity = true,
    Is_Vital_No_Recovery = false,
    Is_Vital_Recovery_Timer = true,
    Is_KO = true,
    Is_Point_Lock = true,
})
local param_func = {
    call = function(_, method, player_index, value)
        if method == "SetVitalPoint" and player_index == 0 then
            player_params.Vital_Point = value
        end
    end,
}
local tf_parameter_setting = {
    apply_count = 0,
    call = function(self, method)
        if method == "bApply" then self.apply_count = self.apply_count + 1 end
    end,
}
local training_manager = object({ _IsReqRefresh = false })
local parameter_setting = object({})
local training_data = object({ ParameterSetting = parameter_setting })
training_manager._tData = training_data
local backups = {}

sdk = {
    find_type_definition = function()
        return { get_field = function() return nil end }
    end,
    get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return training_manager end
        return nil
    end,
}

function get_training_parameter_probe_objects(player_index)
    if player_index ~= 0 then return { tm = training_manager, tf_ps = tf_parameter_setting } end
    return {
        tm = training_manager,
        training_data = training_data,
        parameter_setting = parameter_setting,
        player_params = player_params,
        param_func = param_func,
        tf_ps = tf_parameter_setting,
    }
end

function ct_hp_backup_training_setting_once(player_index)
    backups[player_index] = {
        Vital_Point = player_params.Vital_Point,
        Vital_Timer = player_params.Vital_Timer,
        Is_Vital_Infinity = player_params.Is_Vital_Infinity,
        Is_Vital_No_Recovery = player_params.Is_Vital_No_Recovery,
        Is_Vital_Recovery_Timer = player_params.Is_Vital_Recovery_Timer,
        Is_KO = player_params.Is_KO,
        Is_Point_Lock = player_params.Is_Point_Lock,
    }
end

DRIVE_SETTING_FIELDS = {}
SUPER_SETTING_FIELDS = {}

local SceneStateRuntime = require("func/ComboTrials/SceneStateRuntime")
local trial_state = {}
assert(SceneStateRuntime.apply({}, 0, trial_state, true) == true,
    "scene state application must report the actor HP change")
assert(player_params.Vital_Point == 42,
    "scene state must publish the recorded HP percentage")
assert(player_params.Is_Vital_Infinity == false
        and player_params.Is_Vital_No_Recovery == true
        and player_params.Is_Vital_Recovery_Timer == false
        and player_params.Vital_Timer == 0
        and player_params.Is_KO == false
        and player_params.Is_Point_Lock == false,
    "scene HP ownership must disable training auto-recovery and conflicting locks")
assert(tf_parameter_setting.apply_count == 0 and training_manager._IsReqRefresh == true,
    "scene HP settings must request one refresh without invoking tf_ParameterSetting.bApply")
assert(p1.vital_new == 4200 and p1.vital_old == 4200
        and p1.heal_new == 4500 and p1.heal_old == 4500,
    "scene runtime must preserve exact current and recoverable HP")
assert(backups[0].Vital_Point == 100
        and backups[0].Is_Vital_Infinity == true
        and backups[0].Is_Vital_No_Recovery == false,
    "scene HP settings must be backed up before mutation")
assert(trial_state._hp_snapshot_applied_current_session == true,
    "scene HP application must retain restoration ownership")

training_manager._IsReqRefresh = false
training_data.ParameterSetting = object({})
local stale_trial_state = {}
assert(SceneStateRuntime.apply({}, 0, stale_trial_state, true) == true,
    "live scene resources may still apply while a stale refresh request fails closed")
assert(training_manager._IsReqRefresh == false
        and stale_trial_state._scene_parameter_refresh.requested == false
        and stale_trial_state._scene_parameter_refresh.reason == "stale_parameter_setting"
        and stale_trial_state._scene_parameter_refresh_retry == true
        and stale_trial_state._pending_reinject_settings == true
        and tf_parameter_setting.apply_count == 0,
    "scene refresh must never invoke or request through a replaced ParameterSetting")

training_data.ParameterSetting = parameter_setting
assert(SceneStateRuntime.apply({}, 0, stale_trial_state, false) == true,
    "a failed scene refresh must retry after ParameterSetting identity stabilizes")
assert(training_manager._IsReqRefresh == true
        and stale_trial_state._scene_parameter_refresh.requested == true
        and stale_trial_state._scene_parameter_refresh.reason == "refresh_requested"
        and stale_trial_state._scene_parameter_refresh_retry == false
        and stale_trial_state._pending_reinject_settings == true
        and tf_parameter_setting.apply_count == 0,
    "the stable retry must request refresh and retain one post-refresh reinjection")

print("combo scene state runtime tests passed")
