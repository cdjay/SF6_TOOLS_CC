-- You can play around with something at conf/fastersf6_conf.lua.
local sdk = sdk
local re = re
local json = json

local setup_hook = require("func/setup_hook")
local current_scene_id = require("func/current_scene_id")
local show_custom_ticker = require("func/show_custom_ticker")
local was_key_down = require("func/was_key_down")

local this = {}
this.conf = require("conf/fastersf6_conf")
this._fighter_data = nil

this.END_PHASE = sdk.to_ptr(2)
this.SAVE_PATH = (this.conf.SAVE_PER_USER and sdk.call_native_func(sdk.get_native_singleton("via.Steam"), sdk.find_type_definition("via.Steam"), "get_AccountId") .. "." or "") .. "fastersf6.save.json"

this.save = json.load_file(this.SAVE_PATH) or {}
this.save.fighter_id = this.save.fighter_id or -1
this.save.theme_id = this.save.theme_id or -1
this.save.comment_id = this.save.comment_id or -1
this.save.comment_option = this.save.comment_option or -1
this.save.pose_id = this.save.pose_id or -1
this.save.title_id = this.save.title_id or -1
this.save.input_type = this.save.input_type or -1
this.save.dlc = this.save.dlc ~= nil and this.save.dlc or {}

this.message = require("lang/fastersf6_lang")

function this.interrupt_phase()
    return this.END_PHASE
end
function this.skip_phase()
    return sdk.PreHookResult.SKIP_ORIGINAL
end
function this.destroy(args)
    local obj = sdk.to_managed_object(args[2])
    obj.mIsEndState = true
    obj.mIsSkipEnable = true
    obj:SetState(2)
    obj:ReqSkipState()
    obj:set_Enabled(false)
end
function this.create_message_main_menu()
    return string.format(this.message.booting, this.message.main_menu)
end
function this.create_message_main_menu_with_guide()
    return this.destination == 1 and string.format(this.message.booting .. "\n" .. this.message.switch_prompt, this.message.main_menu) or this.create_message_main_menu()
end
function this.create_message_training_mode()
    return string.format(this.message.booting, this.message.training_mode)
end
function this.create_message_training_mode_with_guide()
    return this.destination == 2 and string.format(this.message.booting .. "\n" .. this.message.switch_prompt, this.message.training_mode) or this.create_message_training_mode()
end
function this.create_message_first_boot()
    return this.message.first_boot
end
function this.create_message_dlc_change()
    return this.message.dlc_detected
end
function this.show_destination_ticker()
    local messenger = {[1] = this.create_message_main_menu, [2] = this.create_message_training_mode}
    show_custom_ticker(messenger[this.destination], this.conf.TICKER_TIME)
end
function this.show_destination_ticker_with_guide()
    local messenger = {[1] = this.create_message_main_menu_with_guide, [2] = this.create_message_training_mode_with_guide}
    show_custom_ticker(messenger[this.destination], this.conf.TICKER_TIME)
end
function this.is_booting()
    local _obj__scn_id = sdk.find_type_definition("app.constant.scn.Index"):create_instance()
    local is_booting = {
        [_obj__scn_id:get_field("eNone")] = true,
        [_obj__scn_id:get_field("eBoot")] = true,
        [_obj__scn_id:get_field("eBootSetup")] = true,
        [_obj__scn_id:get_field("eTitle")] = true,
        [_obj__scn_id:get_field("eLogin")] = true,
        [-1] = true,
    }
    _obj__scn_id:release()
    return is_booting[current_scene_id()] or false
end
function this.update_fighter_settings()
    local _temp_man = sdk.get_managed_singleton("app.TemporarilyDataManager").Data
    this.save.fighter_id = _temp_man._MatchingFighterId
    this.save.theme_id = _temp_man.ThemeId
    this.save.comment_id = _temp_man.CommentId
    this.save.comment_option = _temp_man.CommentOption
    this.save.pose_id = _temp_man.AvatarPose
    local miscData = _temp_man.MatchingFighterSetting:ToArray()
    for _, v in pairs(miscData) do
        if v.FighterId == this.save.fighter_id then
            this.save.title_id = v.TitleId
            this.save.input_type = v.MatchingFighterInputStyle
        end
    end
    json.dump_file(this.SAVE_PATH, this.save)
end
function this.is_valid_fighter_id(id)
    return id >= 1
end
function this.apply_fighter_settings()
    if not this._fighter_data then
        local _temp_man = sdk.get_managed_singleton("app.TemporarilyDataManager")
        if not (_temp_man and _temp_man.Data) then
            return
        end
        this._fighter_data = _temp_man.Data
    end
    if this.is_valid_fighter_id(this.save.fighter_id) then
        this._fighter_data._MatchingFighterId = this.save.fighter_id
        this._fighter_data.ThemeId = this.save.theme_id
        this._fighter_data.CommentId = this.save.comment_id
        this._fighter_data.CommentOption = this.save.comment_option
        this._fighter_data.AvatarPose = this.save.pose_id
    end
