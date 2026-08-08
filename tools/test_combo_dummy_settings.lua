package.path = package.path
    .. ";./autorun/?.lua"
    .. ";./autorun/?/init.lua"

local function object(fields)
    fields = fields or {}
    function fields:get_field(name)
        return self[name]
    end
    return fields
end

local counter_data = object({
    NC_TYPE = 0,
    PC_TYPE = 0,
    NC_Weight = 20,
    NH_Weight = 70,
    PC_Weight = 10,
    StyleNo = 1,
})
local guard_data = object({
    GuardType = 0,
    GuardWeight = 25,
    GuardCount = 2,
    IsGuardSwitching = false,
    GuardOnlyType = 0,
})
local action_data = object({
    DummyActionType = 0,
    JumpType = 0,
    JumpWeight_Front = 20,
    JumpWeight_Virtical = 60,
    JumpWeight_Back = 20,
    CpuLevel = 4,
})
local defense_dummy = object({
    QS_Type = 1,
    GD_Type = 2,
    DR_Type = 3,
    DP_Type = 4,
    QS_Weight = 11,
    GD_Weight = 12,
    DR_Guard_Weight = 13,
    DR_Getup_Weight = 14,
    DR_No_Weight = 15,
    DR_DelayFrame = 16,
    DR_DelayCount = 17,
})
local defense_player = object({
    DR_Type = 3,
    DP_Type = 4,
    DR_Guard_Weight = 13,
    DR_Getup_Weight = 14,
    DR_No_Weight = 15,
})

local training_data = object({
    CounterSetting = object({ DummyData = counter_data }),
    GuardSetting = object({ DummyData = guard_data }),
    DummyStatus = object({ DummyData = action_data }),
    DefenseSystem = object({
        DummyData = defense_dummy,
        PlayerDatas = { [1] = defense_player },
    }),
})
local training_manager = object({
    _tData = training_data,
    _tfFuncs = nil,
})
function training_manager:call(method)
    if method == "get_DefenseFunc" then return nil end
end

sdk = {
    get_managed_singleton = function(name)
        if name == "app.training.TrainingManager" then return training_manager end
        return nil
    end,
}

local DummySettings = require("func/ComboTrials/DummySettings")
local state = { sequence = {} }
DummySettings.init(state)

local counter = DummySettings.read_counter_settings()
assert(counter.counter_type == 0 and counter.NH_Weight == 70,
    "counter settings must preserve native fields")
DummySettings.save_counter_type()
DummySettings.set_counter_type(2, { NH_Weight = 33 })
assert(counter_data.NC_TYPE == 0 and counter_data.PC_TYPE == 1
        and counter_data.NH_Weight == 33,
    "punish-counter writes must preserve the existing runtime mapping")
DummySettings.restore_counter_type()
assert(counter_data.NC_TYPE == 0 and counter_data.PC_TYPE == 0
        and counter_data.NH_Weight == 70,
    "counter restore must replay the captured native settings")

local guard = DummySettings.read_guard_settings()
DummySettings.save_guard_type()
DummySettings.set_guard_type(3, 4, { GuardWeight = 80 })
assert(guard_data.GuardType == 3 and guard_data.GuardWeight == 80,
    "guard writes must retain their raw settings")
DummySettings.restore_guard_type()
assert(guard_data.GuardType == guard.guard_type
        and guard_data.GuardWeight == guard.GuardWeight,
    "guard restore must replay the captured native settings")

local action = DummySettings.read_action_settings()
DummySettings.save_action_type()
DummySettings.set_action_type(1, nil, false, { CpuLevel = 7 })
assert(action_data.DummyActionType == 1 and action_data.JumpType == 0
        and action_data.CpuLevel == 7,
    "dummy action writes must retain jump defaults and raw settings")
DummySettings.restore_action_type()
assert(action_data.DummyActionType == action.action_type
        and action_data.JumpType == action.jump_type
        and action_data.CpuLevel == action.CpuLevel,
    "dummy action restore must replay the captured native settings")

local env = {}
DummySettings.capture_training_defense_environment(env)
assert(env.dummy_drive_parry_type == 4
        and env.dummy_drive_reversal_type == 3
        and env.dummy_throw_escape_type == 2,
    "defense capture must retain the native training fields")
DummySettings.apply_trial_defense_cleanup()
assert(defense_dummy.DR_Type == 0 and defense_dummy.DP_Type == 0
        and defense_dummy.DR_No_Weight == 100,
    "defense cleanup must keep the existing disabled values")
assert(DummySettings.restore_trial_defense_settings() == true,
    "defense restore must consume the captured backup")
assert(defense_dummy.DR_Type == 3 and defense_dummy.DP_Type == 4
        and defense_dummy.DR_No_Weight == 15,
    "defense restore must replay the captured native fields")

print("combo dummy settings tests passed")
