local P2P_SERVICE_TYPE = 17
local ROOM_POLL_FRAMES = 30
local SCENE_POLL_FRAMES = 6
local RTT_POLL_FRAMES = 60
local MAX_ROOM_MEMBERS = 16
local WINDOW_FLAGS = 143
local ICON_PATH = "ui_icons/network_link_white.png"
local ICON_ACTIVE_PATH = "ui_icons/network_link_green.png"
local KEYCAP_BORDER = 0xFF787878
local ACTIVE_GREEN = 0xFF84C768
local HOVER_CARD_FILL = 0xEE171717
local HOVER_CARD_BORDER = 0xFF787878
local HOVER_CARD_TITLE = 0xFFD0D0D0
local DESIGN_WIDTH = 2560
local DESIGN_HEIGHT = 1440
local DESIGN_ICON_CENTER_X = 705
local DESIGN_ICON_CENTER_FROM_BOTTOM = 54
local DESIGN_KEY_SIZE = 31
local DESIGN_ICON_SIZE = 20
local DESIGN_FONT_SIZE = 33
local DESIGN_TOOLTIP_FONT_SIZE = 24
local DESIGN_TEXT_GAP = 10
local DESIGN_TEXT_Y_OFFSET = -2
local BUTTON_OFF = {
    base = 0xD92B2928,
    hover = 0xFF5C314C,
    active = 0xFF432238,
    text = 0xFFDADADA,
}
local BUTTON_ON = {
    base = 0xE039674F,
    hover = 0xFF4C8067,
    active = 0xFF28503D,
    text = 0xFFFFFFFF,
}

local state = {
    in_custom_room = false,
    room_id = nil,
    enabled = false,
    baseline_service_type = nil,
    poll_wait = 0,
    scene_poll_wait = 0,
    rtt_poll_wait = 0,
    room_ui_visible = false,
    room_member_rtts = {},
    room_members = {},
    displayed_rtt = nil,
    status = "",
    button_font = nil,
    tooltip_font = nil,
    font_height = 0,
    icon_handle = nil,
    active_icon_handle = nil,
    icon_failed = false,
    active_icon_failed = false,
}

local function safe_call(target, method, ...)
    if not target then return nil end
    local ok, result = pcall(target.call, target, method, ...)
    if not ok then return nil end
    return result
end

local function get_network_manager()
    if not (sdk and sdk.get_managed_singleton) then return nil end
    local ok, manager = pcall(
        sdk.get_managed_singleton,
        "app.network.NetworkManager"
    )
    if not ok then return nil end
    return manager
end

local function get_custom_room_manager()
    if not (sdk and sdk.get_managed_singleton) then return nil end
    local ok, manager = pcall(
        sdk.get_managed_singleton,
        "app.CustomRoomManager"
    )
    if not ok then return nil end
    return manager
end

local function normalize_room_id(value)
    if value == nil then return nil end
    local text = tostring(value):match("^%s*(.-)%s*$")
    if text == "" or text == "0" or text == "nil" then return nil end
    return text
end

local function read_room_id()
    local manager = get_custom_room_manager()
    return normalize_room_id(safe_call(manager, "get_CustomRoomRoomId"))
end

local function read_service_type()
    local value = safe_call(get_network_manager(), "get_ServiceType")
    return tonumber(value)
end

local function safe_get_field(target, name)
    if not target then return nil end
    local value = nil
    pcall(function() value = target:get_field(name) end)
    return value
end

local function read_tuple_rtt(tuple)
    if not tuple then return nil, nil end
    local rtt = safe_call(tuple, "get_Item1")
        or safe_get_field(tuple, "m_Item1")
    local interface_type = safe_call(tuple, "get_Item2")
        or safe_get_field(tuple, "m_Item2")
    rtt = tonumber(rtt)
    if rtt == nil or rtt < 0 or rtt > 10000 then return nil, nil end
    return math.floor(rtt + 0.5), tonumber(interface_type)
end

local function normalize_player_name(value)
    if value == nil then return nil end
    local name = tostring(value):gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if name == "" then return nil end
    return name
end

