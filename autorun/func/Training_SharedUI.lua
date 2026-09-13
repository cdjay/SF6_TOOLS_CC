-- Training_SharedUI.lua
local UI = {}
local imgui = imgui

-- Global floating rect registry (cleared each frame, any script can publish)
function UI.clear_rects()
    _G.FloatingRects = {}
end

function UI.publish_rect(x, y, w, h)
    if not _G.FloatingRects then _G.FloatingRects = {} end
    table.insert(_G.FloatingRects, { x = x, y = y, w = w, h = h })
end

UI.COLORS = {
    White  = 0xFFDADADA, Green  = 0xFF00FF00, Red    = 0xFF0000FF,
    Grey   = 0x99FFFFFF, DarkGrey = 0xFF888888, Orange = 0xFF00A5FF, 
    Cyan   = 0xFFFFFF00, Yellow = 0xFF00FFFF, 
    Shadow = 0xFF000000, Blue   = 0xFFFFAA00 
}

local fonts = { main = nil, timer = nil, main_size = 0, timer_size = 0, timer_font_name = "" }
local res = { w = 0, h = 0, cooldown = 0 }
local last_hud_suffix = "Default"

-- ==========================================
-- HUD DICTIONARY (Font, Size, Y Pos, X Pos)
-- ==========================================
UI.HUD_CONFIG = {
    ["Default"] = { font = "msyhbd.ttc", size = 78, y = -0.45, x = 0.0 },  -- SF6		: OK
    ["_01"]     = { font = "msyhbd.ttc", size = 60, y = -0.42, x = 0.0 },  -- ??? 		:
    ["_02"]     = { font = "msyhbd.ttc", size = 50, y = -0.39, x = 0.0 },  -- SSF2 	: OK
    ["_03"]     = { font = "msyhbd.ttc", size = 45, y = -0.441, x = 0.0 }, -- SFZ3 	: OK
    ["_04"]     = { font = "msyhbd.ttc", size = 55, y = -0.425, x = 0.0 }, -- SF33s 	: OK
    ["_05"]     = { font = "msyhbd.ttc", size = 65, y = -0.445, x = 0.0 }, -- SF4 		: OK
    ["_06"]     = { font = "msyhbd.ttc", size = 65, y = -0.45, x = 0.0 },  -- SF5 		: OK
    ["_07"]     = { font = "msyhbd.ttc", size = 65, y = -0.451, x = 0.0 }  -- SIMSIM	: OK
}

local function _sui_read_display_xy(result)
    return result.x, result.y
end

function UI.get_screen_size()
    local w, h = 1920, 1080
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            local ok, rx, ry = pcall(_sui_read_display_xy, result)
            if ok then w, h = rx, ry end
        elseif type(result) == "number" then
            w, h = imgui.get_display_size()
        end
    end
    return w, h
end

function UI.get_letterbox_offset()
    local sw, sh = UI.get_screen_size()
    local game_h = sw * 9 / 16
    if game_h >= sh then return 0 end
    return (sh - game_h) / 2
end

function UI.update_fonts(cfg)
    local sw, sh = UI.get_screen_size()
    local scale = math.max(0.1, sh / 1080.0)

    -- Read the active HUD configuration
    local current_hud = _G.CurrentHudSuffix or "Default"
    local hud_cfg = UI.HUD_CONFIG[current_hud] or UI.HUD_CONFIG["Default"]

    local t_main = math.floor((cfg.hud_base_size or 20) * (cfg.hud_auto_scale and scale or 1.0))
    local t_timer = math.floor((hud_cfg.size) * (cfg.hud_auto_scale and scale or 1.0))

    if fonts.main_size ~= t_main then
        fonts.main = imgui.load_font("msyh.ttc", t_main)
        fonts.main_size = t_main
    end
    
    -- Reload if the size OR the font name changes!
    if fonts.timer_size ~= t_timer or fonts.timer_font_name ~= hud_cfg.font then
        fonts.timer = imgui.load_font(hud_cfg.font, t_timer)
        fonts.timer_size = t_timer
        fonts.timer_font_name = hud_cfg.font
    end
end

