local captured = {}

Vector2f = {
    new = function(x, y)
        return { x = x, y = y }
    end
}

local draw_list = {
    add_rect_filled = function(_, _, _, color)
        captured.fill = color
    end,
    add_rect = function(_, _, _, color)
        captured.outline = color
    end,
    add_line = function(_, _, _, color)
        captured.line = color
    end,
    add_text = function(_, _, color)
        captured.text = color
    end
}

imgui = {
    get_background_draw_list = function()
        return draw_list
    end,
    load_font = function(filename, size)
        captured.font_filename = filename
        captured.font_size = size
        return { filename = filename, size = size }
    end,
    push_font = function() end,
    pop_font = function() end,
    calc_text_size = function()
        return { x = 10, y = 24 }
    end
}

local Canvas = assert(loadfile("autorun/func/ImGuiCanvas.lua"))()

assert(Canvas.argb_to_abgr(0xFFFFA000) == 0xFF00A0FF,
    "D2D orange ARGB must become ImGui orange ABGR")
assert(Canvas.argb_to_abgr(0x7F123456) == 0x7F563412,
    "ARGB conversion must preserve alpha and swap red/blue")
assert(Canvas.argb_to_abgr(0xFF888888) == 0xFF888888,
    "grayscale colors must remain unchanged")

assert(Canvas.begin_frame(), "mock draw list must initialize")
Canvas.fill_rect(1, 2, 3, 4, 0xFFFFA000)
Canvas.outline_rect(1, 2, 3, 4, 1, 0xFF112233)
Canvas.line(1, 2, 3, 4, 1, 0x80123456)
assert(captured.fill == 0xFF00A0FF, "filled rectangles must convert D2D colors")
assert(captured.outline == 0xFF332211, "outlines must convert D2D colors")
assert(captured.line == 0x80563412, "lines must convert D2D colors")

local font = assert(Canvas.Font.new("msyhbd.ttc", 18))
assert(captured.font_filename == "msyhbd.ttc", "font filename must be preserved")
assert(captured.font_size == 24, "18px D2D text must load at the equivalent 24px ImGui size")
assert(font.requested_size == 18 and font.size == 24,
    "font must retain both configured and rendered sizes")

Canvas.text(font, "完美", 1, 2, 0xFFFFA500)
assert(captured.text == 0xFF00A5FF, "text must convert D2D colors")

print("ImGui canvas compatibility tests passed")
