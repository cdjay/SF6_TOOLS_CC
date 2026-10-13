-- BcmCommandDecoder.lua
-- Classic command notation for a BCM trigger, decoded the same way as the
-- offline generator (tools/bcm_catalog_builder/bcm_catalog_core.js:
-- decodeButtons, normalizeMotion, formatChargeMotion, decodeCommand,
-- decodeProfile, selectClassicProfile). It lets a fighter without a generated
-- command table (a new fighter before its data ships, or a table that failed
-- validation) show "236+LP" instead of an internal action name.
--
-- The decoder only sees objects through an accessor, so the same code runs
-- on live REFramework objects and on exported dumps (offline tests):
--   access.field(object, name) -> number | boolean | object | nil
--   access.elements(array)     -> Lua array of element objects

local BcmCommandDecoder = {
    name = "ComboTrials.BcmCommandDecoder",
}

local DIR_MAP = {
    [0] = "5", [1] = "8", [2] = "2", [4] = "4", [5] = "7",
    [6] = "1", [8] = "6", [9] = "9", [10] = "3", [15] = "*",
}
local BUTTONS = {
    { 16, "LP" }, { 32, "MP" }, { 64, "HP" },
    { 128, "LK" }, { 256, "MK" }, { 512, "HK" },
}
local OPPOSITE = { ["6"] = "4", ["8"] = "2", ["4"] = "6", ["2"] = "8", ["9"] = "1", ["3"] = "7" }

local function integer(value)
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" then return 0 end
    return math.tointeger(value) or math.floor(value)
end

-- Low 32 bits, as the generator's JavaScript bit operators see them.
local function low32(value)
    return integer(value) & 0xFFFFFFFF
end