function UI.handle_resolution(cfg)
    local sw, sh = UI.get_screen_size()
    local current_hud = _G.CurrentHudSuffix or "Default"
    local force_update = false

    if res.w == 0 then 
        res.w = sw; res.h = sh; last_hud_suffix = current_hud
        UI.update_fonts(cfg); return 
    end
    
    if sw ~= res.w or sh ~= res.h then res.cooldown = 30; res.w = sw; res.h = sh end
    
    -- If the player changes HUD, trigger a font update
    if current_hud ~= last_hud_suffix then
        last_hud_suffix = current_hud
        force_update = true
    end

    if res.cooldown > 0 then 
        res.cooldown = res.cooldown - 1
        if res.cooldown == 0 then force_update = true end 
    end
    
    if force_update then UI.update_fonts(cfg) end
end

function UI.draw_text(text, x, y, color)
    local safe = string.gsub(text, "%%", "%%%%")
    local thick = 0.1
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, UI.COLORS.Grey)
    for dx = -thick, thick do
        for dy = -thick, thick do
            if (dx ~= 0 or dy ~= 0) and (math.abs(dx) + math.abs(dy) <= thick) then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe, UI.COLORS.Grey)
            end
        end
    end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, color)
end

function UI.draw_timer(text, x, y, color)
    local safe = string.gsub(text, "%%", "%%%%")
    local thick = 2
    for dx = -thick, thick, thick do
        for dy = -thick, thick, thick do
            if dx ~= 0 or dy ~= 0 then
                imgui.set_cursor_pos(Vector2f.new(x + dx, y + dy))
                imgui.text_colored(safe, 0xFF000000)
            end
        end
    end
    imgui.set_cursor_pos(Vector2f.new(x, y)); imgui.text_colored(safe, color)
end

function UI.format_time(s)
    if not s or s < 0 then s = 0 end 
    return string.format("%02d:%02d", math.floor(s/60), math.floor(s%60)) 
end

function UI.push_main() if fonts.main then imgui.push_font(fonts.main) end end
function UI.pop_main() if fonts.main then imgui.pop_font() end end
function UI.push_timer() if fonts.timer then imgui.push_font(fonts.timer) end end
function UI.pop_timer() if fonts.timer then imgui.pop_font() end end


