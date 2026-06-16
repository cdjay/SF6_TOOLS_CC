local sdk = sdk
local re = re
local imgui = imgui

local SCALE_DIST = 65536.0

local tp_p1_border = false
local tp_p2_border = true
local teleport_target_dist = 184.000
local pending_tp = { active = false, distance = 0.0, attempts = 0, expected_c2c = 0.0 }
local status_msg = ""
local status_timer = 0
local copied_timer = 0
local show_floating = false

local distances = { cc = 0.0, cb = 0.0, bb = 0.0 }
local p1_front = 0.0
local p2_front = 0.0

local COL_ACTIVE = 0xFF00FF00
local COL_INACTIVE = 0xFF888888

local function get_front_edge_offset(player, is_on_left)
    if not player or not player.pos or not player.mpActParam or not player.mpActParam.Collision then return 0.0 end
    local col = player.mpActParam.Collision
    local px = player.pos.x.v / 6553600.0
    local best_offset = 0.0
    local found = false

    if col.Infos and col.Infos._items then
        for _, r in pairs(col.Infos._items) do
            if r and (r:get_field("Attr") ~= nil or r:get_field("HitNo") ~= nil) then
                local box_x = (r.OffsetX and r.OffsetX.v) and (r.OffsetX.v / 6553600.0) or 0.0
                local size_x = (r.SizeX and r.SizeX.v) and (r.SizeX.v / 6553600.0) or 0.0

                if is_on_left then
                    local offset = (box_x + size_x) - px
                    if not found or offset > best_offset then best_offset = offset; found = true end
                else
                    local offset = px - (box_x - size_x)
                    if not found or offset > best_offset then best_offset = offset; found = true end
                end
            end
        end
    end
    if not found then return 0.0 end
    return best_offset * 100.0
end

local function _tp_update_fronts(p1, p2, p1_is_left)
    p1_front = get_front_edge_offset(p1, p1_is_left)
    p2_front = get_front_edge_offset(p2, not p1_is_left)
end

local function apply_teleport_exact(distance, is_retry)
    local gb = sdk.find_type_definition("gBattle")
    if not gb then return end

    local sP = gb:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end

    local p1 = sP.mcPlayer[0]
    local p2 = sP.mcPlayer[1]
    if not p1 or not p2 then return end

    local px1_raw = p1.pos.x.v
    local px2_raw = p2.pos.x.v
    local p1_is_left = px1_raw < px2_raw

    local p1_offset = tp_p1_border and get_front_edge_offset(p1, p1_is_left) or 0.0
    local p2_offset = tp_p2_border and get_front_edge_offset(p2, not p1_is_left) or 0.0

    local total_center_dist = distance + p1_offset + p2_offset

    local raw_total_dist = math.floor((total_center_dist * 65536.0) + 0.5)
    local current_mid_raw = math.floor((px1_raw + px2_raw) / 2.0)
    local half_raw = math.floor(raw_total_dist / 2.0)

    local p1_target_raw, p2_target_raw
    if p1_is_left then
        p1_target_raw = current_mid_raw - half_raw
        p2_target_raw = p1_target_raw + raw_total_dist
    else
        p2_target_raw = current_mid_raw - half_raw
        p1_target_raw = p2_target_raw + raw_total_dist
    end

    local max_bound_raw = 47841280
    local left_edge_raw = math.min(p1_target_raw, p2_target_raw)
    local right_edge_raw = math.max(p1_target_raw, p2_target_raw)

    if left_edge_raw < -max_bound_raw then
        local shift = -max_bound_raw - left_edge_raw
        p1_target_raw = p1_target_raw + shift
        p2_target_raw = p2_target_raw + shift
    elseif right_edge_raw > max_bound_raw then
        local shift = right_edge_raw - max_bound_raw
        p1_target_raw = p1_target_raw - shift
        p2_target_raw = p2_target_raw - shift
    end

    local p1_pos_double = p1_target_raw / 65536.0
    local p2_pos_double = p2_target_raw / 65536.0

    local sfix_type = sdk.find_type_definition("via.sfix")
    if sfix_type then
        local sfix_from_double = sfix_type:get_method("From(System.Double)")
        if p1 and p1.POS_SETx then p1:POS_SETx(sfix_from_double:call(nil, p1_pos_double)) end
        if p2 and p2.POS_SETx then p2:POS_SETx(sfix_from_double:call(nil, p2_pos_double)) end
    end

    if not is_retry then
        pending_tp.active = true
        pending_tp.distance = distance
        pending_tp.expected_c2c = total_center_dist
        pending_tp.attempts = 0

        status_msg = string.format("APPLIED: %.5f (P1:%s P2:%s)", distance, tp_p1_border and "B" or "C", tp_p2_border and "B" or "C")
        status_timer = 150
    end