function BcmCommandDecoder.decode_buttons(mask, condition_mask)
    local count = ((low32(condition_mask) >> 6) & 3) + 1
    mask = low32(mask)
    if mask == 144 then return "Throw" end
    if mask == 288 then return "Parry" end
    if mask == 576 then return "DI" end
    if mask == 112 then return count == 3 and "PPP" or (count == 2 and "PP" or "P") end
    if mask == 896 then return count == 3 and "KKK" or (count == 2 and "KK" or "K") end
    local names = {}
    for _, button in ipairs(BUTTONS) do
        if mask & button[1] ~= 0 then names[#names + 1] = button[2] end
    end
    local same_family = (mask & (~112)) == 0 or (mask & (~896)) == 0
    return table.concat(names, same_family and #names > count and "/" or "+")
end

-- "5252" / "656": one direction tapped repeatedly with neutral between.
local function repeated_tap(text)
    local first = text:match("^5?[124689]")
    if first == nil then return false end
    local direction = first:sub(-1)
    local rest = text:sub(#first + 1)
    if rest == "" then return false end
    while rest ~= "" do
        if rest:sub(1, 1) == direction then
            rest = rest:sub(2)
        elseif rest:sub(1, 2) == "5" .. direction then
            rest = rest:sub(3)
        else
            return false
        end
    end
    return true
end

function BcmCommandDecoder.normalize_motion(raw)
    local normalized = tostring(raw or "")
    if repeated_tap(normalized) then normalized = normalized:gsub("5", "") end
    normalized = normalized:gsub("23626", "236236")
    normalized = normalized:gsub("21424", "214214")
    normalized = normalized:gsub("626", "623")
    normalized = normalized:gsub("424", "421")
    normalized = normalized:gsub("6314", "63214")
    normalized = normalized:gsub("4136", "41236")
    return normalized
end

function BcmCommandDecoder.format_charge_motion(notation, inputs)
    local first = inputs and inputs[1]
    if first and first.type == 1 and first.charge_release == true and #inputs >= 2 then
        -- The first release record can carry a permissive diagonal; the next
        -- direction is the real release and defines the held opposite.
        local hold = OPPOSITE[inputs[2].direction] or OPPOSITE[first.direction]
        if hold then
            local tail = {}
            for index = 2, #inputs do tail[#tail + 1] = inputs[index].direction end
            return "[" .. hold .. "]" .. table.concat(tail)
        end
    end
    if #notation == 2 and OPPOSITE[notation:sub(2, 2)] then
        return "[" .. OPPOSITE[notation:sub(2, 2)] .. "]" .. notation:sub(2, 2)
    end
    return notation
end

function BcmCommandDecoder.decode_command(access, command)
    if command == nil then return nil end
    local input_array = access.field(command, "inputs")
    local elements = input_array and access.elements(input_array) or {}
    local input_count = math.max(0, integer(access.field(command, "input_num")))
    local has_charge = integer(access.field(command, "charge_bit")) ~= 0
    local inputs = {}
    for index = 1, math.min(input_count, #elements) do
        local input = elements[index]
        local normal = input and access.field(input, "normal")
        local charge = input and access.field(input, "charge")
        local mask = normal and low32(access.field(normal, "ok_key_flags")) or 0
        local input_type = input and integer(access.field(input, "type")) or 0
        local charge_id = charge and integer(access.field(charge, "id")) or 0
        local charge_release = charge ~= nil and access.field(charge, "is_release") == true
        -- 360 / 720 are stored as exact release-style inputs whose low nibble
        -- alone would read as 8 / neutral.
        local full_circle = input_type == 2 and mask == 0x40001 and charge_id == 1 and charge_release
        local double_full_circle = input_type == 2 and mask == 0x70000 and charge_id == 0 and charge_release
        local direction = double_full_circle and "720"
            or (full_circle and "360" or (DIR_MAP[mask & 0xF] or "5"))
        if input_type == 1 or charge_release then has_charge = true end
        inputs[#inputs + 1] = {
            direction = direction,
            type = input_type,
            charge_release = charge_release,
        }
    end
    local directions = {}
    for index, input in ipairs(inputs) do directions[index] = input.direction end
    local motion = BcmCommandDecoder.normalize_motion(table.concat(directions))
    if has_charge then motion = BcmCommandDecoder.format_charge_motion(motion, inputs) end
    return { notation = motion, inputs = inputs }
end

-- The command a profile points at: the first BCM.COMMAND of its command_ptr
-- array (the generator resolves command_no to the same first variant).
local function profile_command(access, profile)
    local pointer = access.field(profile, "command_ptr")
    local elements = pointer and access.elements(pointer) or {}
    return BcmCommandDecoder.decode_command(access, elements[1])
end

function BcmCommandDecoder.profile_notation(access, profile, is_air)
    local function field(name)
        if profile == nil then return nil end
        return access.field(profile, name)
    end
    local command = profile ~= nil and profile_command(access, profile) or nil
    local ok_key_flags = field("ok_key_flags")
    local button = BcmCommandDecoder.decode_buttons(ok_key_flags, field("ok_key_cond_flags"))
    local direction = ""
    local dc_direction = low32(field("dc_exc_flags")) & 0xF
    local ok_direction = low32(ok_key_flags) & 0xF
    if dc_direction ~= 0 and dc_direction ~= 5 then
        direction = DIR_MAP[dc_direction] or ""
    elseif ok_direction ~= 0 and ok_direction ~= 5 and ok_direction ~= 15 then
        direction = DIR_MAP[ok_direction] or ""
    end
    local motion = command and command.notation ~= "" and command.notation or direction
    local body
    if motion ~= "" then
        body = motion .. (button ~= "" and ("+" .. button) or "")
    else
        body = button ~= "" and button or "Normal"
    end
    return (is_air and "j." or "") .. body
end

function BcmCommandDecoder.is_air(access, trigger)
    return integer(access.field(trigger, "cond_owner_state_flags")) == 4
        or (low32(access.field(trigger, "category_flags")) & 0x40000000) ~= 0
end

-- Classic notation of one BCM trigger, or nil when it has no classic input
-- (norm disabled and no enabled support profile).
function BcmCommandDecoder.classic_display(access, trigger)
    if trigger == nil then return nil end
    local profile_name = nil
    if access.field(trigger, "norm_NG") ~= true then
        profile_name = "norm"
    elseif access.field(trigger, "use_sprt") == true and access.field(trigger, "sprt_NG") ~= true then
        profile_name = "sprt"
    end
    if profile_name == nil then return nil end
    return BcmCommandDecoder.profile_notation(access, access.field(trigger, profile_name),
        BcmCommandDecoder.is_air(access, trigger))
end

-- Accessor for live REFramework objects.
BcmCommandDecoder.live_access = {
    field = function(object, name)
        if object == nil then return nil end
        local ok, value = pcall(object.get_field, object, name)
        if ok then return value end
        return nil
    end,
    elements = function(array)
        if array == nil then return {} end
        local ok, list = pcall(array.get_elements, array)
        if ok and type(list) == "table" then return list end
        return {}
    end,
}

return BcmCommandDecoder