function UI.draw_standard_hud(window_name, cfg, session, mode_label, show_timer, custom_stats_func)
    UI.handle_resolution(cfg)
    local sw, sh = UI.get_screen_size()
    
    imgui.push_style_var(4, 0.0); imgui.push_style_var(2, Vector2f.new(0, 0)); imgui.push_style_color(2, 0) 
    imgui.set_next_window_pos(Vector2f.new(0, 0)); imgui.set_next_window_size(Vector2f.new(sw, sh))
    
    local win_flags = 1 | 2 | 4 | 8 | 512 | 786432 | 128 -- ImGui Flags transparents

    if imgui.begin_window(window_name, true, win_flags) then
        UI.push_main()
        
        local lb_off = UI.get_letterbox_offset()
        local game_h = sh - lb_off * 2
        local center_x = sw / 2; local center_y = lb_off + game_h / 2
        local top_y = center_y + ((cfg.hud_n_global_y or -0.33) * game_h)
        local spread_score_px = (cfg.hud_n_spread_score or 0.09) * sw
        local spacing_y_px    = (cfg.hud_n_spacing_y or 0.03) * game_h

        local off_score_px = (cfg.hud_n_offset_score or 0.0) * sw
        local off_total_px = (cfg.hud_n_offset_total or 0.0) * sw
        local off_timer_px = (cfg.hud_n_offset_timer or 0.0) * sw
        local off_status_px = (cfg.hud_n_offset_status_y or 0.0) * game_h

        -- 1. TIMER
        if show_timer then
            local current_hud = _G.CurrentHudSuffix or "Default"
            local hud_cfg = UI.HUD_CONFIG[current_hud] or UI.HUD_CONFIG["Default"]

            local time_show = session.is_running and session.time_rem or ((cfg.timer_minutes or 0) * 60)
            local t_txt = UI.format_time(time_show)

            UI.pop_main(); UI.push_timer()

            local w_t = imgui.calc_text_size(t_txt).x
            local t_col = UI.COLORS.White
            if session.is_paused then t_col = UI.COLORS.Yellow
            elseif session.time_rem and session.time_rem < 10 and session.is_running then t_col = UI.COLORS.Red end
            if session.is_time_up then t_col = UI.COLORS.Red end

            UI.draw_timer(t_txt, center_x - (w_t / 2) + (hud_cfg.x * sw), center_y + (hud_cfg.y * game_h), t_col)
            
            UI.pop_timer(); UI.push_main()
        end

        -- 2. SCORE & LABELS
        local s_txt = "分数: " .. (session.score or 0)
        local tot_txt = "总计: " .. (session.total or 0)
        
        local w_s = imgui.calc_text_size(s_txt).x
        UI.draw_text(s_txt, center_x - spread_score_px - w_s + off_score_px, top_y, session.score_col or UI.COLORS.White)

        local w_m = imgui.calc_text_size(mode_label).x
        local mode_col = session.is_paused and UI.COLORS.Yellow or UI.COLORS.White
        UI.draw_text(mode_label, center_x - (w_m / 2) + off_timer_px, top_y, mode_col)

        UI.draw_text(tot_txt, center_x + spread_score_px + off_total_px, top_y, UI.COLORS.White)

        -- 3. SPECIFIC STATS INJECTION (Callback)
        local stat_y = top_y + spacing_y_px
        if custom_stats_func then custom_stats_func(center_x, stat_y, sw, game_h) end

        -- 4. STATUS
        local final_msg = session.feedback and session.feedback.text or ""
        local final_col = session.feedback and session.feedback.color or UI.COLORS.White
        
        if session.is_running and session.is_paused then
            final_msg = UI.pause_message()
            final_col = UI.COLORS.Yellow
        end
        
        local status_y = stat_y + spacing_y_px + off_status_px
        local w_msg = imgui.calc_text_size(final_msg).x
        UI.draw_text(final_msg, center_x - w_msg/2, status_y, final_col)

        UI.pop_main()
        imgui.end_window()
    end
    imgui.pop_style_var(2); imgui.pop_style_color(1)
end

function UI.pause_message()
    return "已暂停"
end

function UI.reset_message()
    return "训练已结束"
end

-- ==========================================
-- ACTION BUTTON COLORS (read from Training_ScriptManager via _G)
-- ==========================================
-- Fallback defaults (ABGR) if ScriptManager hasn't loaded yet
local SC_DEFAULTS = {
    c1 = { text = 0xFF4444FF, base = 0x784444FF, hover = 0xA04444FF, active = 0xC84444FF, border = 0xFFFFFFFF },
    c2 = { text = 0xFF44FF44, base = 0x7844FF44, hover = 0xA044FF44, active = 0xC844FF44, border = 0xFFFFFFFF },
    c3 = { text = 0xFFFF4444, base = 0x78FF4444, hover = 0xA0FF4444, active = 0xC8FF4444, border = 0xFFFFFFFF },
    c4 = { text = 0xFF00A5FF, base = 0x7800A5FF, hover = 0xA000A5FF, active = 0xC800A5FF, border = 0xFFFFFFFF },
}

-- Dynamic accessor: always reads live colors from _G (updated by ScriptManager)
UI.SC_COLORS = setmetatable({}, {
    __index = function(_, key)
        local g = _G.TrainingSCColors
        if g and g[key] then return g[key] end
        return SC_DEFAULTS[key]
    end
})

function UI.sc_button(label, colors, width)
    imgui.push_style_color(5,  colors.text)
    imgui.push_style_color(21, colors.base)
    imgui.push_style_color(22, colors.hover)
    imgui.push_style_color(23, colors.active)
    imgui.push_style_color(0,  colors.border)
    local clicked = imgui.button(label, width and Vector2f.new(width, 0) or nil)
    imgui.pop_style_color(5)
    return clicked
end

