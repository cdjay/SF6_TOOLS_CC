local M = {}
M.actions = { resume = "PAUSE", pause = "PAUSE", step = "FRAME_STEP", back = "FRAME_BACK", previous_round = "ROUND_CHANGE_PREV",
    next_round = "ROUND_CHANGE_NEXT", slower = "SPEED_DOWN", faster = "SPEED_UP", normal_speed = "RESET_SPEED",
    rewind = "ROLL_BACK", forward = "ROLL_FORWARD", medium_back = "REWIND", medium_forward = "FAST_FORWARD",
    takeover = "HIJACK" }
function M.allowed(key)
    return type(key) == "number" and key % 1 == 0 and ((key >= 0x30 and key <= 0x39) or (key >= 0x41 and key <= 0x5a)
        or (key >= 0x70 and key <= 0x87) or (key >= 0x21 and key <= 0x28) or key == 0x20)
end
function M.parse(text)
    text = text:upper():match("^%s*(.-)%s*$")
    if text:match("^[A-Z0-9]$") then return text:byte() end
    local f = tonumber(text:match("^F(%d+)$"))
    if f and f >= 1 and f <= 24 then return 0x6f + f end
    return ({ SPACE = 0x20, LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28 })[text]
end
local function property(object, name)
    local td = object:get_type_definition()
    if td:get_field(name) then return object:get_field(name) end
    if td:get_method("get_" .. name) then return object:call("get_" .. name) end
    error("Binding property unavailable: " .. name)
end
function M.new(sdk, overrides)
    local resolver = { overrides = overrides or {}, actions = M.actions }
    function resolver:resolve(ui, action)
        local manual = self.overrides[action == "pause" and "resume" or action]
        if type(manual) == "string" and manual ~= "" then
            local key = M.parse(manual)
            return key and { key = key, source = "manual" } or nil, "key_unavailable"
        end
        local ok, result = pcall(function()
            local shortcut = assert(M.actions[action])
            local enum = assert(sdk.find_type_definition("app.esports.ReplayUICtrl.EActiveShortcutType"))
            local value = assert(enum:get_field(shortcut)):get_data(nil)
            local data = assert(ui:get_field("_ShortCutActionDict")):call("get_Item", value)
            local input_id = assert(tonumber(property(assert(data), "InputId")))
            local input = assert(sdk.find_type_definition("app.InputManager"))
            local function call(signature, ...) return assert(input:get_method(signature)):call(nil, ...) end
            local setting = assert(call("GetSettingParam(app.InputAssign.Digital.Id)", input_id))
            local player = assert(tonumber(call("GetKeyboardMousePlayerIndex()")))
            assert(player >= 0, "Keyboard player unavailable")
            local device = assert(tonumber(call("GetPlayerDeviceIndex(System.Int32)", player)))
            assert(device >= 0, "Keyboard device unavailable")
            local config = assert(call("GetConfigParam(app.InputAssign.Digital.ConfigId, System.Int32)", property(setting, "ConfigId"), device))
            assert(property(config, "KeyboardFunctionKeyRequired") == false, "Modified binding unsupported")
            local first = assert(tonumber(property(config, "KeyboardKey")))
            local second = assert(tonumber(property(config, "KeyboardKey2")))
            -- A second nonempty key may represent a chord; do not guess its meaning.
            assert(second == 0 or first == 0 or second == first, "Ambiguous binding")
            local key = first ~= 0 and first or second
            assert(M.allowed(key), "Unsupported key")
            return { key = key, source = "game", input_id = input_id }
        end)
        if ok then return result end
        return nil, "key_unavailable", tostring(result)
    end
    return resolver
end
return M
