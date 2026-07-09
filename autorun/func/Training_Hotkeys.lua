-- =========================================================
-- Training_Hotkeys.lua - Shared multi-device hotkey registry.
-- Modules register actions; ScriptManager draws one global menu.
-- Defaults are intentionally disabled and unbound.
-- =========================================================

local json = json
local fs = fs
local imgui = imgui
local reframework = reframework
local sdk = sdk

local M = {}

local CONFIG_FILE = "Training_ScriptManager_data/TrainingHotkeys_Config.json"

local MODIFIER_VKS = { 0x10, 0x11, 0x12, 0x5B, 0x5C }
local MOD_SET = {}
for _, vk in ipairs(MODIFIER_VKS) do MOD_SET[vk] = true end

local VK_NAMES = {
    [0x08]="BACKSPACE",[0x09]="TAB",[0x0D]="ENTER",[0x10]="SHIFT",[0x11]="CTRL",[0x12]="ALT",
    [0x14]="CAPS",[0x1B]="ESC",[0x20]="SPACE",
    [0x21]="PGUP",[0x22]="PGDN",[0x23]="END",[0x24]="HOME",[0x25]="LEFT",[0x26]="UP",[0x27]="RIGHT",[0x28]="DOWN",
    [0x2D]="INSERT",[0x2E]="DELETE",
    [0x30]="0",[0x31]="1",[0x32]="2",[0x33]="3",[0x34]="4",[0x35]="5",[0x36]="6",[0x37]="7",[0x38]="8",[0x39]="9",
    [0x41]="A",[0x42]="B",[0x43]="C",[0x44]="D",[0x45]="E",[0x46]="F",[0x47]="G",[0x48]="H",[0x49]="I",
    [0x4A]="J",[0x4B]="K",[0x4C]="L",[0x4D]="M",[0x4E]="N",[0x4F]="O",[0x50]="P",[0x51]="Q",[0x52]="R",
    [0x53]="S",[0x54]="T",[0x55]="U",[0x56]="V",[0x57]="W",[0x58]="X",[0x59]="Y",[0x5A]="Z",
    [0x60]="NUM0",[0x61]="NUM1",[0x62]="NUM2",[0x63]="NUM3",[0x64]="NUM4",
    [0x65]="NUM5",[0x66]="NUM6",[0x67]="NUM7",[0x68]="NUM8",[0x69]="NUM9",
    [0x70]="F1",[0x71]="F2",[0x72]="F3",[0x73]="F4",[0x74]="F5",[0x75]="F6",
    [0x76]="F7",[0x77]="F8",[0x78]="F9",[0x79]="F10",[0x7A]="F11",[0x7B]="F12",
    [0xBA]=";",[0xBB]="=",[0xBC]=",",[0xBD]="-",[0xBE]=".",[0xBF]="/",[0xC0]="`",
}

local PAD_BUTTON_NAMES = {
    [1] = "PAD_UP",
    [2] = "PAD_DOWN",
    [4] = "PAD_LEFT",
    [8] = "PAD_RIGHT",
    [16] = "PAD_L3",
    [32] = "PAD_A/CROSS",
    [64] = "PAD_B/CIRCLE",
    [128] = "PAD_X/SQUARE",
    [256] = "PAD_Y/TRIANGLE",
    [512] = "PAD_LB/L1",
    [1024] = "PAD_RB/R1",
    [2048] = "PAD_LT/L2",
    [4096] = "PAD_RT/R2",
    [8192] = "PAD_BACK/SELECT",
    [16384] = "PAD_FUNC",
    [32768] = "PAD_START",
}

local GAME_INPUT_NAMES = {
    [1] = "GAME_8",
    [2] = "GAME_2",
    [4] = "GAME_4",
    [8] = "GAME_6",
    [16] = "GAME_LP",
    [32] = "GAME_MP",
    [64] = "GAME_HP",
    [128] = "GAME_LK",
    [256] = "GAME_MK",
    [512] = "GAME_HK",
    [144] = "GAME_THROW",
    [288] = "GAME_PARRY",
    [576] = "GAME_DI",
}