-- ==========================================
-- FLOATING SESSION WINDOW (ComboTrials style)
-- ==========================================
local float_ui_font = nil    -- Window font (same as ComboTrials custom_ui_font)
local float_btn_font = nil   -- Button font (same as ComboTrials sf6_btn_font)
local float_font_attempted = false
local float_last_sh = 0
local floating_width_pct = 1.0

UI.neon_colors = {
    bg = 0xFC800024,
    border = 0xFFEF51EF,
}

local FLOAT_SELECTOR_COLORS = {
    base = 0xFF363433,
    hover = 0xFF4C4845,
    active = 0xFF2E2B29,
}

local function _load_float_fonts(sh)
    if not float_font_attempted or sh ~= float_last_sh then
        float_font_attempted = true
        float_last_sh = sh
        local font_scale = sh / 1080.0
        pcall(function() float_ui_font = imgui.load_font("msyh.ttc", math.max(10, math.floor(20 * font_scale))) end)
        pcall(function() float_btn_font = imgui.load_font("msyhbd.ttc", math.max(10, math.floor(22 * font_scale))) end)
    end
end

function UI.get_floating_fonts(sh)
    sh = tonumber(sh) or select(2, UI.get_screen_size())
    _load_float_fonts(sh)
    return float_ui_font, float_btn_font
end

local function _push_bar_style(sw, sh)
    local colors = UI.neon_colors
    imgui.push_style_color(2,  colors.bg)    -- WindowBg
    imgui.push_style_color(5,  colors.border) -- Border
    imgui.push_style_color(7,  FLOAT_SELECTOR_COLORS.base)   -- FrameBg
    imgui.push_style_color(8,  FLOAT_SELECTOR_COLORS.hover)  -- FrameBgHovered
    imgui.push_style_color(9,  FLOAT_SELECTOR_COLORS.active) -- FrameBgActive
    imgui.push_style_var(4, 1.0)             -- WindowBorderSize
    imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))  -- WindowPadding
    if float_ui_font then imgui.push_font(float_ui_font) end
end

local function _push_top_bar_style(sw, sh)
    imgui.push_style_color(2,  0x00000000)   -- WindowBg transparent
    imgui.push_style_color(5,  0x00000000)   -- Border transparent
    imgui.push_style_color(7,  0x00000000)   -- FrameBg transparent
    imgui.push_style_color(8,  0x00000000)   -- FrameBgHovered transparent
    imgui.push_style_color(9,  0x00000000)   -- FrameBgActive transparent
    imgui.push_style_var(4, 0.0)             -- WindowBorderSize = 0
    imgui.push_style_var(2, Vector2f.new(sw * 0.01, sh * 0.02))  -- WindowPadding
    if float_ui_font then imgui.push_font(float_ui_font) end
end

local function _pop_bar_style()
    if float_ui_font then imgui.pop_font() end
    imgui.pop_style_var(2)   -- WindowPadding + WindowBorderSize
    imgui.pop_style_color(5)
end

function UI.set_floating_width_pct(value)
    floating_width_pct = math.max(0.3, math.min(1.0, tonumber(value) or 1.0))
    return floating_width_pct
end

function UI.get_floating_width_pct()
    return floating_width_pct
end

function UI.begin_floating_window(window_name, width_pct)
    local sw, sh = UI.get_screen_size()
    _load_float_fonts(sh)
    _push_bar_style(sw, sh)

    width_pct = math.max(0.3, math.min(1.0, tonumber(width_pct) or floating_width_pct))
    -- Same height as ComboTrials single-line bar, optionally compact and centered.
    local target_w = sw * width_pct
    local target_h = sh * 0.0444
    imgui.set_next_window_size(Vector2f.new(target_w, target_h), 1)      -- Always
    imgui.set_next_window_pos(Vector2f.new((sw - target_w) * 0.5, sh - target_h), 1)   -- Always
    -- 15 = NoTitleBar(1) + NoResize(2) + NoMove(4) + NoScrollbar(8)
    local visible = imgui.begin_window(window_name, true, 15)
    if visible then
        -- Match ComboTrials' single-line baseline instead of inheriting the
        -- larger window padding, which places controls too low in the bar.
        imgui.set_cursor_pos(Vector2f.new(sw * 0.01, sh * 0.01))
    end
    if not visible then _G.TrainingFloatingBar = nil end
    return visible, sw, sh