end
function this.check_for_new_dlc()
    if this.destination > 0 then
        local _dlc_manager = sdk.get_managed_singleton("app.DlcManager")
        if not _dlc_manager then
            setup_hook("app.DlcManager", "doStart", nil, this.check_for_new_dlc)
        else
            local dlc_list = {}
            local steam_def = sdk.find_type_definition("via.Steam")
            local steam_obj = sdk.get_native_singleton("via.Steam")
            local dlc_name_enum_def = sdk.find_type_definition("app.AppDefine.DlcData")
            local _obj__dlc_name = dlc_name_enum_def:create_instance()
            for _,v in pairs(sdk.find_type_definition("app.AppDefine.DlcData"):get_fields()) do
                if v:get_type() == dlc_name_enum_def then
                    local _name = _obj__dlc_name:get_field(v:get_name())
                    local _id = math.tointeger(_dlc_manager:GetProductId(_name))
                    if _id then
                        local mInstalled = sdk.call_native_func(steam_obj, steam_def, "isInstalledDlc(System.UInt64)", _id)
                        dlc_list[tostring(_id)] = mInstalled
                    end
                end
            end

            local function tables_equal(a, b)
                for k, v in pairs(a) do
                    if b[k] ~= v and not (b[k] == nil and v == false) then
                        return false
                    end
                end
                for k, v in pairs(b) do
                    if a[k] ~= v and not (a[k] == nil and v == false) then 
                        return false
                    end
                end
                return true
            end
            if not tables_equal(this.save.dlc, dlc_list) then
                this.destination = -2
                show_custom_ticker(this.create_message_dlc_change)
            end
            this.save.dlc = dlc_list
            json.dump_file(this.SAVE_PATH, this.save)
            _obj__dlc_name:release()
        end
    end
end


--Initialize (choosing destination)
this.destination = this.is_booting() and this.conf.FIRST_DESTINATION or 0
this.destination = this.is_valid_fighter_id(this.save.fighter_id) and this.destination or -1
if this.destination > 0 then
    this.check_for_new_dlc()
end

--Only When the Game is Booting
if this.destination ~= 0 then

    --Logo Skips
    setup_hook("app.bBootFlow", "UpdatePhaseIllegalCopy", nil, this.interrupt_phase)
    setup_hook("app.bBootFlow", "UpdatePhasePhotosensitive", nil, this.interrupt_phase)
    setup_hook("app.bBootFlow", "UpdatePhaseLogo", nil, this.interrupt_phase)
    setup_hook("app.bBootFlow", "UpdatePhaseNoticeCore", nil, this.interrupt_phase)
    setup_hook("app.bBootFlow", "StartPhaseIllegalCopy", this.skip_phase)
    setup_hook("app.bBootFlow", "StartPhasePhotosensitive", this.skip_phase)
    setup_hook("app.bBootFlow", "StartPhaseLogo", this.skip_phase)

    --Removing Logo Ghost
    setup_hook("app.UIFlowNotice", "lateUpdate", this.destroy)
    setup_hook("app.UIFlowLogo", "lateUpdate", this.destroy)

    --Called Immediately after Entering the Main Menu
    --Call Training Mode if Demand
    setup_hook("app.menu.ModeSelectMain", "updateWait", function(args)
        if this.destination == -1 then
            this.update_fighter_settings()
        end
        if this.destination < 0 then
            this.destination = this.conf.FIRST_DESTINATION
        end
        if this.destination == 2 then
            sdk.to_managed_object(args[2]):call("updateTransitionToTrainingWithMatching(app.FlowPhase.dUpdatePhase, System.Single)", args[3], 0)
        end
        this.apply_fighter_settings()
        this.destination = 0
    end)
    setup_hook("app.UIFlowMatchingSetting.Param", "BeforeShowObject", function(args)
        this.apply_fighter_settings()
    end)

    --When First Boot or Else
    if this.destination == -1 then
        --Show First Boot Initial Notification
        show_custom_ticker(this.create_message_first_boot)
    elseif this.destination > 0 then
        --Manually Load Character Preferences in case when Login Asyncronously
        --Also Show General Initial Notification
        setup_hook("app.TemporarilyDataManager", "GetFighterSettingData", function(args)
            this.apply_fighter_settings()
        end,function(retval)
            local obj = sdk.to_managed_object(retval)
            if obj and obj.FighterId == this.save.fighter_id and #sdk.get_managed_singleton("app.TemporarilyDataManager").Data.MatchingFighterSetting:ToArray() == 0 then
                obj.TitleId = this.save.title_id
                obj.MatchingFighterInputStyle = this.save.input_type
                if this._fighter_data then
                    this._fighter_data.MatchingFighterSetting:Add(obj)
                end
            end
            return sdk.to_ptr(obj)
        end)
        setup_hook("app.TemporarilyDataManager.TemporarilyData", ".ctor", function(args)
            this._fighter_data = sdk.to_managed_object(args[2])
            this.apply_fighter_settings()
        end)
        if this.conf.SHOW_FIRST_TICKER then
            this.show_destination_ticker_with_guide()
        end
    end
end

--Title Skip
setup_hook("app.BootSetupFlow", "UpdatePhaseTransition", nil, function()
    sdk.find_type_definition("app.helper.flow"):get_method("requestTransitionLoginScene"):call(nil, 1)
    return this.END_PHASE
end)

--Make Login Process Done Asynchronous
setup_hook("app.bLoginFlow", "updateLogin", nil, function(retval)
    if this.destination > 0 and not this.conf.SAFE_MODE then
        return this.END_PHASE
    end
    return retval
end)

--Update Character Preferences as well when Matching Settings Get Updated
setup_hook("app.UIFlowMatchingSetting.Param", "OnEnd", nil, function(retval)
    this.update_fighter_settings()
    return retval
end)

--Handle Player Input to Switch the Destination
re.on_frame(function()
    if this.destination > 0 and was_key_down(this.conf.SWITCHER_KEY_CODE) then
        this.destination = this.destination == 1 and 2 or 1
        this.show_destination_ticker()
    end
end)