end

re.on_frame(function()
    local gb = sdk.find_type_definition("gBattle")
    if not gb then return end

    local sP = gb:get_field("Player"):get_data(nil)
    if not sP or not sP.mcPlayer then return end

    local p1 = sP.mcPlayer[0]
    local p2 = sP.mcPlayer[1]
    if not p1 or not p2 then return end

    local p1_x = p1.pos and p1.pos.x and p1.pos.x.v and (p1.pos.x.v / SCALE_DIST) or 0
    local p2_x = p2.pos and p2.pos.x and p2.pos.x.v and (p2.pos.x.v / SCALE_DIST) or 0
    local p1_is_left = p1_x < p2_x

    local cc = math.abs(p1_x - p2_x)
    pcall(_tp_update_fronts, p1, p2, p1_is_left)
    distances.cc = cc
    distances.bc = cc - p1_front
    distances.cb = cc - p2_front

    if pending_tp.active then
        if math.abs(cc - pending_tp.expected_c2c) > 0.5 then
            pending_tp.attempts = pending_tp.attempts + 1
            if pending_tp.attempts < 15 then
                apply_teleport_exact(pending_tp.distance, true)
            else
                pending_tp.active = false
            end
        else
            pending_tp.active = false
        end
    end

    if status_timer > 0 then status_timer = status_timer - 1 end
    if copied_timer > 0 then copied_timer = copied_timer - 1 end
end)

local modes = {
    { label = "P1 Center - P2 Center", p1b = false, p2b = false, dist_key = "cc" },
    { label = "P1 Center - P2 Border", p1b = false, p2b = true,  dist_key = "cb" },
    { label = "P1 Border - P2 Center", p1b = true,  p2b = false, dist_key = "bc" },
}

local function draw_teleport_ui(suffix)
    local sf = suffix or ""
    for i, mode in ipairs(modes) do
        if i > 1 then imgui.same_line() end
        local is_active = (tp_p1_border == mode.p1b and tp_p2_border == mode.p2b)
        if is_active then
            imgui.push_style_color(21, 0xFF006600)
            imgui.push_style_color(22, 0xFF008800)
            imgui.push_style_color(23, 0xFF00AA00)
        end
        if imgui.button(mode.label .. "##" .. sf) then
            tp_p1_border = mode.p1b
            tp_p2_border = mode.p2b
        end
        if is_active then imgui.pop_style_color(3) end
    end

    local active_key = "cc"
    for _, mode in ipairs(modes) do
        if tp_p1_border == mode.p1b and tp_p2_border == mode.p2b then active_key = mode.dist_key; break end
    end
    local dist_val = distances[active_key] or 0
    local dist_str = string.format("%.5f", dist_val)

    imgui.text_colored(dist_str, COL_ACTIVE)
    imgui.same_line()
    if imgui.button("COPY##tp_copy" .. sf) then
        teleport_target_dist = tonumber(dist_str) or teleport_target_dist
        copied_timer = 90
    end
    if copied_timer > 0 then
        imgui.same_line()
        imgui.text_colored("已复制!", 0xFF00FFFF)
    end

    local t_str = tostring(teleport_target_dist)
    imgui.push_item_width(120)
    local changed, new_t = imgui.input_text("Target##" .. sf, t_str)
    imgui.pop_item_width()
    if changed then local n = tonumber(new_t); if n then teleport_target_dist = n end end
    imgui.same_line()
    if imgui.button("TELEPORT##tp_apply" .. sf) then apply_teleport_exact(teleport_target_dist) end

    if status_timer > 0 then
        imgui.text_colored(status_msg, 0xFFFFFF00)
    end
end

re.on_draw_ui(function()
    if imgui.tree_node("SF6 TELEPORT") then
        local c_fl, v_fl = imgui.checkbox("Floating Window##tp_float", show_floating)
        if c_fl then show_floating = v_fl end
        imgui.separator()
        draw_teleport_ui("ref")
        imgui.tree_pop()
    end
end)

re.on_frame(function()
    if show_floating then
        if imgui.begin_window("SF6 TELEPORT##float", true, 64) then
            local c_fl, v_fl = imgui.checkbox("Floating Window##tp_float2", show_floating)
            if c_fl then show_floating = v_fl end
            imgui.separator()
            draw_teleport_ui("float")
            imgui.end_window()
        end
    end
end)