end

function UI.end_floating_window()
    imgui.end_window()
    _pop_bar_style()
end

-- Top floating window (vertical mirror of the bottom one)
function UI.begin_floating_window_top(window_name, width_pct, height_pct)
    local sw, sh = UI.get_screen_size()
    width_pct = width_pct or 1.0
    height_pct = height_pct or 0.0444

    _load_float_fonts(sh)
    _push_top_bar_style(sw, sh)

    local real_w, real_h = sw, sh
    if imgui.get_display_size then
        local result = imgui.get_display_size()
        if type(result) == "userdata" then
            local ok, rx, ry = pcall(_sui_read_display_xy, result)
            if ok then real_w, real_h = rx, ry end
        elseif type(result) == "number" then real_w, real_h = imgui.get_display_size() end
    end
    local target_w = real_w * width_pct
    local target_h = real_h * height_pct
    imgui.set_next_window_size(Vector2f.new(target_w, target_h))
    imgui.set_next_window_pos(Vector2f.new((real_w - target_w) / 2, 0))
    local visible = imgui.begin_window(window_name, true, 143)  -- NoBackground
    return visible, sw, sh
end

function UI.end_floating_window_top()
    imgui.end_window()
    _pop_bar_style()
end

function UI.draw_floating_bg_top()
    local sz = imgui.get_window_size()
    local pos = imgui.get_window_pos()
    UI.publish_rect(pos.x, pos.y, sz.x, sz.y)
    _G.TrainingBarsDrawn = true
end

function UI.draw_floating_bg()
    local sz = imgui.get_window_size()
    local pos = imgui.get_window_pos()
    UI.publish_rect(pos.x, pos.y, sz.x, sz.y)
    _G.TrainingBarsDrawn = true
end

-- SF6 neon button (identical to styled_sf6_button in floating mode with sf6_btn_font)
function UI.sf6_button(label, colors, width, height)
    if float_btn_font then imgui.push_font(float_btn_font) end
    imgui.push_style_color(5,  0x00000000)     -- Border transparent (no outline)
    imgui.push_style_color(21, colors.base)    -- Button
    imgui.push_style_color(22, colors.hover)   -- ButtonHovered
    imgui.push_style_color(23, colors.active)  -- ButtonActive
    imgui.push_style_color(0,  colors.border)  -- Text
    local clicked = imgui.button(label, Vector2f.new(width or 0, height or 0))
    imgui.pop_style_color(5)
    if float_btn_font then imgui.pop_font() end
    return clicked
end

local function _visible_button_label(label)
    local text = tostring(label or "")
    return text:match("^(.-)##") or text
end

UI.rect_button_colors = {
    normal =          { fill = 0xF0423832, border = 0xFF988C82 },
    hover =           { fill = 0xF0996746, border = 0xFFE7C3A9 },
    selected =        { fill = 0xF0AF6A2D, border = 0xFFF4CD9E },
    selected_hover =  { fill = 0xF0C47E3A, border = 0xFFFFFFFF },
    pressed =         { fill = 0xF07A4C2C, border = 0xFFD8B18D },
    selected_pressed ={ fill = 0xF0975B26, border = 0xFFEBCB91 },
    text = 0xFFFFFFFF,
    text_shadow = 0xA0000000,
    body_shadow = 0x80000000,
    highlight = 0x70FFFFFF,
}

