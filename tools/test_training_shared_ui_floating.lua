local captured = {
    colors = {},
    pop_color_count = 0,
    font_loads = 0,
}

Vector2f = {
    new = function(x, y)
        return { x = x, y = y }
    end
}

imgui = {
    get_display_size = function()
        return 1920, 1080
    end,
    load_font = function(filename, size)
        captured.font_loads = captured.font_loads + 1
        return { filename = filename, size = size }
    end,
    push_font = function() end,
    pop_font = function() end,
    push_style_color = function(index, color)
        captured.colors[index] = color
    end,
    pop_style_color = function(count)
        captured.pop_color_count = count
    end,
    push_style_var = function() end,
    pop_style_var = function(count)
        captured.pop_var_count = count
    end,
    set_next_window_size = function(value)
        captured.window_size = value
    end,
    set_next_window_pos = function(value)
        captured.window_pos = value
    end,
    begin_window = function()
        return true
    end,
    end_window = function()
        captured.ended = true
    end,
    set_cursor_pos = function(value)
        captured.cursor_pos = value
    end,
    button = function(label, size)
        captured.button_label = label
        captured.button_size = size
        return false
    end,
}

local SharedUI = assert(loadfile("autorun/func/Training_SharedUI.lua"))()
assert(SharedUI.set_floating_width_pct(0.57) == 0.57,
    "shared floating width must accept the ComboTrials bar width")
local visible, sw, sh = SharedUI.begin_floating_window("test")
local shared_ui_font, shared_button_font = SharedUI.get_floating_fonts(sh)

assert(visible and sw == 1920 and sh == 1080, "floating bar must use the display dimensions")
assert(shared_ui_font and shared_button_font and captured.font_loads == 2,
    "shared floating fonts must be reusable without duplicate loading")
assert(math.abs(captured.window_size.x - 1094.4) < 0.001,
    "floating bar must use the published ComboTrials width")
assert(math.abs(captured.window_size.y - 47.952) < 0.001, "floating bar height must remain 4.44%")
assert(math.abs(captured.window_pos.x - 412.8) < 0.001,
    "floating bar must remain centered at the published width")
assert(math.abs(captured.cursor_pos.x - 19.2) < 0.001
    and math.abs(captured.cursor_pos.y - 10.8) < 0.001,
    "floating controls must use the ComboTrials centered baseline")
assert(captured.colors[7] == 0xFF363433
    and captured.colors[8] == 0xFF4C4845
    and captured.colors[9] == 0xFF2E2B29,
    "floating selectors must have base, hover, and active backgrounds")

SharedUI.end_floating_window()
assert(captured.ended == true, "floating window must close")
assert(captured.pop_color_count == 5 and captured.pop_var_count == 2,
    "floating style stack must remain balanced")

SharedUI.sf6_button("X##test", {
    base = 0xFF000000,
    hover = 0xFF111111,
    active = 0xFF222222,
    border = 0xFFFFFFFF,
}, 32, 32)
assert(captured.button_size.x == 32 and captured.button_size.y == 32,
    "top-bar close control must support an explicit square size")

print("training shared UI floating tests passed")
