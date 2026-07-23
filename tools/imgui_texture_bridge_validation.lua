-- Manual validation overlay for reframework-imgui-texture.
-- Copy to reframework/autorun only while collecting the 24/32/40 px screenshot.

local ICONS = {
    "1.png",
    "2.png",
    "2_HOLD.png",
    "6.png",
    "6_HOLD.png",
    "mp.png",
    "hp.png",
    "modern_m.png",
    "dr.png",
    "di.png",
}

local state = {
    initialized = false,
    api_missing_logged = false,
    entries = {},
}

local function log_once(message)
    if state.api_missing_logged then
        return
    end
    state.api_missing_logged = true
    log.error("[imgui-texture-validation] " .. message)
end

local function initialize()
    if state.initialized then
        return true
    end
    if type(texture) ~= "table" or
       type(texture.load) ~= "function" or
       type(texture.draw) ~= "function" or
       type(texture.size) ~= "function" then
        log_once("texture bridge API 未加载")
        return false
    end

    for _, name in ipairs(ICONS) do
        local handle, load_error =
            texture.load("buttonsAndArrows/" .. name)
        local width, height = 0, 0
        if handle then
            width, height = texture.size(handle)
        end
        table.insert(state.entries, {
            name = name,
            handle = handle,
            error = load_error,
            width = width or 0,
            height = height or 0,
        })
    end
    state.initialized = true
    return true
end

local function add_text(draw_list, x, y, color, text)
    draw_list:add_text(Vector2f.new(x, y), color, text)
end

re.on_frame(function()
    if not initialize() then
        return
    end

    local draw_list = imgui.get_background_draw_list()
    if not draw_list then
        return
    end

    local origin_x = 44
    local origin_y = 72
    local label_width = 150
    local native_size = 80
    local row_height = 88
    local columns = {
        { label = "PNG 80", size = 80 },
        { label = "24 px", size = 24 },
        { label = "32 px", size = 32 },
        { label = "40 px", size = 40 },
    }

    add_text(
        draw_list,
        origin_x,
        origin_y - 42,
        0xFFFFFFFF,
        "reframework-imgui-texture / original PNG comparison"
    )

    local column_x = origin_x + label_width
    for _, column in ipairs(columns) do
        add_text(
            draw_list,
            column_x,
            origin_y - 20,
            0xFFFFFFFF,
            column.label
        )
        column_x = column_x + native_size + 24
    end

    for row, entry in ipairs(state.entries) do
        local y = origin_y + (row - 1) * row_height
        local size_text = string.format(
            "%s  (%dx%d)",
            entry.name,
            entry.width,
            entry.height
        )
        add_text(draw_list, origin_x, y + 28, 0xFFFFFFFF, size_text)

        local x = origin_x + label_width
        for _, column in ipairs(columns) do
            if entry.handle then
                texture.draw(
                    entry.handle,
                    x,
                    y,
                    column.size,
                    column.size
                )
            else
                add_text(
                    draw_list,
                    x,
                    y + 8,
                    0xFF4040FF,
                    "[load failed]"
                )
            end
            x = x + native_size + 24
        end
    end
end)