-- SF6-style procedural rectangular button. Adjacent controls can share their
-- borders without texture seams; the close control contains only an X.
function UI.sf6_rect_button(label, is_selected, width, height, shape_kind)
    local _, sh = UI.get_screen_size()
    local scale = sh / 1440.0
    width = tonumber(width) or (187 * scale)
    height = tonumber(height)
    if height == nil or height <= 0 then height = 35 * scale end

    local cursor = imgui.get_cursor_screen_pos()
    local x, y = cursor.x, cursor.y
    local is_close = shape_kind == "close"

    if float_btn_font then imgui.push_font(float_btn_font) end
    imgui.push_style_color(5,  0x00000000)
    imgui.push_style_color(21, 0x00000000)
    imgui.push_style_color(22, 0x00000000)
    imgui.push_style_color(23, 0x00000000)
    imgui.push_style_color(0,  0x00000000)

    local clicked = imgui.button("##sf6_rect_" .. tostring(label), Vector2f.new(width, height))
    local hovered = imgui.is_item_hovered()
    local pressed = imgui.is_item_active()
    local press_offset = pressed and math.max(1, math.floor(1.5 * scale + 0.5)) or 0
    local palette
    if pressed then
        palette = is_selected
            and UI.rect_button_colors.selected_pressed
            or UI.rect_button_colors.pressed
    elseif hovered then
        palette = is_selected
            and UI.rect_button_colors.selected_hover
            or UI.rect_button_colors.hover
    else
        palette = is_selected
            and UI.rect_button_colors.selected
            or UI.rect_button_colors.normal
    end

    local draw_list = imgui.get_window_draw_list()
    if draw_list then
        local ox = press_offset
        local oy = press_offset
        local shadow_y = math.max(1, 2 * scale)
        local p1 = Vector2f.new(x + ox, y + oy)
        local p2 = Vector2f.new(x + width + ox, y + oy)
        local p3 = Vector2f.new(x + width + ox, y + height + oy)
        local p4 = Vector2f.new(x + ox, y + height + oy)
        local s1 = Vector2f.new(p1.x, p1.y + shadow_y)
        local s2 = Vector2f.new(p2.x, p2.y + shadow_y)
        local s3 = Vector2f.new(p3.x, p3.y + shadow_y)
        local s4 = Vector2f.new(p4.x, p4.y + shadow_y)
        local border_width = math.max(1, 1.35 * scale)

        draw_list:add_quad_filled(s1, s2, s3, s4, UI.rect_button_colors.body_shadow)
        draw_list:add_quad_filled(p1, p2, p3, p4, palette.fill)
        draw_list:add_line(p1, p2, UI.rect_button_colors.highlight, border_width)
        draw_list:add_line(p2, p3, palette.border, border_width)
        draw_list:add_line(p3, p4, palette.border, border_width)
        draw_list:add_line(p4, p1, palette.border, border_width)

        if is_close then
            local inset = math.max(4 * scale, height * 0.27)
            local x_width = math.max(1.5, 2.2 * scale)
            draw_list:add_line(
                Vector2f.new(x + inset + ox, y + inset + oy),
                Vector2f.new(x + width - inset + ox, y + height - inset + oy),
                UI.rect_button_colors.text,
                x_width
            )
            draw_list:add_line(
                Vector2f.new(x + width - inset + ox, y + inset + oy),
                Vector2f.new(x + inset + ox, y + height - inset + oy),
                UI.rect_button_colors.text,
                x_width
            )
        else
            local text = _visible_button_label(label)
            local text_size = imgui.calc_text_size(text)
            local text_x = x + (width - text_size.x) * 0.5 + ox
            local text_y = y + (height - text_size.y) * 0.5 + oy
            draw_list:add_text(
                Vector2f.new(text_x + scale, text_y + scale),
                UI.rect_button_colors.text_shadow,
                text
            )
            draw_list:add_text(
                Vector2f.new(text_x, text_y),
                UI.rect_button_colors.text,
                text
            )
        end
    end

    imgui.pop_style_color(5)
    if float_btn_font then imgui.pop_font() end
    return clicked
end

-- ==========================================
-- EXTERNAL QUICK SETTINGS
-- ==========================================
local quick_settings_state = {
    open_panel = nil,
    anchor_x = 0,
    anchor_y = 0,
    gear_rect = nil,
    gear_handle = nil,
    gear_load_failed = false,
    toggled_this_frame = false,
}

local QUICK_SETTINGS_GEAR_PATH = "ui_icons/settings_white.png"
local QUICK_SETTINGS_WINDOW_BG = 0xF51C1A19
local QUICK_SETTINGS_WINDOW_BORDER = 0xFF8F8178
local QUICK_SETTINGS_TITLE_COLOR = 0xFFFFFFFF
local QUICK_SETTINGS_SECTION_COLOR = 0xFF77C9FF
local QUICK_SETTINGS_WINDOW_FLAGS = (1 << 0) | (1 << 1) | (1 << 2)