local registry = {}
local scope_order = {}
local config = { scopes = {} }
local loaded = false
local capture = nil
local capture_release_wait = false
local last_down = {}
local debug_state = {
    pad_mask = 0,
    game_mask = 0,
    last_source = "none",
}

local function safe_load_json(path)
    if _G.safe_load_json then return _G.safe_load_json(path) end
    local ok, data = pcall(json.load_file, path)
    return ok and data or nil
end

local function save_config()
    if fs and fs.create_dir then pcall(fs.create_dir, "Training_ScriptManager_data") end
    json.dump_file(CONFIG_FILE, config)
end

local function load_config()
    if loaded then return end
    loaded = true
    local data = safe_load_json(CONFIG_FILE)
    if type(data) == "table" then
        if type(data.scopes) == "table" then config.scopes = data.scopes end
    end
end

local function ensure_scope_config(scope_id, enabled_default)
    load_config()
    if type(config.scopes[scope_id]) ~= "table" then
        config.scopes[scope_id] = {
            enabled = enabled_default == true,
            bindings = {},
        }
        save_config()
    end
    local scope_cfg = config.scopes[scope_id]
    if type(scope_cfg.bindings) ~= "table" then scope_cfg.bindings = {} end
    if scope_cfg.enabled == nil then scope_cfg.enabled = enabled_default == true end
    return scope_cfg
end

local function read_key(vk)
    if not reframework or not reframework.is_key_down then return false end
    local ok, down = pcall(reframework.is_key_down, reframework, vk)
    return ok and down == true
end

local function read_pad_mask()
    if not sdk or not sdk.get_native_singleton or not sdk.find_type_definition or not sdk.call_native_func then return 0 end
    local ok, mask = pcall(function()
        local gamepad_manager = sdk.get_native_singleton("via.hid.GamePad")
        local gamepad_type = sdk.find_type_definition("via.hid.GamePad")
        if not gamepad_manager or not gamepad_type then return 0 end
        local devices = sdk.call_native_func(gamepad_manager, gamepad_type, "get_ConnectingDevices")
        if not devices then return 0 end
        local count = devices:call("get_Count") or 0
        local combined = 0
        for i = 0, count - 1 do
            local pad = devices:call("get_Item", i)
            if pad then
                local buttons = pad:call("get_Button") or 0
                if buttons > 0 then combined = combined | buttons end
            end
        end
        return combined
    end)
    return ok and (tonumber(mask) or 0) or 0
end

local function read_game_input_mask()
    local gs = _G.GameState
    local p1 = gs and gs.p1
    if not p1 then return 0 end
    local ok, mask = pcall(function()
        local td = p1:get_type_definition()
        if not td then return 0 end
        local f_input = td:get_field("pl_input_new")
        local f_sw = td:get_field("pl_sw_new")
        local input = (f_input and f_input:get_data(p1)) or 0
        local sw = (f_sw and f_sw:get_data(p1)) or 0
        return (input | sw) & 0xFFFF
    end)
    return ok and (tonumber(mask) or 0) or 0
end

function M.vk_name(vk)
    return VK_NAMES[vk] or string.format("0x%02X", tonumber(vk) or 0)
end