local function read_room_members(manager, rtts)
    local members = {}
    local room_info = safe_call(manager, "get_RoomInfo")
        or safe_get_field(manager, "<RoomInfo>k__BackingField")
    local player_list = safe_get_field(room_info, "PlayerList")
    local count = math.max(0, math.floor(tonumber(
        safe_call(player_list, "get_Count")
    ) or 0))
    local limit = math.min(count, MAX_ROOM_MEMBERS)

    for index = 0, limit - 1 do
        local member = safe_call(player_list, "get_Item", index)
        local profile = safe_get_field(member, "FighterProfileInfo")
        local member_id = tonumber(safe_get_field(profile, "ShortId"))
        local name = normalize_player_name(safe_get_field(profile, "FighterId"))
        if member_id ~= nil and name ~= nil then
            local network = rtts[member_id]
            members[#members + 1] = {
                member_id = member_id,
                name = name,
                rtt = network and network.rtt or nil,
            }
        end
    end
    return members
end

local function refresh_room_rtts()
    if not state.in_custom_room then
        state.room_member_rtts = {}
        state.room_members = {}
        state.displayed_rtt = nil
        return
    end

    local manager = get_custom_room_manager()
    local map = safe_call(manager, "get_RoomMemberRttMap")
    local rtts = {}
    local displayed_rtt = nil
    local count = map and math.max(0, math.floor(tonumber(
        safe_call(map, "get_Count")
    ) or 0)) or 0
    local keys = map and safe_call(map, "get_Keys") or nil
    local values = map and safe_call(map, "get_Values") or nil
    local limit = math.min(count, MAX_ROOM_MEMBERS)

    for index = 0, limit - 1 do
        local member_id = tonumber(safe_call(keys, "get_Item", index))
        local tuple = safe_call(values, "get_Item", index)
        if member_id ~= nil then
            tuple = safe_call(map, "get_Item", member_id) or tuple
        end
        local rtt, interface_type = read_tuple_rtt(tuple)
        if member_id ~= nil and rtt ~= nil then
            rtts[member_id] = {
                rtt = rtt,
                interface_type = interface_type,
            }
            if displayed_rtt == nil or rtt > displayed_rtt then
                displayed_rtt = rtt
            end
        end
    end

    state.room_member_rtts = rtts
    state.room_members = read_room_members(manager, rtts)
    state.displayed_rtt = displayed_rtt
end