local function _quick_settings_ensure_gear()
    local state = quick_settings_state
    if state.gear_handle or state.gear_load_failed then return state.gear_handle end
    if type(texture) ~= "table" or type(texture.load) ~= "function" then
        state.gear_load_failed = true
        return nil
    end
    local ok, handle = pcall(texture.load, QUICK_SETTINGS_GEAR_PATH)
    if ok and handle then
        state.gear_handle = handle
        return handle
    end
    state.gear_load_failed = true
    return nil
end

local function _quick_settings_point_in_rect(x, y, rect)
    return rect
        and x >= rect.x and x <= rect.x + rect.w
        and y >= rect.y and y <= rect.y + rect.h
end

local function _quick_settings_mouse_position()
    if type(imgui.get_mouse) ~= "function" then return nil, nil end
    local ok, mouse = pcall(imgui.get_mouse)
    if not ok or not mouse then return nil, nil end
    local xy_ok, x, y = pcall(function() return mouse.x, mouse.y end)
    if not xy_ok then return nil, nil end
    return x, y
end

function UI.quick_settings_is_open(panel_id)
    return quick_settings_state.open_panel == panel_id
end

function UI.close_quick_settings()
    quick_settings_state.open_panel = nil
end

function UI.draw_quick_settings_gear(menu_registry, panel_id, size)
    size = math.max(1, tonumber(size) or 28)
    local cursor = imgui.get_cursor_screen_pos()
    imgui.push_style_color(21, 0x00000000)
    imgui.push_style_color(22, 0x00000000)
    imgui.push_style_color(23, 0x00000000)
    imgui.push_style_color(0, 0x00000000)
    local clicked = imgui.button(
        "设置##quick_settings_" .. tostring(panel_id),
        Vector2f.new(size, size)
    )
    local hovered = imgui.is_item_hovered()
    local pressed = imgui.is_item_active()
    imgui.pop_style_color(4)

    local state = quick_settings_state
    state.anchor_x = cursor.x
    state.anchor_y = cursor.y + size
    state.gear_rect = { x = cursor.x, y = cursor.y, w = size, h = size }

    local draw_list = imgui.get_window_draw_list()
    if draw_list then
        local palette = UI.rect_button_colors
        local colors
        if pressed then
            colors = UI.quick_settings_is_open(panel_id) and palette.selected_pressed or palette.pressed
        elseif hovered then
            colors = UI.quick_settings_is_open(panel_id) and palette.selected_hover or palette.hover
        else
            colors = UI.quick_settings_is_open(panel_id) and palette.selected or palette.normal
        end
        draw_list:add_rect_filled(
            Vector2f.new(cursor.x, cursor.y),
            Vector2f.new(cursor.x + size, cursor.y + size),
            colors.fill,
            0.0,
            0
        )
        draw_list:add_rect(
            Vector2f.new(cursor.x, cursor.y),
            Vector2f.new(cursor.x + size, cursor.y + size),
            colors.border,
            0.0,
            0,
            1.0
        )
    end

    local icon = _quick_settings_ensure_gear()
    if icon and type(texture.draw_window) == "function" then
        local icon_size = math.max(8, math.floor(size * 0.58 + 0.5))
        local icon_x = cursor.x + math.floor((size - icon_size) * 0.5)
        local icon_y = cursor.y + math.floor((size - icon_size) * 0.5)
        pcall(texture.draw_window, icon, icon_x, icon_y, icon_size, icon_size)
    elseif draw_list then
        local fallback = "S"
        local text_size = imgui.calc_text_size(fallback)
        draw_list:add_text(
            Vector2f.new(
                cursor.x + (size - text_size.x) * 0.5,
                cursor.y + (size - text_size.y) * 0.5
            ),
            0xFFFFFFFF,
            fallback
        )
    end

    if hovered then imgui.set_tooltip("连段训练设置") end
    if clicked then
        if UI.quick_settings_is_open(panel_id) then
            state.open_panel = nil
        else
            state.open_panel = panel_id
        end
        state.toggled_this_frame = true
    end
    return clicked