local function bitmask_name(mask, names, prefix)
    mask = tonumber(mask) or 0
    if mask <= 0 then return prefix .. "_NONE" end
    if names[mask] then return names[mask] end

    local parts = {}
    local remaining = mask
    local bit = 1
    while remaining > 0 and bit <= 0x40000000 do
        if (mask & bit) ~= 0 then
            parts[#parts + 1] = names[bit] or string.format("%s_0x%X", prefix, bit)
            remaining = remaining & ~bit
        end
        bit = bit << 1
    end
    return #parts > 0 and table.concat(parts, " + ") or string.format("%s_0x%X", prefix, mask)
end

function M.pad_button_name(mask)
    return bitmask_name(mask, PAD_BUTTON_NAMES, "PAD")
end

function M.game_input_name(mask)
    return bitmask_name(mask, GAME_INPUT_NAMES, "GAME")
end

local function sort_mods(mods)
    table.sort(mods, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
    return mods
end

local function binding_device(binding)
    if type(binding) ~= "table" then return nil end
    if binding.device then return binding.device end
    if binding.vk then return "keyboard" end
    if binding.button then return "gamepad" end
    if binding.input then return "game_input" end
    return nil
end

function M.combo_name(binding)
    if type(binding) ~= "table" then return "未绑定" end
    local device = binding_device(binding)
    if device == "gamepad" then
        return M.pad_button_name(binding.button)
    end
    if device == "game_input" then
        return M.game_input_name(binding.input)
    end
    if not binding.vk then return "未绑定" end
    local parts = {}
    for _, m in ipairs(binding.mods or {}) do parts[#parts + 1] = M.vk_name(m) end
    parts[#parts + 1] = M.vk_name(binding.vk)
    return table.concat(parts, " + ")
end

local function binding_key(binding)
    if type(binding) ~= "table" then return nil end
    local device = binding_device(binding)
    if device == "gamepad" then
        local button = tonumber(binding.button) or 0
        return button > 0 and ("gamepad|" .. tostring(button)) or nil
    end
    if device == "game_input" then
        local input = tonumber(binding.input) or 0
        return input > 0 and ("game_input|" .. tostring(input)) or nil
    end
    if not binding.vk then return nil end
    local mods = {}
    for _, m in ipairs(binding.mods or {}) do mods[#mods + 1] = tonumber(m) or m end
    sort_mods(mods)
    return "keyboard|" .. table.concat(mods, "+") .. "|" .. tostring(binding.vk)
end

local function binding_down(binding, pad_mask, game_mask)
    if type(binding) ~= "table" then return false end
    local device = binding_device(binding)
    if device == "gamepad" then
        local button = tonumber(binding.button) or 0
        if button <= 0 then return false end
        return ((pad_mask or 0) & button) == button
    end
    if device == "game_input" then
        local input = tonumber(binding.input) or 0
        if input <= 0 then return false end
        return ((game_mask or 0) & input) == input
    end
    if not binding.vk then return false end
    if not read_key(binding.vk) then return false end
    local required = {}
    for _, m in ipairs(binding.mods or {}) do
        required[m] = true
        if not read_key(m) then return false end
    end
    for _, m in ipairs(MODIFIER_VKS) do
        if not required[m] and read_key(m) then return false end
    end
    return true
end

local function scan_binding(pad_mask, game_mask)
    if read_key(0x1B) then return "cancel" end

    pad_mask = pad_mask or 0
    local pad_baseline = (capture and capture.pad_baseline) or 0
    if capture and pad_mask == 0 and pad_baseline ~= 0 then
        capture.pad_baseline = 0
        pad_baseline = 0
    end
    local new_pad_mask = pad_mask & ~pad_baseline
    if new_pad_mask > 0 then
        return { device = "gamepad", button = new_pad_mask }
    end

    game_mask = game_mask or 0
    local game_baseline = (capture and capture.game_baseline) or 0
    if capture and game_mask == 0 and game_baseline ~= 0 then
        capture.game_baseline = 0
        game_baseline = 0
    end
    local new_game_mask = game_mask & ~game_baseline
    if new_game_mask > 0 then
        return { device = "game_input", input = new_game_mask }
    end

    local mods = {}
    for _, mk in ipairs(MODIFIER_VKS) do
        if read_key(mk) then mods[#mods + 1] = mk end
    end
    for vk = 0x08, 0xC0 do
        if not MOD_SET[vk] and read_key(vk) then
            return { device = "keyboard", vk = vk, mods = sort_mods(mods) }
        end
    end
    return nil
end

local function any_binding_key_down(pad_mask, game_mask)
    if (pad_mask or 0) > 0 then return true end
    if (game_mask or 0) > 0 then return true end
    for vk = 0x08, 0xC0 do
        if read_key(vk) then return true end
    end
    return false
end

function M.register_scope(scope_id, spec)
    if type(scope_id) ~= "string" or scope_id == "" then return false end
    spec = spec or {}
    local scope = registry[scope_id]
    if not scope then
        scope = {
            id = scope_id,
            title = spec.title or scope_id,
            order = spec.order or (#scope_order + 1),
            actions = {},
            action_order = {},
            enabled_default = spec.enabled_default == true,
        }
        registry[scope_id] = scope
        scope_order[#scope_order + 1] = scope_id
    else
        scope.title = spec.title or scope.title
        scope.order = spec.order or scope.order
        scope.enabled_default = spec.enabled_default == true
    end

    ensure_scope_config(scope_id, scope.enabled_default)

    for _, action in ipairs(spec.actions or {}) do
        if type(action) == "table" and type(action.id) == "string" then
            if not scope.actions[action.id] then
                scope.action_order[#scope.action_order + 1] = action.id
            end
            scope.actions[action.id] = action
        end
    end
    table.sort(scope_order, function(a, b)
        return (registry[a].order or 0) < (registry[b].order or 0)
    end)
    return true
end

function M.is_scope_enabled(scope_id)
    local scope_cfg = config.scopes[scope_id]
    return type(scope_cfg) == "table" and scope_cfg.enabled == true
end

function M.get_binding(scope_id, action_id)
    local scope_cfg = config.scopes[scope_id]
    if type(scope_cfg) ~= "table" or type(scope_cfg.bindings) ~= "table" then return nil end
    return scope_cfg.bindings[action_id]
end

function M.get_label(scope_id, action_id)
    return M.combo_name(M.get_binding(scope_id, action_id))
end

local function find_conflicts(scope_id, action_id)
    local target = binding_key(M.get_binding(scope_id, action_id))
    if not target then return nil end
    local hits = {}
    for _, sid in ipairs(scope_order) do
        local scope = registry[sid]
        local scope_cfg = config.scopes[sid]
        if scope and scope_cfg and type(scope_cfg.bindings) == "table" then
            for _, aid in ipairs(scope.action_order) do
                if not (sid == scope_id and aid == action_id) and binding_key(scope_cfg.bindings[aid]) == target then
                    local action = scope.actions[aid]
                    hits[#hits + 1] = (scope.title or sid) .. " / " .. ((action and action.label) or aid)
                end
            end
        end
    end
    return #hits > 0 and table.concat(hits, ", ") or nil
end

local function draw_action_row(label, binding_label, draw_controls, force_stacked)
    local cursor = imgui.get_cursor_pos()
    local window_w = imgui.get_window_size().x
    local label_w = imgui.calc_text_size(label).x
    local binding_w = imgui.calc_text_size(binding_label).x
    local controls_w = imgui.calc_text_size("绑定").x + imgui.calc_text_size("清除").x + 44
    local right_aligned_x = window_w - controls_w - 12
    local controls_x = math.max(cursor.x + label_w + binding_w + 24, right_aligned_x)
    local binding_x = math.max(cursor.x + label_w + 12, controls_x - binding_w - 12)
    local inline_fits = controls_x + controls_w <= window_w - 12

    if not force_stacked and inline_fits and binding_x >= cursor.x + label_w + 12 then
        imgui.text(label)
        imgui.set_cursor_pos(Vector2f.new(binding_x, cursor.y))
        imgui.text_colored(binding_label, 0xFF00FFFF)
        imgui.set_cursor_pos(Vector2f.new(controls_x, cursor.y))
        draw_controls()
        return
    end

    -- Narrow REFramework menus cannot fit the label, binding and controls on one line.
    -- Keep every control in the visible content region by stacking the row instead.
    imgui.text(label)
    local binding_text = "当前绑定: " .. binding_label
    local compact_w = imgui.calc_text_size(binding_text).x + controls_w + 8
    if not force_stacked and cursor.x + compact_w <= window_w - 12 then
        imgui.text_colored(binding_text, 0xFF00FFFF)
        imgui.same_line(0, 8)
        draw_controls()
    else
        imgui.text_colored(binding_text, 0xFF00FFFF)
        draw_controls()
    end
end

function M.is_input_blocked()
    return capture ~= nil or capture_release_wait
end

function M.update(suspended)
    load_config()

    if suspended then return end
    local pad_mask = read_pad_mask()
    local game_mask = read_game_input_mask()
    debug_state.pad_mask = pad_mask
    debug_state.game_mask = game_mask

    if capture_release_wait then
        if not any_binding_key_down(pad_mask, game_mask) then capture_release_wait = false end
        return
    end

    if capture then
        local binding = scan_binding(pad_mask, game_mask)
        if binding == "cancel" then
            capture = nil
            capture_release_wait = true
            return
        elseif type(binding) == "table" then
            debug_state.last_source = binding.device or "unknown"
            local scope_cfg = ensure_scope_config(capture.scope_id, false)
            scope_cfg.bindings[capture.action_id] = binding
            save_config()
            capture = nil
            capture_release_wait = true
            return
        end
        return
    end

    for _, scope_id in ipairs(scope_order) do
        local scope = registry[scope_id]
        local scope_cfg = config.scopes[scope_id]
        if scope and scope_cfg and scope_cfg.enabled == true then
            for _, action_id in ipairs(scope.action_order) do
                local action = scope.actions[action_id]
                local binding = scope_cfg.bindings and scope_cfg.bindings[action_id]
                local key = scope_id .. "." .. action_id
                local is_down = binding_down(binding, pad_mask, game_mask)
                if is_down and not last_down[key] then
                    local allowed = true
                    if type(action.enabled) == "function" then
                        local ok, result = pcall(action.enabled)
                        allowed = ok and result ~= false
                    end
                    if allowed and type(action.run) == "function" then pcall(action.run) end
                end
                last_down[key] = is_down
            end
        end
    end
end

local function draw_scope(scope)
    local scope_cfg = ensure_scope_config(scope.id, scope.enabled_default)
    local changed, enabled = imgui.checkbox("启用 " .. scope.title .. " 快捷键##hk_enabled_" .. scope.id, scope_cfg.enabled == true)
    if changed then
        scope_cfg.enabled = enabled == true
        save_config()
    end

    for _, action_id in ipairs(scope.action_order) do
        local action = scope.actions[action_id]
        if action then
            imgui.separator()
            local cap = capture and capture.scope_id == scope.id and capture.action_id == action_id
            draw_action_row(action.label or action_id, M.combo_name(scope_cfg.bindings[action_id]), function()
                if cap then
                    imgui.text_colored("请按键或设备按钮；ESC 取消。", 0xFF00A5FF)
                    return
                end
                if imgui.button("绑定##hk_bind_" .. scope.id .. "_" .. action_id) then
                    capture = {
                        scope_id = scope.id,
                        action_id = action_id,
                        pad_baseline = read_pad_mask(),
                        game_baseline = read_game_input_mask(),
                    }
                end
                imgui.same_line()
                if imgui.button("清除##hk_clear_" .. scope.id .. "_" .. action_id) then
                    scope_cfg.bindings[action_id] = nil
                    save_config()
                end
            end, cap == true)

            local conflict = find_conflicts(scope.id, action_id)
            if conflict then
                imgui.text_colored("冲突: " .. conflict, 0xFF0000FF)
            end
        end
    end
end

function M.draw_menu()
    load_config()
    imgui.text_colored(string.format(
        "设备检测: HID=0x%X  游戏输入=0x%X  最近来源=%s",
        debug_state.pad_mask or 0,
        debug_state.game_mask or 0,
        debug_state.last_source or "none"
    ), 0xFF888888)
    if #scope_order == 0 then
        imgui.text_colored("暂无模块注册快捷键动作。", 0xFF888888)
        return
    end
    for _, scope_id in ipairs(scope_order) do
        local scope = registry[scope_id]
        if scope and imgui.tree_node(scope.title .. "##hotkeys_" .. scope_id) then
            draw_scope(scope)
            imgui.tree_pop()
        end
    end
end

return M