local function build_room_rtt_rows()
    if #state.room_members == 0 then
        return { { name = "暂无玩家延迟数据", rtt = "" } }
    end
    local rows = {}
    for _, member in ipairs(state.room_members) do
        local rtt = member.rtt and (tostring(member.rtt) .. "ms") or "-- ms"
        rows[#rows + 1] = { name = member.name, rtt = rtt }
    end
    return rows
end

local function is_training_scene_active()
    if not (sdk and sdk.get_managed_singleton) then return false end
    local ok, manager = pcall(
        sdk.get_managed_singleton,
        "app.training.TrainingManager"
    )
    if not ok or not manager then return false end
    local read_ok, training_data = pcall(manager.get_field, manager, "_tData")
    return read_ok and training_data ~= nil
end

local function is_battle_session_active()
    local network = get_network_manager()
    local session = safe_call(network, "get_Session")
    if not session then return false end

    local fg_battle = safe_call(session, "get_FGBattle")
    if fg_battle and safe_call(fg_battle, "IsJoinSession") == true then
        return true
    end

    local wt_battle = safe_call(session, "get_WTBattle")
    return wt_battle ~= nil
        and safe_call(wt_battle, "IsJoinSession") == true
end

local function write_service_type(value)
    value = tonumber(value)
    if value == nil then return false end
    local manager = get_network_manager()
    if not manager then return false end
    local ok = pcall(manager.call, manager, "set_ServiceType", value)
    return ok
end

local function disable(reason)
    local restore = state.baseline_service_type
    state.enabled = false
    if restore ~= nil then
        if not write_service_type(restore) then
            state.status = "正在恢复网络模式"
            return false
        end
    end

    state.baseline_service_type = nil
    state.status = reason or "已关闭"
    return true
end

local function enable()
    if not state.in_custom_room then
        state.status = "仅比赛间可用"
        return false
    end
    if state.baseline_service_type ~= nil then
        state.status = "正在恢复网络模式"
        return false
    end

    local current = read_service_type()
    if current == nil then
        state.status = "无法读取网络模式"
        return false
    end

    state.baseline_service_type = current
    if current ~= P2P_SERVICE_TYPE
        and not write_service_type(P2P_SERVICE_TYPE) then
        state.baseline_service_type = nil
        state.status = "开启失败"
        return false
    end

    state.enabled = true
    state.status = "已开启"
    return true
end

local function refresh_room_state()
    local room_id = read_room_id()
    local in_custom_room = room_id ~= nil

    if state.in_custom_room and not in_custom_room then
        disable("已离开比赛间，功能已关闭")
    elseif state.in_custom_room and in_custom_room
        and state.room_id ~= room_id then
        disable("比赛间已变化，功能已关闭")
    end

    if not in_custom_room and state.baseline_service_type ~= nil then
        disable("已离开比赛间，功能已关闭")
    end

    state.in_custom_room = in_custom_room
    state.room_id = room_id
    if not in_custom_room then
        state.room_member_rtts = {}
        state.room_members = {}
        state.displayed_rtt = nil
    end
    if in_custom_room and state.status == "" then
        state.status = "已关闭"
    end
end

local function refresh_scene_state()
    state.room_ui_visible = state.in_custom_room
        and not is_training_scene_active()
        and not is_battle_session_active()
end

local function get_screen_size()
    local width, height = 1920, 1080
    if not (imgui and imgui.get_display_size) then return width, height end

    local ok, first, second = pcall(imgui.get_display_size)
    if not ok then return width, height end
    if type(first) == "userdata" then
        local read_ok, x, y = pcall(function() return first.x, first.y end)
        if read_ok then return tonumber(x) or width, tonumber(y) or height end
    elseif type(first) == "number" then
        return first, tonumber(second) or height
    end
    return width, height
end

local function ensure_fonts(ui_scale)
    local font_size = math.max(1, math.floor(DESIGN_FONT_SIZE * ui_scale + 0.5))
    if state.font_height == font_size then return end
    state.font_height = font_size

    state.button_font = nil
    state.tooltip_font = nil
    if not (imgui and imgui.load_font) then return end
    pcall(function()
        state.button_font = imgui.load_font(
            "msyh.ttc",
            font_size
        )
        state.tooltip_font = imgui.load_font(
            "msyh.ttc",
            math.max(1, math.floor(DESIGN_TOOLTIP_FONT_SIZE * ui_scale + 0.5))
        )
    end)
end

local function ensure_icon(active)
    local handle_key = active and "active_icon_handle" or "icon_handle"
    local failed_key = active and "active_icon_failed" or "icon_failed"
    local path = active and ICON_ACTIVE_PATH or ICON_PATH
    if state[handle_key] or state[failed_key] then return state[handle_key] end
    if type(texture) ~= "table" or type(texture.load) ~= "function" then
        state[failed_key] = true
        return nil
    end

    local ok, handle = pcall(texture.load, path)
    if ok and handle then
        state[handle_key] = handle
        return handle
    end
    state[failed_key] = true
    return nil
end

local function release_icon(handle)
    if handle and type(texture) == "table"
        and type(texture.release) == "function" then
        pcall(texture.release, handle)
    end
end

local function draw_room_rtt_hover_card(anchor_x, anchor_bottom, ui_scale)
    if type(imgui.get_background_draw_list) ~= "function" then return end
    local ok, draw_list = pcall(imgui.get_background_draw_list)
    if not ok or not draw_list then return end

    local rows = build_room_rtt_rows()
    local padding = math.max(6, math.floor(12 * ui_scale + 0.5))
    local column_gap = math.max(12, math.floor(24 * ui_scale + 0.5))
    local row_gap = math.max(2, math.floor(4 * ui_scale + 0.5))
    local title_gap = math.max(4, math.floor(8 * ui_scale + 0.5))
    local card_gap = math.max(4, math.floor(8 * ui_scale + 0.5))

    if state.tooltip_font then imgui.push_font(state.tooltip_font) end
    local title = "房间玩家延迟"
    local title_size = imgui.calc_text_size(title)
    local max_name_width = 0
    local max_rtt_width = 0
    local line_height = title_size.y
    for _, row in ipairs(rows) do
        local name_size = imgui.calc_text_size(row.name)
        local rtt_size = imgui.calc_text_size(row.rtt)
        max_name_width = math.max(max_name_width, name_size.x)
        max_rtt_width = math.max(max_rtt_width, rtt_size.x)
        line_height = math.max(line_height, name_size.y, rtt_size.y)
    end

    local row_width = max_name_width
    if max_rtt_width > 0 then row_width = row_width + column_gap + max_rtt_width end
    local card_width = math.ceil(math.max(title_size.x, row_width) + padding * 2)
    local rows_height = #rows * line_height + math.max(0, #rows - 1) * row_gap
    local card_height = math.ceil(
        padding * 2 + title_size.y + title_gap + rows_height
    )
    local left = math.floor(anchor_x)
    local bottom = math.floor(anchor_bottom - card_gap)
    local top = math.max(0, bottom - card_height)
    local right = left + card_width

    draw_list:add_rect_filled(
        Vector2f.new(left, top),
        Vector2f.new(right, bottom),
        HOVER_CARD_FILL,
        0.0,
        0
    )
    draw_list:add_rect(
        Vector2f.new(left, top),
        Vector2f.new(right, bottom),
        HOVER_CARD_BORDER,
        0.0,
        0,
        1.0
    )

    local text_x = left + padding
    local text_y = top + padding
    draw_list:add_text(
        Vector2f.new(text_x, text_y),
        HOVER_CARD_TITLE,
        title
    )
    text_y = text_y + title_size.y + title_gap
    for _, row in ipairs(rows) do
        draw_list:add_text(
            Vector2f.new(text_x, text_y),
            0xFFFFFFFF,
            row.name
        )
        if row.rtt ~= "" then
            draw_list:add_text(
                Vector2f.new(right - padding - max_rtt_width, text_y),
                ACTIVE_GREEN,
                row.rtt
            )
        end
        text_y = text_y + line_height + row_gap
    end
    if state.tooltip_font then imgui.pop_font() end
end

local function draw_room_ui()
    if not state.room_ui_visible then return end

    local screen_width, screen_height = get_screen_size()
    local scale_x = screen_width / DESIGN_WIDTH
    local scale_y = screen_height / DESIGN_HEIGHT
    local ui_scale = math.max(0.5, math.min(scale_x, scale_y))
    ensure_fonts(ui_scale)

    local key_size = math.max(1, math.floor(DESIGN_KEY_SIZE * ui_scale + 0.5))
    local icon_size = math.max(1, math.floor(DESIGN_ICON_SIZE * ui_scale + 0.5))
    local gap = math.max(1, math.floor(DESIGN_TEXT_GAP * ui_scale + 0.5))
    local icon_center_x = DESIGN_ICON_CENTER_X * scale_x
    local center_from_bottom = DESIGN_ICON_CENTER_FROM_BOTTOM * scale_y
    local label = state.enabled and "网络加速开" or "网络加速关"
    if state.displayed_rtt ~= nil then
        label = label .. "  " .. tostring(state.displayed_rtt) .. "ms"
    end

    if state.button_font then imgui.push_font(state.button_font) end
    local text_size = imgui.calc_text_size(label)
    local centered_text_y = math.floor(
        (key_size - text_size.y) * 0.5
            + DESIGN_TEXT_Y_OFFSET * ui_scale
    )
    local top_inset = math.max(0, -centered_text_y)
    local text_y = top_inset + centered_text_y
    local window_width = math.floor(key_size + gap + text_size.x + 4 * ui_scale)
    local window_height = math.max(
        top_inset + key_size,
        math.floor(text_y + text_size.y + 4 * ui_scale)
    )
    local x = math.max(0, math.floor(icon_center_x - key_size * 0.5))
    local key_y = math.max(0, screen_height - center_from_bottom - key_size * 0.5)
    local y = math.max(0, math.floor(key_y - top_inset))

    imgui.push_style_color(2, 0x00000000)
    imgui.push_style_color(5, 0x00000000)
    imgui.push_style_color(7, 0x00000000)
    imgui.push_style_color(8, 0x00000000)
    imgui.push_style_var(4, 0.0)
    imgui.push_style_var(2, Vector2f.new(0, 0))
    imgui.set_next_window_pos(Vector2f.new(x, y), 1)
    imgui.set_next_window_size(Vector2f.new(window_width, window_height), 1)

    local hovered = false
    local hover_anchor_x = x
    local hover_anchor_bottom = key_y
    local visible = imgui.begin_window(
        "SF6 P2P##SF6P2PRoomControl",
        true,
        WINDOW_FLAGS
    )
    if visible then
        local colors = state.enabled and BUTTON_ON or BUTTON_OFF
        imgui.set_cursor_pos(Vector2f.new(0, 0))
        local hitbox_pos = imgui.get_cursor_screen_pos()
        imgui.push_style_color(21, 0x00000000)
        imgui.push_style_color(22, 0x00000000)
        imgui.push_style_color(23, 0x00000000)
        imgui.push_style_color(0, 0x00000000)
        local clicked = imgui.button(
            "##sf6p2p_toggle",
            Vector2f.new(window_width, window_height)
        )
        hovered = imgui.is_item_hovered()
        local pressed = imgui.is_item_active()
        imgui.pop_style_color(4)

        local screen_pos = Vector2f.new(hitbox_pos.x, hitbox_pos.y + top_inset)
        local draw_list = imgui.get_window_draw_list()
        if draw_list then
            local fill = pressed and colors.active or (hovered and colors.hover or colors.base)
            local border = state.enabled and ACTIVE_GREEN or KEYCAP_BORDER
            draw_list:add_rect_filled(
                screen_pos,
                Vector2f.new(screen_pos.x + key_size, screen_pos.y + key_size),
                fill,
                0.0,
                0
            )
            draw_list:add_rect(
                screen_pos,
                Vector2f.new(screen_pos.x + key_size, screen_pos.y + key_size),
                border,
                0.0,
                0,
                1.5
            )
        end

        local icon = ensure_icon(state.enabled)
        if icon and type(texture.draw_window) == "function" then
            local icon_x = screen_pos.x + math.floor((key_size - icon_size) * 0.5)
            local icon_y = screen_pos.y + math.floor((key_size - icon_size) * 0.5)
            pcall(texture.draw_window, icon, icon_x, icon_y, icon_size, icon_size)
        end

        if clicked then
            if state.enabled then
                disable("已关闭")
            else
                enable()
            end
        end

        local text_x = key_size + gap
        if draw_list then
            local text_color = state.enabled and ACTIVE_GREEN or 0xFFFFFFFF
            draw_list:add_text(
                Vector2f.new(hitbox_pos.x + text_x, hitbox_pos.y + text_y),
                text_color,
                label
            )
        end
    end
    imgui.end_window()
    imgui.pop_style_var(2)
    imgui.pop_style_color(4)
    if state.button_font then imgui.pop_font() end
    if hovered then
        draw_room_rtt_hover_card(hover_anchor_x, hover_anchor_bottom, ui_scale)
    end
end

refresh_room_state()
refresh_scene_state()

re.on_frame(function()
    state.poll_wait = state.poll_wait - 1
    if state.poll_wait <= 0 then
        state.poll_wait = ROOM_POLL_FRAMES
        refresh_room_state()
    end
    state.scene_poll_wait = state.scene_poll_wait - 1
    if state.scene_poll_wait <= 0 then
        state.scene_poll_wait = SCENE_POLL_FRAMES
        refresh_scene_state()
    end
    state.rtt_poll_wait = state.rtt_poll_wait - 1
    if state.rtt_poll_wait <= 0 then
        state.rtt_poll_wait = RTT_POLL_FRAMES
        refresh_room_rtts()
    end
    draw_room_ui()
end)

if re.on_script_reset then
    re.on_script_reset(function()
        disable("脚本已重载")
        release_icon(state.icon_handle)
        release_icon(state.active_icon_handle)
        state.icon_handle = nil
        state.active_icon_handle = nil
    end)
end