end

local function _draw_quick_settings_header(title, scale, window_width)
    local close_size = math.max(24, math.floor(30 * scale + 0.5))
    local cursor_y = imgui.get_cursor_pos().y
    imgui.text_colored(title, QUICK_SETTINGS_TITLE_COLOR)
    imgui.set_cursor_pos(Vector2f.new(window_width - close_size - 14 * scale, cursor_y - 5 * scale))
    if UI.sf6_rect_button("X##close_quick_settings", false, close_size, close_size, "close") then
        UI.close_quick_settings()
    end
    imgui.set_cursor_pos(Vector2f.new(14 * scale, cursor_y + close_size + 2 * scale))
    imgui.separator()
end

function UI.draw_open_quick_settings(menu_registry, hotkeys)
    local state = quick_settings_state
    local panel_id = state.open_panel
    if not panel_id then
        state.toggled_this_frame = false
        return false
    end

    local spec = menu_registry.get_quick_spec(panel_id) or {}
    local sw, sh = UI.get_screen_size()
    local scale = math.max(0.65, sh / 1080.0)
    local padding = 14 * scale
    local panel_w = math.min(math.max(520 * scale, sw * 0.34), sw - 24 * scale)
    local panel_h = math.min(sh * 0.84, 900 * scale)
    local panel_x = math.max(12 * scale, math.min(state.anchor_x, sw - panel_w - 12 * scale))
    local panel_y = math.max(sh * 0.052, state.anchor_y + 4 * scale)
    if panel_y + panel_h > sh - 12 * scale then panel_h = sh - panel_y - 12 * scale end
    local panel_rect = { x = panel_x, y = panel_y, w = panel_w, h = panel_h }

    imgui.push_style_color(2, QUICK_SETTINGS_WINDOW_BG)
    imgui.push_style_color(5, QUICK_SETTINGS_WINDOW_BORDER)
    imgui.push_style_var(4, 1.0)
    imgui.push_style_var(2, Vector2f.new(padding, padding))
    imgui.set_next_window_pos(Vector2f.new(panel_x, panel_y), 1)
    imgui.set_next_window_size(Vector2f.new(panel_w, panel_h), 1)
    local panel_font = UI.get_floating_fonts(sh)
    if panel_font then imgui.push_font(panel_font) end

    local visible = imgui.begin_window(
        "SF6CCQuickSettings##" .. tostring(panel_id),
        true,
        QUICK_SETTINGS_WINDOW_FLAGS
    )
    if visible then
        UI.publish_rect(panel_x, panel_y, panel_w, panel_h)
        _draw_quick_settings_header(spec.title or "功能设置", scale, panel_w)
        if state.open_panel then
            imgui.spacing()
            imgui.text_colored("常用设置", QUICK_SETTINGS_SECTION_COLOR)
            imgui.spacing()
            menu_registry.draw_quick(panel_id)

            local hotkey_scope = spec.hotkey_scope
            if type(hotkey_scope) == "string" and hotkey_scope ~= "" then
                imgui.spacing()
                imgui.separator()
                imgui.spacing()
                imgui.text_colored("快捷键", QUICK_SETTINGS_SECTION_COLOR)
                imgui.text_colored("点击绑定后，按下键盘、手柄或游戏输入；ESC 取消。", 0xFF999999)
                imgui.spacing()
                hotkeys.draw_scope(hotkey_scope)
            end
        end
    end
    imgui.end_window()
    if panel_font then imgui.pop_font() end
    imgui.pop_style_var(2)
    imgui.pop_style_color(2)

    if state.open_panel and not state.toggled_this_frame and imgui.is_mouse_clicked(0) then
        local mouse_x, mouse_y = _quick_settings_mouse_position()
        if mouse_x and not _quick_settings_point_in_rect(mouse_x, mouse_y, panel_rect)
            and not _quick_settings_point_in_rect(mouse_x, mouse_y, state.gear_rect) then
            UI.close_quick_settings()
        end
    end
    state.toggled_this_frame = false
    return true
end


return UI
