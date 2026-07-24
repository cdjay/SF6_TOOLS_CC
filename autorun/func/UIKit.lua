-- UIKit.lua
-- Shared UI primitives for the training suite. Consolidates styled_button,
-- styled_header, COLORS, UI_THEME core, and argb_to_abgr — previously
-- copy-pasted across 8 scripts.
--
-- Usage: local UIKit = require("func/UIKit")
--   UIKit.styled_button(label, style, text_col)
--   UIKit.styled_header(label, style)
--   UIKit.plain_header(label)
--   UIKit.COLORS.Green, .Red, .White, etc.
--   UIKit.THEME.btn_neutral, .btn_green, .btn_red, .hdr_rainbow_red, etc.
--   UIKit.argb_to_abgr(argb_color)

local imgui = imgui
local M = {}

-- =========================================================
-- COLORS (ABGR) — canonical palette, identical across all scripts
-- =========================================================
M.COLORS = {
    White    = 0xFFDADADA,
    Green    = 0xFF00FF00,
    Red      = 0xFF0000FF,
    Grey     = 0x99FFFFFF,
    DarkGrey = 0xFF888888,
    Orange   = 0xFF00A5FF,
    Cyan     = 0xFFFFFF00,
    Yellow   = 0xFF00FFFF,
    Shadow   = 0xFF000000,
    Blue     = 0xFFFFAA00,
    Easy     = 0xFFFF9933,
    Medium   = 0xFF00FFFF,
    Hard     = 0xFF0000FF,
}

-- =========================================================
-- UI_THEME core — shared button and header styles
-- Scripts extend with their own entries: UIKit.THEME.my_header = {...}
-- =========================================================
M.THEME = {
    btn_neutral = { base = 0xFF444444, hover = 0xFF666666, active = 0xFF222222 },
    btn_green   = { base = 0xFF00AA00, hover = 0xFF00CC22, active = 0xFF007700 },
    btn_red     = { base = 0xFF0000CC, hover = 0xFF2222FF, active = 0xFF000099 },

    btn_easy    = { base = 0xFFFF8800, hover = 0xFFFFAA33, active = 0xFFCC6600 },
    btn_medium  = { base = 0xFF00FFFF, hover = 0xFF66FFFF, active = 0xFF00CCCC },
    btn_hard    = { base = 0xFF0000FF, hover = 0xFF4444FF, active = 0xFF0000AA },

    -- Reusable header palettes (named by color, not by section)
    hdr_dark_purple = { base = 0xFF5C314C, hover = 0xFF774262, active = 0xFF432238 },
    hdr_gold    = { base = 0xFFDB9834, hover = 0xFFE6A94D, active = 0xFFC78320 },
    hdr_purple  = { base = 0xFFB6599B, hover = 0xFFC770AC, active = 0xFFA04885 },
    hdr_blue    = { base = 0xFF5D6DDA, hover = 0xFF7382E6, active = 0xFF4555C9 },
    hdr_green   = { base = 0xFF9CBC1A, hover = 0xFFAED12B, active = 0xFF8AA814 },
    hdr_skyblue = { base = 0xFF4DA6FF, hover = 0xFF80BFFF, active = 0xFF0073E6 },

    -- Seven-step rainbow for same-level menu sections, ordered top to bottom.
    -- Values use ImGui's ABGR layout.
    hdr_rainbow_red    = { base = 0xFF4C4CC9, hover = 0xFF6464D8, active = 0xFF3A3AA9 },
    hdr_rainbow_orange = { base = 0xFF327CD4, hover = 0xFF4D94E2, active = 0xFF2662AF },
    hdr_rainbow_yellow = { base = 0xFF2496B5, hover = 0xFF3DAAC7, active = 0xFF1A7892 },
    hdr_rainbow_green  = { base = 0xFF5A9639, hover = 0xFF70AB51, active = 0xFF44752B },
    hdr_rainbow_cyan   = { base = 0xFF9D9731, hover = 0xFFB1AB49, active = 0xFF7B7626 },
    hdr_rainbow_blue   = { base = 0xFFB87547, hover = 0xFFCB8A5E, active = 0xFF915A35 },
    hdr_rainbow_violet = { base = 0xFFAE567D, hover = 0xFFC16D94, active = 0xFF874060 },
}

-- =========================================================
-- STYLED WIDGETS
-- =========================================================
function M.styled_button(label, style, text_col)
    imgui.push_style_color(21, style.base)
    imgui.push_style_color(22, style.hover)
    imgui.push_style_color(23, style.active)
    if text_col then imgui.push_style_color(0, text_col) end
    local clicked = imgui.button(label)
    if text_col then imgui.pop_style_color(1) end
    imgui.pop_style_color(3)
    return clicked
end

function M.translucent_header(style, base_alpha, hover_alpha, active_alpha)
    style = style or M.THEME.hdr_dark_purple
    local function with_alpha(color, alpha)
        return ((alpha & 0xFF) << 24) | ((tonumber(color) or 0) & 0x00FFFFFF)
    end
    return {
        base = with_alpha(style.base, base_alpha or 0x38),
        hover = with_alpha(style.hover, hover_alpha or 0x58),
        active = with_alpha(style.active, active_alpha or 0x78),
    }
end

function M.styled_header(label, style)
    imgui.push_style_color(24, style.base)
    imgui.push_style_color(25, style.hover)
    imgui.push_style_color(26, style.active)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

function M.plain_header(label)
    imgui.push_style_color(24, 0x00000000)
    imgui.push_style_color(25, 0x00000000)
    imgui.push_style_color(26, 0x00000000)
    local is_open = imgui.collapsing_header(label)
    imgui.pop_style_color(3)
    return is_open
end

-- =========================================================
-- COLOR CONVERSION
-- =========================================================
function M.argb_to_abgr(argb)
    local a = (argb >> 24) & 0xFF
    local r = (argb >> 16) & 0xFF
    local g = (argb >> 8) & 0xFF
    local b = argb & 0xFF
    return (a << 24) | (b << 16) | (g << 8) | r
end

return M
