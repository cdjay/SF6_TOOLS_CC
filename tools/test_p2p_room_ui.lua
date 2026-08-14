local function read_file(path)
    local file = assert(io.open(path, "rb"))
    local content = assert(file:read("*a"))
    file:close()
    return content
end

local source = read_file("autorun/P2P.lua")

assert(source:find('"app.CustomRoomManager"', 1, true),
    "P2P must detect the custom-room manager directly")
assert(source:find('"get_CustomRoomRoomId"', 1, true),
    "P2P must use the current custom-room identity")
assert(source:find('"get_ServiceType"', 1, true)
        and source:find('"set_ServiceType"', 1, true),
    "P2P must snapshot and change the network service type")
assert(source:find("baseline_service_type", 1, true),
    "P2P must restore the actual pre-enable service type")
assert(source:find('disable("已离开比赛间，功能已关闭")', 1, true),
    "leaving the room must force P2P off")
assert(source:find("not in_custom_room and state.baseline_service_type ~= nil", 1, true),
    "failed room-exit restoration must be retried until the baseline is restored")
assert(source:find('disable("比赛间已变化，功能已关闭")', 1, true),
    "changing rooms must invalidate the previous enablement")
assert(source:find("if not state.room_ui_visible then return end", 1, true),
    "the floating UI must only exist in the custom-room menu")
assert(source:find('"app.training.TrainingManager"', 1, true)
        and source:find('"_tData"', 1, true),
    "entering a training scene from the room must hide the UI")
assert(source:find('"get_FGBattle"', 1, true)
        and source:find('"IsJoinSession"', 1, true),
    "an active battle session must hide the room-only UI")
assert(source:find("local DESIGN_WIDTH = 2560", 1, true)
        and source:find("local DESIGN_HEIGHT = 1440", 1, true)
        and source:find("local scale_x = screen_width / DESIGN_WIDTH", 1, true)
        and source:find("local scale_y = screen_height / DESIGN_HEIGHT", 1, true),
    "the control geometry must scale from the reference game resolution")
assert(source:find('"网络加速关"', 1, true)
        and source:find('"网络加速开"', 1, true),
    "the room UI must expose the requested native-style on/off labels")
assert(source:find('"get_RoomMemberRttMap"', 1, true)
        and source:find('"get_Item1"', 1, true)
        and source:find('"ms"', 1, true)
        and source:find("RTT_POLL_FRAMES = 60", 1, true),
    "the room UI must display low-frequency exact room-member RTT")
assert(source:find('"PlayerList"', 1, true)
        and source:find('"FighterProfileInfo"', 1, true)
        and source:find('"ShortId"', 1, true)
        and source:find('"FighterId"', 1, true)
        and source:find("draw_room_rtt_hover_card", 1, true),
    "hovering the complete control must show each mapped player name and RTT")
assert(source:find("local bottom = math.floor(anchor_bottom - card_gap)", 1, true)
        and source:find("local top = math.max(0, bottom - card_height)", 1, true)
        and not source:find("imgui.set_tooltip", 1, true),
    "the RTT card bottom edge must stay anchored while the card grows upward")
assert(source:find("state.enabled and ACTIVE_GREEN or 0xFFFFFFFF", 1, true),
    "the P2P label must be white when off and green when active")
assert(not source:find("is_key_down", 1, true),
    "the standalone room UI must not register keyboard shortcuts")
assert(not source:find("platform_id", 1, true),
    "the standalone P2P control must not modify platform identity")
assert(source:find('imgui.load_font(', 1, true)
        and source:find('"msyh.ttc"', 1, true),
    "the room UI must use the packaged regular Microsoft YaHei font")
assert(source:find("WINDOW_FLAGS = 143", 1, true)
        and source:find("imgui.push_style_color(2, 0x00000000)", 1, true),
    "the room UI must be a transparent native-style action hint without a panel")
assert(source:find('ICON_PATH = "ui_icons/network_link_white.png"', 1, true)
        and source:find('ICON_ACTIVE_PATH = "ui_icons/network_link_green.png"', 1, true)
        and source:find("texture.draw_window", 1, true),
    "the action keycap must render distinct off and active network-link icons")
assert(source:find("Vector2f.new(window_width, window_height)", 1, true)
        and source:find("imgui.is_item_hovered()", 1, true),
    "the complete icon and label row must be interactive")
assert(source:find("local DESIGN_KEY_SIZE = 31", 1, true)
        and source:find("local DESIGN_ICON_CENTER_X = 705", 1, true)
        and source:find("local DESIGN_ICON_CENTER_FROM_BOTTOM = 54", 1, true)
        and source:find("icon_center_x - key_size * 0.5", 1, true),
    "the keycap must use the requested responsive reference position and size")
assert(source:find("KEYCAP_BORDER = 0xFF787878", 1, true)
        and source:find("local ACTIVE_GREEN = 0xFF84C768", 1, true)
        and source:find("draw_list:add_rect(", 1, true),
    "the keycap must use a gray off border and green active border")
assert(source:find("local DESIGN_FONT_SIZE = 33", 1, true)
        and source:find("DESIGN_FONT_SIZE * ui_scale", 1, true),
    "the P2P font load size must produce the requested roughly 22px visible height")
assert(source:find("(key_size - text_size.y) * 0.5", 1, true)
        and source:find("local DESIGN_TEXT_Y_OFFSET = -2", 1, true)
        and source:find("local top_inset = math.max(0, -centered_text_y)", 1, true)
        and source:find("hitbox_pos.y + text_y", 1, true),
    "the label offset must remain effective without moving the keycap")
assert(not source:find("imgui.text_colored(state.status", 1, true),
    "internal status details must not be drawn in the room UI")
assert(source:find("re.on_script_reset", 1, true),
    "script reload must restore the previous network mode")
assert(source:find("release_icon(state.icon_handle)", 1, true)
        and source:find("release_icon(state.active_icon_handle)", 1, true)
        and source:find("state.active_icon_handle = nil", 1, true),
    "script reload must release both inactive and active icon textures")

print("P2P room UI tests passed")
