local function managed(object)
    object.get_field = function(self, name) return self[name] end
    object.set_field = function(self, name, value) self[name] = value end
    return object
end

local p1_select = managed({ ManualPosX = -125 })
local p2_select = managed({ ManualPosX = 175 })
local select_menu = managed({
    StartLocation = 2,
    PlayerDatas = { [0] = p1_select, [1] = p2_select },
})
local p1_params = managed({
    Vital_Point = 88,
    Is_Vital_Infinity = true,
    Is_Vital_No_Recovery = false,
    DG_Stock = 6,
    DG_Point = 60000,
    SA_Stock = 2,
    SA_Point = 20000,
})
local parameter_setting = managed({
    PlayerDatas = { [0] = p1_params },
    ParamFunc = managed({
        call = function() return true end,
    }),
})
local guard_dummy = managed({
    GuardType = 4,
    GuardWeight = 7,
    GuardCount = 2,
    IsGuardSwitching = true,
    GuardOnlyType = 1,
})
local guard_setting = managed({ DummyData = guard_dummy })
local defense_dummy = managed({ DP_Type = 2 })
local p2_defense = managed({ DP_Type = 2 })
local defense_system = managed({
    DummyData = defense_dummy,
    PlayerDatas = { [1] = p2_defense },
})
local training_data = managed({
    SelectMenu = select_menu,
    ParameterSetting = parameter_setting,
    GuardSetting = guard_setting,
    DefenseSystem = defense_system,
})

local parameter_apply_count = 0
local guard_apply_count = 0
local defense_apply_count = 0
local function tf_object(type_name, counter)
    return managed({
        get_type_definition = function()
            return { get_full_name = function() return type_name end }
        end,
        call = function(_, method)
            if method == "bApply" then counter() end
        end,
    })
end
local tf_parameter = tf_object("app.training.tf_ParameterSetting", function()
    parameter_apply_count = parameter_apply_count + 1
end)
local tf_guard = tf_object("app.training.tf_GuardSetting", function()
    guard_apply_count = guard_apply_count + 1
end)
local tf_defense = tf_object("app.training.tf_DefenseSystem", function()
    defense_apply_count = defense_apply_count + 1
end)
local entries = managed({
    values = {
        [0] = managed({ value = tf_parameter }),
        [1] = managed({ value = tf_guard }),
        [2] = managed({ value = tf_defense }),
    },
    call = function(self, method, index)
        if method == "get_Count" then return 3 end
        if method == "get_Item" then return self.values[index] end
    end,
})
local manager = managed({
    _tData = training_data,
    _IsReqRefresh = false,
    _tfFuncs = managed({ _entries = entries }),
})

local p1 = managed({
    vital_max = 10000,
    vital_new = 8800,
    vital_old = 8800,
    heal_new = 8800,
    heal_old = 8800,
    focus_new = 50000,
    focus_old = 50000,
    position_x = "native-refresh-owned",
    POS_SETx = function(self, value) self.position_x = value end,
})
local p2 = managed({
    position_x = "native-refresh-owned",
    vital_new = 7654,
    POS_SETx = function(self, value) self.position_x = value end,
})
_G.GameState = { p1 = p1, p2 = p2 }

local team = managed({ mSuperGauge = 20000 })
local team_data = { mcTeam = { [0] = team } }
local team_field = { get_data = function() return team_data end }

sdk = {
    get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return manager end
    end,
    find_type_definition = function(name)
        if name == "gBattle" then
            return { get_field = function(_, field) return field == "Team" and team_field or nil end }
        end
    end,
}

local Runtime = dofile("autorun/func/RandomKill/Runtime.lua")
assert(Runtime.read_p2_vital() == 7654, "runtime must expose P2 vitality for damage statistics")
local backup, capture_err = Runtime.capture()
assert(backup and not capture_err, "runtime must capture the original training state")

local scenario = {
    p1_x = -730,
    p2_x = -630,
    hp_pct = 20,
    drive_bars = 3,
    drive_points = 30000,
    super_bars = 3,
    super_points = 30000,
}
local applied, apply_err = Runtime.apply_scenario(scenario)
assert(applied and not apply_err, "runtime must accept a complete scenario")
assert(manager._IsReqRefresh == true, "scenario application must request one training refresh")
assert(p1_params.Vital_Point == 20 and p1_params.DG_Point == 30000
        and p1_params.SA_Point == 30000,
    "scenario resources must be written to native training parameters")
assert(guard_dummy.GuardType == 3
        and guard_dummy.IsGuardSwitching == true
        and guard_dummy.GuardOnlyType == 0,
    "one-click setup must force all guard with default guard switching")
assert(defense_dummy.DP_Type == 0 and p2_defense.DP_Type == 0,
    "one-click setup must force normal guard instead of parry")

manager._IsReqRefresh = false
local result = nil
for _ = 1, 10 do result = Runtime.update() end
assert(result == "ready", "runtime must apply exact values after refresh settles")
assert(p1.vital_new == 2000 and p1.focus_new == 30000 and team.mSuperGauge == 30000,
    "runtime must apply exact live P1 resources")
assert(p1.position_x == "native-refresh-owned" and p2.position_x == "native-refresh-owned",
    "runtime must not overwrite native refreshed positions with a second coordinate system")

local restored, restore_err = Runtime.restore(backup)
assert(restored and not restore_err, "runtime must schedule restoration")
manager._IsReqRefresh = false
for _ = 1, 10 do result = Runtime.update() end
assert(result == "restored", "runtime must finish restoration after refresh")
assert(select_menu.StartLocation == 2
        and p1_select.ManualPosX == -125
        and p2_select.ManualPosX == 175,
    "native position settings must be restored")
assert(p1.vital_new == 8800 and p1.focus_new == 50000 and team.mSuperGauge == 20000,
    "live P1 resources must be restored")
assert(guard_dummy.GuardType == 4
        and guard_dummy.GuardWeight == 7
        and guard_dummy.IsGuardSwitching == true,
    "dummy guard settings must be restored")
assert(defense_dummy.DP_Type == 2 and p2_defense.DP_Type == 2,
    "dummy defense settings must be restored")
assert(parameter_apply_count >= 2 and guard_apply_count >= 2 and defense_apply_count >= 2,
    "native parameter, guard, and defense panels must apply on setup and restore")

print("random kill runtime tests passed")
